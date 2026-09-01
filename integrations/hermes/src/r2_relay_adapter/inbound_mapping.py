from __future__ import annotations

from typing import Any

from gateway.platforms.base import MessageType


def format_inbound_text(msg: dict[str, Any]) -> str:
    content = msg.get('content') or {}
    content_type = str(content.get('type') or 'text')

    if content_type == 'reaction':
        emoji = str(content.get('emoji') or '')
        target = str(content.get('target_msg_id') or 'unknown')
        if content.get('remove'):
            return f'Reaction removed: {emoji or "(cleared)"} on msg {target}'
        return f'Reaction added: {emoji or "(empty)"} on msg {target}'

    if content_type == 'system':
        event = str(content.get('event') or 'unknown')
        return f'[system:{event}]'

    if content_type == 'approval_request':
        slug = str(content.get('approval_id') or 'unknown')
        decisions = content.get('allowed_decisions') or []
        return f'[approval_request:{slug}] options: {", ".join(str(d) for d in decisions)}'

    if content_type == 'approval_response':
        approval_id = str(content.get('approval_id') or '').strip()
        decision = str(content.get('decision') or '').strip()
        return f'/approve {approval_id} {decision}' if approval_id and decision else ''

    # Default: text
    delivery = msg.get('delivery') or {}
    stream = delivery.get('stream')
    if stream:
        stream_id = str(stream.get('stream_id') or 'unknown')
        state = str(stream.get('state') or 'partial')
        seq = stream.get('seq')
        text = str(content.get('text') or '')
        seq_suffix = f' #{seq}' if seq is not None else ''
        return f'[stream {stream_id} {state}{seq_suffix}] {text}'.strip()

    return str(content.get('text') or '')


def infer_message_type(attachments: list[dict[str, Any]]) -> MessageType:
    if not attachments:
        return MessageType.TEXT
    first = attachments[0] or {}
    content_type = str(first.get('content_type') or '')
    if content_type.startswith('image/'):
        return MessageType.PHOTO
    if content_type.startswith('video/'):
        return MessageType.VIDEO
    if content_type.startswith('audio/'):
        return MessageType.AUDIO
    return MessageType.DOCUMENT
