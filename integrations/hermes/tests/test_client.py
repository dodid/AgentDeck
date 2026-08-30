from __future__ import annotations

import asyncio
import logging

import pytest

from r2_relay_adapter.client import PreconditionFailedError, R2RelayClient, normalize_etag


class _Body:
    def __init__(self, parts):
        self._parts = list(parts)

    def __aiter__(self):
        async def _iterate():
            for part in self._parts:
                yield part
        return _iterate()


class _S3Stub:
    def __init__(self):
        self.calls = []
        self.responses = []

    async def put_object(self, **kwargs):
        self.calls.append(("put_object", kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    async def get_object(self, **kwargs):
        self.calls.append(("get_object", kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    async def head_object(self, **kwargs):
        self.calls.append(("head_object", kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    async def delete_object(self, **kwargs):
        self.calls.append(("delete_object", kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    async def delete_objects(self, **kwargs):
        self.calls.append(("delete_objects", kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    async def list_objects_v2(self, **kwargs):
        self.calls.append(("list_objects_v2", kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


class _SyncBody:
    def __init__(self, parts):
        self._parts = list(parts)

    def iter_chunks(self, chunk_size=1024):
        del chunk_size
        for part in self._parts:
            yield part


class _SyncS3Stub:
    def __init__(self):
        self.calls = []
        self.responses = []

    def put_object(self, **kwargs):
        self.calls.append(("put_object", kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    def get_object(self, **kwargs):
        self.calls.append(("get_object", kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    def head_object(self, **kwargs):
        self.calls.append(("head_object", kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    def delete_object(self, **kwargs):
        self.calls.append(("delete_object", kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    def delete_objects(self, **kwargs):
        self.calls.append(("delete_objects", kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    def list_objects_v2(self, **kwargs):
        self.calls.append(("list_objects_v2", kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


class _ClientError(Exception):
    def __init__(self, code: str, status: int, *, operation_name: str = "PutObject"):
        self.response = {
            "Error": {"Code": code},
            "ResponseMetadata": {"HTTPStatusCode": status},
        }
        self.operation_name = operation_name
        super().__init__(code)


@pytest.mark.asyncio
async def test_put_object_retries_without_tagging_for_not_implemented():
    s3 = _S3Stub()
    s3.responses = [
        _ClientError("NotImplemented", 501),
        {"ETag": '"etag-1"'},
    ]
    client = R2RelayClient(bucket="demo", s3_client=s3)

    result = await client.put_object("k", "body", "text/plain", tagging="a=b")

    assert result == {"ETag": '"etag-1"'}
    assert len(s3.calls) == 2
    first = s3.calls[0][1]
    second = s3.calls[1][1]
    assert first["Tagging"] == "a=b"
    assert "Tagging" not in second


@pytest.mark.asyncio
async def test_put_object_raises_precondition_failed_error_on_412():
    s3 = _S3Stub()
    s3.responses = [_ClientError("PreconditionFailed", 412)]
    client = R2RelayClient(bucket="demo", s3_client=s3)

    with pytest.raises(PreconditionFailedError):
        await client.put_object("k", "body")


@pytest.mark.asyncio
async def test_get_object_returns_none_for_missing_keys():
    s3 = _S3Stub()
    s3.responses = [_ClientError("NoSuchKey", 404, operation_name="GetObject")]
    client = R2RelayClient(bucket="demo", s3_client=s3)

    result = await client.get_object("missing")

    assert result is None


@pytest.mark.asyncio
async def test_get_object_logs_missing_keys(caplog):
    s3 = _S3Stub()
    s3.responses = [_ClientError("NoSuchKey", 404, operation_name="GetObject")]
    client = R2RelayClient(bucket="demo", s3_client=s3)

    with caplog.at_level(logging.DEBUG, logger='r2_relay_adapter.client'):
        result = await client.get_object("missing")

    assert result is None
    assert 'r2 get_object missing key=missing' in caplog.text


@pytest.mark.asyncio
async def test_get_json_with_etag_reads_async_body_and_normalizes_etag():
    s3 = _S3Stub()
    s3.responses = [{"Body": _Body([b'{"ok":', b' true}']), "ETag": '"abc"'}]
    client = R2RelayClient(bucket="demo", s3_client=s3)

    result = await client.get_json_with_etag("state.json")

    assert result == {"body": {"ok": True}, "etag": "abc"}


@pytest.mark.asyncio
async def test_list_prefix_page_returns_expected_shape():
    s3 = _S3Stub()
    s3.responses = [{
        "Contents": [{"Key": "msg/a"}],
        "NextContinuationToken": "next-token",
        "IsTruncated": True,
    }]
    client = R2RelayClient(bucket="demo", s3_client=s3)

    result = await client.list_prefix_page("msg/")

    assert result == {
        "contents": [{"Key": "msg/a"}],
        "next_continuation_token": "next-token",
        "is_truncated": True,
    }


@pytest.mark.asyncio
async def test_put_attachment_uses_attachment_key_and_content_metadata():
    s3 = _S3Stub()
    s3.responses = [{"ETag": '"etag-att"'}]
    client = R2RelayClient(bucket="demo", s3_client=s3)

    result = await client.put_attachment(
        "att/peer-1/9999999999876-msg-01-photo.png",
        b"png-bytes",
        content_type="image/png",
    )

    assert result == {"ETag": '"etag-att"'}
    op, kwargs = s3.calls[0]
    assert op == "put_object"
    assert kwargs["Key"] == "att/peer-1/9999999999876-msg-01-photo.png"
    assert kwargs["ContentType"] == "image/png"
    assert kwargs["IfNoneMatch"] == "*"


@pytest.mark.asyncio
async def test_put_object_supports_sync_boto3_client_methods():
    s3 = _SyncS3Stub()
    s3.responses = [{"ETag": '"etag-sync"'}]
    client = R2RelayClient(bucket="demo", s3_client=s3)

    result = await client.put_object("k", "body", "text/plain")

    assert result == {"ETag": '"etag-sync"'}
    assert s3.calls == [(
        "put_object",
        {"Bucket": "demo", "Key": "k", "Body": "body", "ContentType": "text/plain"},
    )]


@pytest.mark.asyncio
async def test_get_json_with_etag_supports_sync_boto3_streaming_body():
    s3 = _SyncS3Stub()
    s3.responses = [{"Body": _SyncBody([b'{"ok":', b' true}']), "ETag": '"sync-etag"'}]
    client = R2RelayClient(bucket="demo", s3_client=s3)

    result = await client.get_json_with_etag("state.json")

    assert result == {"body": {"ok": True}, "etag": "sync-etag"}


@pytest.mark.asyncio
async def test_get_attachment_returns_none_for_missing_key():
    s3 = _S3Stub()
    s3.responses = [_ClientError("NoSuchKey", 404, operation_name="GetObject")]
    client = R2RelayClient(bucket="demo", s3_client=s3)

    result = await client.get_attachment("att/missing")

    assert result is None


def test_normalize_etag_strips_quotes():
    assert normalize_etag('"abc"') == "abc"
    assert normalize_etag(None) is None
