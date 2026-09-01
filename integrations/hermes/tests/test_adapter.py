from __future__ import annotations

from pathlib import Path

import pytest

from gateway.config import PlatformConfig
from gateway.platforms.base import SendResult

from r2_relay_adapter.adapter import R2RelayAdapter, check_r2_relay_requirements


@pytest.fixture
def relay_env(monkeypatch):
    monkeypatch.setenv("R2_RELAY_ENDPOINT", "https://example.r2.cloudflarestorage.com")
    monkeypatch.setenv("R2_RELAY_BUCKET", "relay-bucket")
    monkeypatch.setenv("R2_RELAY_ACCESS_KEY_ID", "abc")
    monkeypatch.setenv("R2_RELAY_SECRET_ACCESS_KEY", "secret")
    monkeypatch.setenv("R2_RELAY_SERVER_ID", "server one")
    monkeypatch.setenv("R2_RELAY_DISCOVERY_CONVERSATION_ID", "main")


class ServiceStub:
    def __init__(self):
        self.identities = []
        self.sent = []
        self.stored_attachments = []

    async def publish_identity(self, payload=None):
        self.identities.append(payload)
        return payload

    async def send_message(self, recipient, options):
        self.sent.append((recipient, options))
        return {"message_id": "msg-1", "key": "msg/peer-1/key.json"}

    async def store_attachment(self, recipient, message_id, index, data, file_name=None, content_type=None, now_ms=None):
        del now_ms
        record = {
            "id": f"att-{message_id}-{index}",
            "key": f"att/{recipient}/{message_id}-{index:02d}-{file_name}",
            "file_name": file_name,
            "content_type": content_type,
            "size": len(data),
            "sha256": None,
            "kind": "image" if (content_type or "").startswith("image/") else "file",
            "width": None,
            "height": None,
            "duration_ms": None,
            "preview_image_key": None,
            "preview_image_type": None,
            "preview_size": None,
        }
        self.stored_attachments.append(record)
        return record

    async def poll_inbox(self, *args, **kwargs):
        return None


def make_adapter(service: ServiceStub) -> R2RelayAdapter:
    return R2RelayAdapter(PlatformConfig(enabled=True), service=service)


def test_requirements_probe_boto3_instead_of_credentials(monkeypatch):
    assert check_r2_relay_requirements() is True
    monkeypatch.setattr("r2_relay_adapter.adapter.importlib.util.find_spec", lambda name: None)
    assert check_r2_relay_requirements() is False


@pytest.mark.asyncio
async def test_connect_publishes_strict_v3_identity(relay_env):
    service = ServiceStub()
    adapter = make_adapter(service)

    assert await adapter.connect(is_reconnect=False) is True
    identity = service.identities[0]
    assert identity["protocol"] == {"name": "r2-relay", "version": 3}
    assert identity["software"]["id"] == "hermes"
    assert identity["agents"][0]["is_default"] is True
    assert identity["agents"][0]["default_route"] == {"agent_id": "main"}
    assert identity["conversations"][0]["source"]["chat_kind"] == "dm"
    assert identity["capabilities"]["messaging"]["reactions"] is False
    assert identity["capabilities"]["attachments"]["supported"] is True
    assert identity["capabilities"]["approvals"] is None
    await adapter.disconnect()


@pytest.mark.asyncio
async def test_send_emits_v3_text_envelope(relay_env):
    service = ServiceStub()
    adapter = make_adapter(service)

    result = await adapter.send("peer=phone-1,conversation=conversation-1", "hello relay")

    assert isinstance(result, SendResult)
    assert result.success is True
    recipient, options = service.sent[0]
    assert recipient == "phone-1"
    assert options == {
        "route": {"agent_id": "main", "conversation_id": "conversation-1", "instance_id": None},
        "content": {"type": "text", "text": "hello relay"},
    }


@pytest.mark.asyncio
async def test_send_emits_v3_stream_delivery(relay_env):
    service = ServiceStub()
    adapter = make_adapter(service)

    result = await adapter.send(
        "phone-1",
        "partial answer",
        metadata={"stream_id": "stream-1", "stream_seq": 2, "stream_state": "partial"},
    )

    assert result.success is True
    assert service.sent[0][1]["delivery"] == {
        "stream": {"stream_id": "stream-1", "seq": 2, "state": "partial"}
    }


@pytest.mark.asyncio
async def test_send_emits_v3_reaction(relay_env):
    service = ServiceStub()
    adapter = make_adapter(service)

    result = await adapter.send(
        "phone-1",
        "",
        metadata={
            "content_type": "reaction",
            "reaction_target_message_id": "msg-target-1",
            "reaction_emoji": "👍",
            "reaction_remove": False,
        },
    )

    assert result.success is True
    assert service.sent[0][1]["content"] == {
        "type": "reaction",
        "target_msg_id": "msg-target-1",
        "emoji": "👍",
        "remove": False,
    }


@pytest.mark.asyncio
async def test_send_document_places_attachment_inside_text_content(relay_env, tmp_path: Path):
    service = ServiceStub()
    adapter = make_adapter(service)
    note = tmp_path / "note.txt"
    note.write_text("hello attachment", encoding="utf-8")

    result = await adapter.send_document("phone-1", str(note), caption="see note")

    assert result.success is True
    content = service.sent[0][1]["content"]
    assert content["text"] == "see note"
    assert content["attachments"][0]["file_name"] == "note.txt"


@pytest.mark.asyncio
async def test_edit_message_reuses_stream_id_and_finishes(relay_env):
    service = ServiceStub()
    adapter = make_adapter(service)

    first = await adapter.send("phone-1", "partial ▉")
    second = await adapter.edit_message("phone-1", first.message_id, "complete ▉", finalize=True)

    assert first.success and second.success
    first_stream = service.sent[0][1]["delivery"]["stream"]
    second_stream = service.sent[1][1]["delivery"]["stream"]
    assert second_stream["stream_id"] == first_stream["stream_id"]
    assert second_stream["seq"] == 2
    assert second_stream["state"] == "final"
