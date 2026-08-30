from __future__ import annotations

from typing import Any


def parse_relay_target(value: str) -> tuple[str, str | None]:
    raw = str(value or '').strip()
    if not raw:
        return '', None
    if '=' not in raw:
        return raw, None

    peer: str | None = None
    conversation_id: str | None = None
    for segment in raw.split(','):
        trimmed = segment.strip()
        if not trimmed:
            continue
        if '=' not in trimmed:
            return raw, None
        key, parsed = trimmed.split('=', 1)
        key = key.strip().lower()
        parsed = parsed.strip()
        if key == 'peer' and parsed:
            peer = parsed
        elif key == 'conversation' and parsed:
            conversation_id = parsed
    return peer or raw, conversation_id


def build_source_chat_id(peer: str, conversation_id: str | None) -> str:
    if conversation_id:
        return f'peer={peer},conversation={conversation_id}'
    return peer


def new_stream_id(service: Any | None = None) -> str:
    relay = getattr(service, 'relay', None)
    short_uuid = getattr(relay, 'short_uuid', None)
    if callable(short_uuid):
        return str(short_uuid())

    import time

    return f'stream-{int(time.time() * 1000)}'
