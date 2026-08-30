from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path('/home/ww/.hermes/hermes-agent')
sys.path.insert(0, str(ROOT))

from gateway.platforms.base import MessageType

from r2_relay_adapter.checkpoint_store import FileCheckpointStore
from r2_relay_adapter.outbound_mapping import build_send_options
from r2_relay_adapter.address_mapping import build_source_chat_id, parse_relay_target
from r2_relay_adapter.inbound_mapping import format_inbound_text, infer_message_type
from r2_relay_adapter.service_factory import build_relay_service


class _ClientStub:
    async def put_object(self, *args, **kwargs):
        return {"ETag": '"etag-1"'}

    async def get_object(self, key):
        return None

    async def get_json_with_etag(self, key):
        return None

    async def delete_object(self, key):
        return {"deleted": key}

    async def delete_objects(self, keys):
        return {"deleted": keys}

    async def list_prefix_page(self, prefix, continuation_token=None, max_keys=1000):
        return {"contents": [], "next_continuation_token": None, "is_truncated": False}


class _RelayConfig:
    bucket = 'relay-bucket'
    server_id = 'server-one'


def test_parse_relay_target_extracts_peer_and_conversation_id():
    peer, conversation_id = parse_relay_target('peer=peer-1,conversation=conversation-1')

    assert peer == 'peer-1'
    assert conversation_id == 'conversation-1'


def test_build_source_chat_id_returns_peer_identifier():
    assert build_source_chat_id('peer-1', 'conversation-1') == 'peer=peer-1,conversation=conversation-1'


def test_build_send_options_prefers_explicit_session_fields_and_stream_metadata():
    options = build_send_options(
        'conversation-1',
        'partial answer',
        None,
        {
            'agent_id': 'coding',
            'instance_id': 'instance-1',
            'stream_id': 'stream-1',
            'stream_seq': 2,
            'stream_state': 'partial',
        },
    )

    assert options == {
        'route': {'agent_id': 'coding', 'conversation_id': 'conversation-1', 'instance_id': 'instance-1'},
        'content': {'type': 'text', 'text': 'partial answer'},
        'delivery': {'stream': {'stream_id': 'stream-1', 'seq': 2, 'state': 'partial'}},
    }


def test_format_inbound_text_formats_stream_snapshot():
    text = format_inbound_text(
        {
            'content': {'type': 'text', 'text': 'partial answer'},
            'delivery': {'stream': {'stream_id': 'stream-1', 'seq': 2, 'state': 'partial'}},
        }
    )

    assert text == '[stream stream-1 partial #2] partial answer'


def test_infer_message_type_uses_first_attachment_content_type():
    message_type = infer_message_type([
        {
            'content_type': 'image/png',
        }
    ])

    assert message_type == MessageType.PHOTO


def test_service_factory_builds_hermes_service_on_shared_core(tmp_path):
    service = build_relay_service(
        config=_RelayConfig(),
        client=_ClientStub(),
        checkpoint_store=FileCheckpointStore(tmp_path / 'checkpoint.json'),
    )

    assert service.peer_id == 'server-one'
    assert service.relay.make_head_key('peer-1') == 'head/peer-1.json'
    assert service.checkpoint_store.path == tmp_path / 'checkpoint.json'
