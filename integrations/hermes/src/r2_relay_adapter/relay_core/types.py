from __future__ import annotations

from typing import Any, TypedDict


JSONDict = dict[str, Any]


class AttachmentRef(TypedDict, total=False):
    id: str
    key: str
    file_name: str | None
    content_type: str | None
    size: int | None
    sha256: str | None
    kind: str
    width: int | None
    height: int | None
    duration_ms: int | None
    preview_image_key: str | None
    preview_image_type: str | None
    preview_size: int | None


class RelayRoute(TypedDict, total=False):
    agent_id: str
    conversation_id: str | None
    instance_id: str | None


class RelayDeliveryStream(TypedDict):
    stream_id: str
    seq: int
    state: str


class RelayDelivery(TypedDict, total=False):
    stream: RelayDeliveryStream | None


class RelayMessageStatus(TypedDict, total=False):
    state: str
    processed_at: int | None
    processed_by: str | None
    error: str | None


class RelayMessage(TypedDict, total=False):
    msg_id: str
    from_: str
    to: str
    ts_sent: int
    prev_key: str | None
    route: RelayRoute
    content: JSONDict
    delivery: RelayDelivery | None
    status: RelayMessageStatus | None
    size: int | None


MessageDocument = RelayMessage


class HeadDocument(TypedDict, total=False):
    head_key: str
    head_msg_id: str
    head_ts: int


class HeadState(TypedDict, total=False):
    body: HeadDocument
    etag: str | None


class InboxMessage(TypedDict):
    key: str
    message: JSONDict


class InboxBatch(TypedDict):
    head: HeadDocument | None
    messages: list[InboxMessage]


class CheckpointState(TypedDict):
    last_head_key: str | None
    seen: list[str]
    seen_msg_ids: list[str]
