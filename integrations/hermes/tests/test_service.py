from __future__ import annotations

import asyncio
import logging
import time

import pytest

from r2_relay_adapter.protocol import R2RelayProtocol
from r2_relay_adapter.service import R2RelayService


class _ClientStub:
    def __init__(self):
        self.put_calls = []
        self.delete_calls = []
        self.messages = {}
        self.head_state = None
        self.deleted_keys = []
        self.list_pages = []

    async def put_object(self, key, body, content_type=None, tagging=None, if_match=None, if_none_match=None):
        self.put_calls.append(
            {
                'key': key,
                'body': body,
                'content_type': content_type,
                'tagging': tagging,
                'if_match': if_match,
                'if_none_match': if_none_match,
            }
        )
        return {'ETag': '"etag-1"'}

    async def get_json_with_etag(self, key):
        return self.head_state

    async def get_object(self, key):
        payload = self.messages.get(key)
        if payload is None:
            return None
        return {'payload': payload}

    async def delete_object(self, key):
        self.delete_calls.append(key)
        self.deleted_keys.append(key)
        return {'deleted': key}

    async def list_prefix_page(self, prefix, continuation_token=None, max_keys=1000):
        if self.list_pages:
            return self.list_pages.pop(0)
        return {'contents': [], 'next_continuation_token': None, 'is_truncated': False}

    async def delete_objects(self, keys):
        self.deleted_keys.extend(keys)
        return {'deleted': keys, 'errors': []}


class _CheckpointStore:
    def __init__(self, state=None):
        self.state = state or {
            'last_head_key': None,
            'seen': [],
        }
        self.saved = []

    def load(self):
        return {
            'last_head_key': self.state['last_head_key'],
            'seen': list(self.state['seen']),
        }

    def save(self, state):
        snapshot = {
            'last_head_key': state['last_head_key'],
            'seen': list(state['seen']),
        }
        self.saved.append(snapshot)
        self.state = snapshot


class _ClientError(Exception):
    pass


@pytest.mark.asyncio
async def test_collect_inbox_messages_returns_chain_in_oldest_first_order():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')

    older_key = relay.make_msg_key('server-one', now_ms=100, suffix='old')
    newer_key = relay.make_msg_key('server-one', now_ms=200, suffix='new')
    client.head_state = {'body': {'head_key': newer_key, 'head_msg_id': 'msg-new', 'head_ts': 200}, 'etag': 'etag-1'}
    client.messages[older_key] = {
        'msg_id': 'msg-old',
        'from': 'phone-1',
        'to': 'server-one',
        'ts_sent': 100,
        'prev_key': None,
        'body': 'older',
    }
    client.messages[newer_key] = {
        'msg_id': 'msg-new',
        'from': 'phone-1',
        'to': 'server-one',
        'ts_sent': 200,
        'prev_key': older_key,
        'body': 'newer',
    }

    batch = await service.collect_inbox_messages('server-one', last_seen_key=None)

    assert [item['key'] for item in batch['messages']] == [older_key, newer_key]
    assert [item['message']['body'] for item in batch['messages']] == ['older', 'newer']


@pytest.mark.asyncio
async def test_collect_inbox_messages_returns_empty_batch_when_head_target_missing():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')

    missing_key = relay.make_msg_key('server-one', now_ms=100, suffix='missing')
    client.head_state = {'body': {'head_key': missing_key, 'head_msg_id': 'msg-missing', 'head_ts': 100}, 'etag': 'etag-1'}

    batch = await service.collect_inbox_messages('server-one', last_seen_key=None)

    assert batch == {
        'head': {'head_key': missing_key, 'head_msg_id': 'msg-missing', 'head_ts': 100},
        'messages': [],
    }


