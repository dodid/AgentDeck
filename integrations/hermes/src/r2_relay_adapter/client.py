"""Async Cloudflare R2 client helpers for the relay adapter."""

from __future__ import annotations

import asyncio
import inspect
import json
import logging
from typing import Any

from .config import R2RelayEnvConfig


logger = logging.getLogger(__name__)


class PreconditionFailedError(RuntimeError):
    """Raised when an object-store CAS precondition fails."""


def normalize_etag(etag: str | None) -> str | None:
    if not etag:
        return None
    normalized = etag.strip().strip('"')
    return normalized or None


class R2RelayClient:
    def __init__(
        self,
        bucket: str,
        s3_client: Any,
    ) -> None:
        self.bucket = bucket
        self.s3 = s3_client

    async def _call_s3(self, method_name: str, **kwargs: Any) -> Any:
        method = getattr(self.s3, method_name)
        result = method(**kwargs)
        if inspect.isawaitable(result):
            return await result
        return await asyncio.to_thread(lambda: result)

    @classmethod
    def from_env_config(cls, config: R2RelayEnvConfig) -> "R2RelayClient":
        return cls(bucket=config.bucket, s3_client=config.create_s3_client())

    async def put_object(
        self,
        key: str,
        body: bytes | str,
        content_type: str | None = None,
        tagging: str | None = None,
        if_match: str | None = None,
        if_none_match: str | None = None,
    ) -> Any:
        params: dict[str, Any] = {
            "Bucket": self.bucket,
            "Key": key,
            "Body": body,
        }
        if content_type:
            params["ContentType"] = content_type
        if tagging:
            params["Tagging"] = tagging
        if if_match:
            params["IfMatch"] = if_match
        if if_none_match:
            params["IfNoneMatch"] = if_none_match
        logger.debug(
            "r2 put_object key=%s content_type=%s if_match=%s if_none_match=%s tagging=%s body_len=%s",
            key,
            content_type,
            if_match,
            if_none_match,
            bool(tagging),
            _body_length(body),
        )
        try:
            return await self._call_s3("put_object", **params)
        except Exception as err:
            code, status = _extract_error_code(err)
            if tagging and (code == "NotImplemented" or status == 501):
                logger.warning(
                    "r2 put_object retrying without tagging key=%s code=%s status=%s",
                    key,
                    code,
                    status,
                )
                retry_params = dict(params)
                retry_params.pop("Tagging", None)
                return await self._call_s3("put_object", **retry_params)
            if code == "PreconditionFailed" or status == 412:
                logger.debug("r2 put_object precondition failed key=%s code=%s status=%s", key, code, status)
                raise PreconditionFailedError("PreconditionFailed") from err
            logger.exception("r2 put_object failed key=%s code=%s status=%s", key, code, status)
            raise

    async def get_object(self, key: str) -> Any | None:
        try:
            response = await self._call_s3("get_object", Bucket=self.bucket, Key=key)
            logger.debug("r2 get_object hit key=%s", key)
            return response
        except Exception as err:
            code, status = _extract_error_code(err)
            if code in {"NoSuchKey", "NotFound"} or status == 404:
                logger.debug("r2 get_object missing key=%s code=%s status=%s", key, code, status)
                return None
            logger.exception("r2 get_object failed key=%s code=%s status=%s", key, code, status)
            raise

    async def head_object(self, key: str) -> Any | None:
        try:
            response = await self._call_s3("head_object", Bucket=self.bucket, Key=key)
            logger.debug("r2 head_object hit key=%s", key)
            return response
        except Exception as err:
            code, status = _extract_error_code(err)
            if code in {"NoSuchKey", "NotFound"} or status == 404:
                logger.debug("r2 head_object missing key=%s code=%s status=%s", key, code, status)
                return None
            logger.warning("r2 head_object failed key=%s code=%s status=%s", key, code, status)
            return None

    async def get_json_with_etag(self, key: str) -> dict[str, Any] | None:
        response = await self.get_object(key)
        if not response or not response.get("Body"):
            logger.debug("r2 get_json_with_etag missing_or_empty key=%s", key)
            return None
        body_text = await _body_to_text(response["Body"])
        parsed = {
            "body": json.loads(body_text),
            "etag": normalize_etag(response.get("ETag")),
        }
        logger.debug("r2 get_json_with_etag parsed key=%s etag=%s", key, parsed["etag"])
        return parsed

    async def delete_object(self, key: str) -> Any:
        logger.debug("r2 delete_object key=%s", key)
        return await self._call_s3("delete_object", Bucket=self.bucket, Key=key)

    async def delete_objects(self, keys: list[str]) -> Any:
        if not keys:
            return {"deleted": [], "errors": []}
        logger.debug("r2 delete_objects count=%s first_key=%s", len(keys), keys[0])
        return await self._call_s3(
            "delete_objects",
            Bucket=self.bucket,
            Delete={
                "Objects": [{"Key": key} for key in keys],
                "Quiet": True,
            },
        )

    async def list_prefix(self, prefix: str, max_keys: int = 100) -> list[Any]:
        logger.debug("r2 list_prefix prefix=%s max_keys=%s", prefix, max_keys)
        response = await self._call_s3("list_objects_v2", Bucket=self.bucket, Prefix=prefix, MaxKeys=max_keys)
        return response.get("Contents") or []

    async def list_prefix_page(
        self,
        prefix: str,
        continuation_token: str | None = None,
        max_keys: int = 1000,
    ) -> dict[str, Any]:
        logger.debug(
            "r2 list_prefix_page prefix=%s continuation_token=%s max_keys=%s",
            prefix,
            continuation_token,
            max_keys,
        )
        response = await self._call_s3(
            "list_objects_v2",
            Bucket=self.bucket,
            Prefix=prefix,
            MaxKeys=max_keys,
            ContinuationToken=continuation_token,
        )
        return {
            "contents": response.get("Contents") or [],
            "next_continuation_token": response.get("NextContinuationToken"),
            "is_truncated": bool(response.get("IsTruncated")),
        }

    async def put_attachment(
        self,
        key: str,
        body: bytes | str,
        content_type: str | None = None,
    ) -> Any:
        return await self.put_object(
            key,
            body,
            content_type=content_type,
            if_none_match='*',
        )

    async def get_attachment(self, key: str) -> Any | None:
        return await self.get_object(key)


