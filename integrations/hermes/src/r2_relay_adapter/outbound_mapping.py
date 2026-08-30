from __future__ import annotations

from typing import Any


def build_send_options(
    target_conversation_id: str | None,
    text: str,
    attachments: list[dict[str, Any]] | None = None,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    metadata = dict(metadata or {})

    agent_id = str(metadata.get('agent_id') or 'main')
    conversation_id = (
        metadata.get('conversation_id')
        or target_conversation_id
        or 'main'
    )

    options: dict[str, Any] = {
        'route': {
            'agent_id': agent_id,
            'conversation_id': str(conversation_id),
            'instance_id': metadata.get('instance_id'),
        },
    }

    # Build typed content
    content_type = metadata.get('content_type') or 'text'
    if content_type == 'reaction':
        options['content'] = {
            'type': 'reaction',
            'target_msg_id': str(metadata.get('reaction_target_message_id') or ''),
            'emoji': metadata.get('reaction_emoji'),
            'remove': metadata.get('reaction_remove', False),
        }
    elif content_type == 'system':
        options['content'] = {
            'type': 'system',
            'event': str(metadata.get('system_event') or 'unknown'),
            'data': metadata.get('system_data'),
        }
    else:
        options['content'] = {
            'type': 'text',
            'text': text,
        }
        if attachments:
            options['content']['attachments'] = attachments

    # Streaming delivery
    if metadata.get('stream_id'):
        stream_state = str(metadata.get('stream_state') or 'partial')
        stream_seq = metadata.get('stream_seq')
        options['delivery'] = {
            'stream': {
                'stream_id': str(metadata['stream_id']),
                'seq': int(stream_seq) if stream_seq is not None else 0,
                'state': stream_state,
            }
        }

    return options