@pytest.mark.asyncio
async def test_collect_inbox_messages_recovers_when_head_points_to_missing_latest_object():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')

    older_key = relay.make_msg_key('server-one', now_ms=100, suffix='old')
    missing_latest_key = relay.make_msg_key('server-one', now_ms=200, suffix='missing')
    client.head_state = {'body': {'head_key': missing_latest_key, 'head_msg_id': 'msg-missing', 'head_ts': 200}, 'etag': 'etag-1'}
    client.messages[older_key] = {
        'msg_id': 'msg-old',
        'from': 'phone-1',
        'to': 'server-one',
        'ts_sent': 100,
        'prev_key': None,
        'body': 'older',
    }

    async def read_message_with_fallback(key):
        if key == missing_latest_key:
            return {
                'msg_id': 'msg-missing',
                'from': 'phone-1',
                'to': 'server-one',
                'ts_sent': 200,
                'prev_key': older_key,
                'body': 'missing latest reconstructed',
            }
        return client.messages.get(key)

    service.read_message = read_message_with_fallback

    batch = await service.collect_inbox_messages('server-one', last_seen_key=None)

    assert [item['key'] for item in batch['messages']] == [older_key, missing_latest_key]
    assert [item['message']['body'] for item in batch['messages']] == ['older', 'missing latest reconstructed']


@pytest.mark.asyncio
async def test_send_message_writes_message_then_head_update():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')

    result = await service.send_message(
        'phone-1',
        {
            'route': {'agent_id': 'main', 'conversation_id': 'conversation-1'},
            'content': {'type': 'text', 'text': 'hello there'},
        },
    )

    assert result['message_id']
    assert len(client.put_calls) == 2
    message_write = client.put_calls[0]
    head_write = client.put_calls[1]
    assert message_write['key'].startswith('msg/phone-1/')
    assert head_write['key'] == 'head/phone-1.json'
    assert 'hello there' in message_write['body']
    assert 'conversation-1' in message_write['body']


@pytest.mark.asyncio
async def test_publish_identity_preserves_discovery_payload_shape():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')

    identity = await service.publish_identity(
        {
            'display_name': 'Demo Gateway',
            'protocol': {'name': 'r2-relay', 'version': 3},
            'software': {'id': 'hermes', 'version': '0.1.0'},
            'capabilities': {
                'messaging': {'text': True, 'streaming': True, 'reactions': False, 'system_events': False},
                'conversations': {'list': True, 'create': False, 'reset': False, 'archive': False, 'threading': True},
                'agents': {'list': True, 'multiple': False, 'switch': False, 'per_agent_models': False},
            },
            'agents': [{'id': 'main', 'is_default': True, 'default_route': {'agent_id': 'main'}}],
            'conversations': [],
            'limits': {
                'inbound_attachment_max_bytes': {
                    'image': 100,
                    'video': 200,
                    'audio': 300,
                    'file': 400,
                },
                'oversize_attachment_behavior': 'reject',
            },
        }
    )

    assert identity['display_name'] == 'Demo Gateway'
    assert identity['protocol'] == {'name': 'r2-relay', 'version': 3}
    assert identity['agents'][0]['default_route'] == {'agent_id': 'main'}
    assert identity['limits']['inbound_attachment_max_bytes']['file'] == 400
    assert client.put_calls[0]['key'] == 'identity/server-one.json'
    assert '"display_name": "Demo Gateway"' in client.put_calls[0]['body']
    assert '"protocol": {"name": "r2-relay", "version": 3}' in client.put_calls[0]['body']


@pytest.mark.asyncio
async def test_publish_identity_skips_redundant_writes_for_unchanged_payload():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')
    payload = {
        'display_name': 'Demo Gateway',
        'role': 'server',
        'conversations': [
            {
                'id': 'main',
                'display_title': 'Main',
                'route': {
                    'agent_id': 'main',
                    'conversation_id': 'main',
                },
                'source': {'channel': 'hermes', 'chat_kind': 'dm'},
                'updated_at': None,
            }
        ],
    }

    first = await service.publish_identity(payload)
    second = await service.publish_identity(dict(payload))

    assert first == second
    assert len(client.put_calls) == 1


@pytest.mark.asyncio
async def test_publish_identity_allows_heartbeat_write_after_refresh_interval(monkeypatch):
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')
    payload = {
        'display_name': 'Demo Gateway',
        'role': 'server',
        'conversations': [],
    }
    base_time = 1_700_000_000.0
    monkeypatch.setattr(time, 'time', lambda: base_time)
    await service.publish_identity(payload)
    monkeypatch.setattr(time, 'time', lambda: base_time + (12 * 60 * 60) + 1)

    await service.publish_identity(dict(payload))

    assert len(client.put_calls) == 2


