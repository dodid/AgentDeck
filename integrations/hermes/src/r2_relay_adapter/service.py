"""Relay service logic shared by the Hermes R2 adapter."""

from __future__ import annotations

import json
import mimetypes
import time
from pathlib import Path
from typing import Any

from gateway.platforms.base import cache_audio_from_bytes, cache_document_from_bytes, cache_image_from_bytes
from .relay_core import R2RelayService as _SharedR2RelayService
from .relay_core import extract_timestamp_from_relay_key

IDENTITY_REFRESH_INTERVAL_MS = 12 * 60 * 60 * 1000


class R2RelayService(_SharedR2RelayService):
    def __init__(
        self,
        client: Any,
        relay: Any,
        peer_id: str,
        checkpoint_store: Any | None = None,
    ) -> None:
        super().__init__(
            store=client,
            keyspace=relay,
            peer_id=peer_id,
            checkpoint_store=checkpoint_store,
        )
        self.client = client
        self.relay = relay
        self._published_identity_signature: str | None = None
        self._published_identity: dict[str, Any] | None = None
        self._published_identity_at_ms = 0

    async def publish_identity(self, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        signature = _identity_signature(payload)
        now_ms = _now_ms()
        heartbeat_due = now_ms - self._published_identity_at_ms >= IDENTITY_REFRESH_INTERVAL_MS
        if (
            self._published_identity_signature == signature
            and self._published_identity is not None
            and not heartbeat_due
        ):
            return dict(self._published_identity)
        identity = await super().publish_identity(payload)
        self._published_identity_signature = signature
        self._published_identity = dict(identity)
        self._published_identity_at_ms = now_ms
        return identity

    async def store_attachment(
        self,
        recipient: str,
        message_id: str,
        index: int,
        data: bytes,
        file_name: str | None = None,
        content_type: str | None = None,
        now_ms: int | None = None,
    ) -> dict[str, Any]:
        resolved_name = _normalize_file_name(file_name, content_type)
        resolved_type = _resolve_content_type(content_type, resolved_name)
        key = self.keyspace.make_att_key(recipient, message_id, index, name=resolved_name, now_ms=now_ms)
        put_attachment = getattr(self.store, 'put_attachment', None)
        if callable(put_attachment):
            await put_attachment(key, data, content_type=resolved_type)
        else:
            await self.store.put_object(key, data, resolved_type, if_none_match='*')
        return {
            'id': f'att-{message_id}-{index}',
            'key': key,
            'file_name': resolved_name,
            'content_type': resolved_type,
            'size': len(data),
            'sha256': None,
            'kind': _classify_attachment_kind(resolved_type),
            'width': None,
            'height': None,
            'duration_ms': None,
            'preview_image_key': None,
            'preview_image_type': None,
            'preview_size': None,
        }

    async def fetch_attachment(
        self,
        key: str,
        file_name: str | None = None,
        content_type: str | None = None,
    ) -> dict[str, Any] | None:
        fetch_attachment = getattr(self.store, 'get_attachment', None)
        if callable(fetch_attachment):
            response = await fetch_attachment(key)
        else:
            response = await self.store.get_object(key)
        if response is None:
            return None
        body = response.get('Body') if isinstance(response, dict) else None
        if body is None:
            return None
        data = await _body_to_bytes(body)
        resolved_type = _resolve_content_type(
            response.get('ContentType') if isinstance(response, dict) else None,
            file_name,
            fallback=content_type,
        )
        resolved_name = _normalize_file_name(file_name, resolved_type)
        cached_path = _cache_attachment_bytes(data, resolved_name, resolved_type)
        return {
            'key': key,
            'file_path': cached_path,
            'file_name': resolved_name,
            'content_type': resolved_type,
            'message_type': _message_type_name_for_content_type(resolved_type),
            'size': len(data),
        }


async def _body_to_bytes(body: Any) -> bytes:
    chunks = await _body_to_chunks(body)
    return b''.join(chunks)


async def _body_to_chunks(body: Any) -> list[bytes]:
    if hasattr(body, '__aiter__'):
        chunks: list[bytes] = []
        async for chunk in body:
            if isinstance(chunk, bytes):
                chunks.append(chunk)
            else:
                chunks.append(bytes(chunk))
        return chunks
    import asyncio

    return await asyncio.to_thread(_sync_body_to_chunks, body)


def _sync_body_to_chunks(body: Any) -> list[bytes]:
    if hasattr(body, 'iter_chunks') and callable(body.iter_chunks):
        iterator = body.iter_chunks()
    elif hasattr(body, 'read') and callable(body.read):
        data = body.read()
        if data is None:
            return []
        iterator = [data]
    elif hasattr(body, '__iter__'):
        iterator = iter(body)
    else:
        raise TypeError(f'Unsupported response body type: {type(body)!r}')

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


def _normalize_file_name(file_name: str | None, content_type: str | None = None) -> str:
    safe_name = Path(str(file_name or '').strip()).name
    if safe_name and safe_name not in {'.', '..'}:
        return safe_name
    guessed_ext = _guess_extension(content_type)
    return f'attachment{guessed_ext}'


def _resolve_content_type(content_type: str | None, file_name: str | None, fallback: str | None = None) -> str:
    if content_type:
        return content_type
    if file_name:
        guessed, _encoding = mimetypes.guess_type(file_name)
        if guessed:
            return guessed
    return fallback or 'application/octet-stream'


def _guess_extension(content_type: str | None) -> str:
    if not content_type:
        return ''
    guessed = mimetypes.guess_extension(content_type, strict=False)
    return guessed or ''


def _classify_attachment_kind(content_type: str | None) -> str:
    if not content_type:
        return 'unknown'
    if content_type.startswith('image/'):
        return 'image'
    if content_type.startswith('video/'):
        return 'video'
    if content_type.startswith('audio/'):
        return 'audio'
    return 'file'


def _message_type_name_for_content_type(content_type: str | None) -> str:
    kind = _classify_attachment_kind(content_type)
    if kind == 'image':
        return 'photo'
    if kind == 'video':
        return 'video'
    if kind == 'audio':
        return 'audio'
    return 'document'


def _cache_attachment_bytes(data: bytes, file_name: str, content_type: str | None) -> str:
    extension = Path(file_name).suffix or _guess_extension(content_type) or '.bin'
    kind = _classify_attachment_kind(content_type)
    if kind == 'image':
        try:
            return cache_image_from_bytes(data, extension)
        except ValueError:
            return cache_document_from_bytes(data, file_name)
    if kind == 'audio':
        return cache_audio_from_bytes(data, extension)
    return cache_document_from_bytes(data, file_name)


def _identity_signature(payload: dict[str, Any] | None) -> str:
    if payload is None:
        return 'null'
    return json.dumps(payload, sort_keys=True, separators=(',', ':'), ensure_ascii=True)


def _now_ms() -> int:
    return int(time.time() * 1000)