async def _body_to_text(body: Any) -> str:
    chunks = await _body_to_chunks(body)
    return b"".join(chunks).decode("utf-8")


def _sync_body_to_chunks(body: Any) -> list[bytes]:
    if hasattr(body, "iter_chunks") and callable(body.iter_chunks):
        iterator = body.iter_chunks()
    elif hasattr(body, "read") and callable(body.read):
        data = body.read()
        if data is None:
            return []
        iterator = [data]
    elif hasattr(body, "__iter__"):
        iterator = iter(body)
    else:
        raise TypeError(f"Unsupported response body type: {type(body)!r}")

    chunks: list[bytes] = []
    for chunk in iterator:
        if isinstance(chunk, tuple) and chunk:
            chunk = chunk[0]
        if chunk is None:
            continue
        if isinstance(chunk, bytes):
            chunks.append(chunk)
        else:
            chunks.append(bytes(chunk))
    return chunks


async def _body_to_chunks(body: Any) -> list[bytes]:
    if hasattr(body, "__aiter__"):
        chunks: list[bytes] = []
        async for chunk in body:
            if isinstance(chunk, bytes):
                chunks.append(chunk)
            else:
                chunks.append(bytes(chunk))
        return chunks
    return await asyncio.to_thread(_sync_body_to_chunks, body)


def _extract_error_code(err: Exception) -> tuple[str | None, int | None]:
    response = getattr(err, "response", None) or {}
    error = response.get("Error", {}) if isinstance(response, dict) else {}
    metadata = response.get("ResponseMetadata", {}) if isinstance(response, dict) else {}
    return error.get("Code"), metadata.get("HTTPStatusCode")


def _body_length(body: bytes | str) -> int:
    if isinstance(body, bytes):
        return len(body)
    return len(body.encode("utf-8"))