@pytest.mark.asyncio
async def test_send_message_includes_attachment_payloads():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')
    attachments = [
        {
            'id': 'att-1',
            'key': 'att/phone-1/9999999999876-msg-01-photo.png',
            'file_name': 'photo.png',
            'content_type': 'image/png',
            'size': 123,
            'sha256': None,
            'kind': 'image',
            'width': 10,
            'height': 20,
            'duration_ms': None,
            'preview_image_key': None,
            'preview_image_type': None,
            'preview_size': None,
        }
    ]

    await service.send_message(
        'phone-1',
        {
            'route': {'agent_id': 'main', 'conversation_id': 'conversation-1'},
            'content': {'type': 'text', 'text': 'hello with image', 'attachments': attachments},
        },
    )

    message_write = client.put_calls[0]
    assert 'photo.png' in message_write['body']
    assert 'att/phone-1/9999999999876-msg-01-photo.png' in message_write['body']


@pytest.mark.asyncio
async def test_send_streaming_snapshots_reuses_stream_id_and_marks_partial_then_final():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')

    result = await service.send_streaming_snapshots(
        'phone-1',
        ['first snapshot', 'second snapshot'],
        options={'route': {'agent_id': 'main', 'conversation_id': 'conversation-1'}},
    )

    assert result['stream_id']
    assert len(result['results']) == 2
    assert len(client.put_calls) == 4

    first_message = client.put_calls[0]
    second_message = client.put_calls[2]
    assert '"type": "text"' in first_message['body']
    assert '"seq": 1' in first_message['body']
    assert '"state": "partial"' in first_message['body']
    assert '"conversation_id": "conversation-1"' in first_message['body']
    assert '"seq": 2' in second_message['body']
    assert '"state": "final"' in second_message['body']

    expected_stream_fragment = f'"stream_id": "{result["stream_id"]}"'
    assert expected_stream_fragment in first_message['body']
    assert expected_stream_fragment in second_message['body']


@pytest.mark.asyncio
async def test_store_attachment_builds_attachment_ref_and_uploads_bytes():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')

    attachment = await service.store_attachment(
        recipient='phone-1',
        message_id='msg-1',
        index=1,
        data=b'\x89PNG\r\n\x1a\nrest',
        file_name='photo.png',
        content_type='image/png',
        now_ms=123,
    )

    assert attachment == {
        'id': 'att-msg-1-1',
        'key': 'att/phone-1/9999999999876-msg-1-01-photo.png',
        'file_name': 'photo.png',
        'content_type': 'image/png',
        'size': 12,
        'sha256': None,
        'kind': 'image',
        'width': None,
        'height': None,
        'duration_ms': None,
        'preview_image_key': None,
        'preview_image_type': None,
        'preview_size': None,
    }
    upload = client.put_calls[0]
    assert upload['key'] == 'att/phone-1/9999999999876-msg-1-01-photo.png'
    assert upload['body'] == b'\x89PNG\r\n\x1a\nrest'
    assert upload['content_type'] == 'image/png'
    assert upload['if_none_match'] == '*'


@pytest.mark.asyncio
async def test_fetch_attachment_returns_local_media_record():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')
    client.messages['att/key'] = {'ignored': True}

    class _Body:
        def __aiter__(self):
            async def _iterate():
                yield b'hello world'
            return _iterate()

    async def get_object(key):
        assert key == 'att/key'
        return {'Body': _Body(), 'ContentType': 'text/plain'}

    client.get_object = get_object

    media = await service.fetch_attachment('att/key', file_name='note.txt', content_type='text/plain')

    assert media['content_type'] == 'text/plain'
    assert media['file_path'].endswith('note.txt')
    assert media['file_path']
    assert media['message_type'] == 'document'


@pytest.mark.asyncio
async def test_fetch_attachment_supports_sync_streaming_body():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')

    class _SyncBody:
        def iter_chunks(self, chunk_size=1024):
            del chunk_size
            yield b'hello world'

    async def get_object(key):
        assert key == 'att/key'
        return {'Body': _SyncBody(), 'ContentType': 'text/plain'}

    client.get_object = get_object

    media = await service.fetch_attachment('att/key', file_name='note.txt', content_type='text/plain')

    assert media['content_type'] == 'text/plain'
    assert media['file_path'].endswith('note.txt')
    assert media['file_path']
    assert media['message_type'] == 'document'


