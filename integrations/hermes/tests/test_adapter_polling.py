from __future__ import annotations

import asyncio

import pytest

from gateway.config import PlatformConfig
from gateway.platforms.base import MessageType

from r2_relay_adapter.adapter import R2RelayAdapter


@pytest.fixture
def relay_env(monkeypatch):
    monkeypatch.setenv("R2_RELAY_ENDPOINT", "https://example.r2.cloudflarestorage.com")
    monkeypatch.setenv("R2_RELAY_BUCKET", "relay-bucket")
    monkeypatch.setenv("R2_RELAY_ACCESS_KEY_ID", "abc")
    monkeypatch.setenv("R2_RELAY_SECRET_ACCESS_KEY", "secret")
    monkeypatch.setenv("R2_RELAY_SERVER_ID", "server-one")


class PollingServiceStub:
    def __init__(self, message):
        self.message = message
        self.fetched = {}
        self.sent = []

    async def publish_identity(self, payload=None):
        return payload

    async def poll_inbox(self, self_id, handler, **kwargs):
        del self_id, kwargs
        await handler(self.message, "msg/server-one/incoming.json")

    async def fetch_attachment(self, key, **kwargs):
        del kwargs
        return self.fetched.get(key)

    async def send_message(self, recipient, options):
        self.sent.append((recipient, options))
        return {"message_id": "ack-1", "key": "msg/phone-1/ack.json"}


async def collect_event(message, configure=None):
    service = PollingServiceStub(message)
    if configure:
        configure(service)
    adapter = R2RelayAdapter(PlatformConfig(enabled=True), service=service)
    events = []

    async def handler(event):
        events.append(event)

    adapter.set_message_handler(handler)
    await adapter.connect()
    await asyncio.sleep(0.01)
    await adapter.disconnect()
    return events[0]


@pytest.mark.asyncio
async def test_polling_converts_v3_text_message(relay_env):
    services = []
    event = await collect_event(
        {
            "msg_id": "incoming-1",
            "from": "phone-1",
            "to": "server-one",
            "ts_sent": 123,
            "prev_key": None,
            "route": {"agent_id": "main", "conversation_id": "conversation-1"},
            "content": {"type": "text", "text": "hello"},
        },
        services.append,
    )
    assert event.text == "hello"
    assert event.source.chat_id == "peer=phone-1,conversation=conversation-1"
    recipient, acknowledgement = services[0].sent[0]
    assert recipient == "phone-1"
    assert acknowledgement["content"] == {
        "type": "reaction",
        "target_msg_id": "incoming-1",
        "emoji": "✅",
        "remove": False,
    }


@pytest.mark.asyncio
async def test_polling_converts_v3_stream(relay_env):
    event = await collect_event(
        {
            "msg_id": "incoming-2",
            "from": "phone-1",
            "to": "server-one",
            "ts_sent": 123,
            "prev_key": None,
            "route": {"agent_id": "main", "conversation_id": "conversation-1"},
            "content": {"type": "text", "text": "partial answer"},
            "delivery": {"stream": {"stream_id": "stream-1", "seq": 2, "state": "partial"}},
        }
    )
    assert event.text == "[stream stream-1 partial #2] partial answer"


@pytest.mark.asyncio
async def test_polling_converts_v3_reaction(relay_env):
    event = await collect_event(
        {
            "msg_id": "incoming-3",
            "from": "phone-1",
            "to": "server-one",
            "ts_sent": 123,
            "prev_key": None,
            "route": {"agent_id": "main", "conversation_id": "conversation-1"},
            "content": {"type": "reaction", "target_msg_id": "target-1", "emoji": "✅"},
        }
    )
    assert event.text == "Reaction added: ✅ on msg target-1"
    assert event.reply_to_message_id == "target-1"


@pytest.mark.asyncio
async def test_polling_downloads_v3_text_attachment(relay_env):
    key = "att/server-one/file.txt"

    def configure(service):
        service.fetched[key] = {"file_path": "/tmp/file.txt", "content_type": "text/plain"}

    event = await collect_event(
        {
            "msg_id": "incoming-4",
            "from": "phone-1",
            "to": "server-one",
            "ts_sent": 123,
            "prev_key": None,
            "route": {"agent_id": "main", "conversation_id": "conversation-1"},
            "content": {
                "type": "text",
                "text": "file",
                "attachments": [{"id": "att-1", "key": key, "kind": "file", "content_type": "text/plain"}],
            },
        },
        configure,
    )
    assert event.message_type == MessageType.DOCUMENT
    assert event.media_urls == ["/tmp/file.txt"]