@pytest.mark.asyncio
async def test_poll_inbox_dispatches_messages_and_persists_checkpoint_state():
    client = _ClientStub()
    checkpoint = _CheckpointStore()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one', checkpoint_store=checkpoint)

    key = relay.make_msg_key('server-one', now_ms=100, suffix='one')
    client.head_state = {'body': {'head_key': key, 'head_msg_id': 'msg-one', 'head_ts': 100}, 'etag': 'etag'}
    client.messages[key] = {
        'msg_id': 'msg-one',
        'from': 'phone-1',
        'to': 'server-one',
        'ts_sent': 100,
        'prev_key': None,
        'route': {'agent_id': 'main'},
        'content': {'type': 'text', 'text': 'hi from phone'},
    }

    seen = []

    async def handler(msg, msg_key):
        seen.append((msg['content']['text'], msg_key))
        raise _ClientError('stop after first message')

    with pytest.raises(_ClientError):
        await service.poll_inbox('server-one', handler, poll_interval_ms=1, backoff_max_ms=2)

    assert seen == [('hi from phone', key)]
    assert checkpoint.saved[-1]['last_head_key'] is None
    assert checkpoint.saved[-1]['seen'] == []
    assert checkpoint.saved[-1].get('seen_msg_ids', []) == []


@pytest.mark.asyncio
async def test_poll_inbox_skips_already_seen_messages_from_checkpoint():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    key = relay.make_msg_key('server-one', now_ms=100, suffix='one')
    checkpoint = _CheckpointStore({'last_head_key': key, 'seen': [key]})
    service = R2RelayService(client=client, relay=relay, peer_id='server-one', checkpoint_store=checkpoint)

    client.head_state = {'body': {'head_key': key, 'head_msg_id': 'msg-one', 'head_ts': 100}, 'etag': 'etag'}
    client.messages[key] = {
        'msg_id': 'msg-one',
        'from': 'phone-1',
        'to': 'server-one',
        'ts_sent': 100,
        'prev_key': None,
        'body': 'hi from phone',
    }

    seen = []
    abort = asyncio.Event()
    abort.set()

    async def handler(msg, msg_key):
        seen.append((msg['body'], msg_key))

    await service.poll_inbox('server-one', handler, poll_interval_ms=1, backoff_max_ms=2, abort_event=abort)

    assert seen == []


@pytest.mark.asyncio
async def test_mark_message_processed_updates_stored_message():
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')
    key = relay.make_msg_key('server-one', now_ms=100, suffix='one')
    client.messages[key] = {
        'msg_id': 'msg-one',
        'from': 'phone-1',
        'to': 'server-one',
        'ts_sent': 100,
        'prev_key': None,
        'body': 'hi from phone',
    }

    updated = await service.mark_message_processed(key, {'processedBy': 'server-one'})

    assert updated['status']['processed_by'] == 'server-one'
    assert updated['status']['state'] == 'done'
    assert any(call['key'] == key for call in client.put_calls)


@pytest.mark.asyncio
async def test_sweep_by_key_timestamp_deletes_expired_keys(monkeypatch):
    client = _ClientStub()
    relay = R2RelayProtocol(bucket='demo')
    service = R2RelayService(client=client, relay=relay, peer_id='server-one')

    now_ms = 10 * 24 * 60 * 60 * 1000
    service._now_ms = lambda: now_ms
    old_key = relay.make_msg_key('phone-1', now_ms=0, suffix='old')
    new_key = relay.make_msg_key('phone-1', now_ms=now_ms, suffix='new')
    client.list_pages = [
        {
            'contents': [{'Key': old_key}, {'Key': new_key}],
            'next_continuation_token': None,
            'is_truncated': False,
        }
    ]

    summary = await service.sweep_by_key_timestamp('msg/', ttl_days=7)

    assert summary['deleted'] == 1
    assert old_key in client.deleted_keys
    assert new_key not in client.deleted_keys
