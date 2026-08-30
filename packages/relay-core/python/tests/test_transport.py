from __future__ import annotations

import asyncio
import json
from pathlib import Path

import pytest

from r2_relay_core.checkpoint import InMemoryCheckpointStore, default_checkpoint_state, has_seen_message, remember_message
from r2_relay_core.errors import PreconditionFailedError
from r2_relay_core.keyspace import RelayKeyspace
from r2_relay_core.transport import R2RelayTransport


FIXTURES_DIR = Path(__file__).resolve().parents[2] / "spec" / "fixtures"


class SequentialIds:
    def __init__(self, values: list[str]):
        self._values = iter(values)

    def __call__(self) -> str:
        return next(self._values)


class SequentialTimes:
    def __init__(self, values: list[int]):
        self._values = iter(values)

    def __call__(self) -> int:
        return next(self._values)


class ObjectStoreStub:
    def __init__(self) -> None:
        self.put_calls: list[dict[str, object]] = []
        self.objects: dict[str, dict[str, object]] = {}
        self.head_reads: list[dict[str, object] | None] = []
        self.list_pages: list[dict[str, object]] = []
        self.fail_next_head_writes = 0
        self.deleted_objects: list[str] = []

    async def put_object(
        self,
        key: str,
        body: bytes | str,
        content_type: str | None = None,
        tagging: str | None = None,
        if_match: str | None = None,
        if_none_match: str | None = None,
    ) -> dict[str, str]:
        self.put_calls.append(
            {
                "key": key,
                "body": body,
                "content_type": content_type,
                "tagging": tagging,
                "if_match": if_match,
                "if_none_match": if_none_match,
            }
        )
        if key.startswith("head/") and self.fail_next_head_writes:
            self.fail_next_head_writes -= 1
            raise PreconditionFailedError("PreconditionFailed")

        payload: object = body
        if isinstance(body, str) and content_type == "application/json":
            payload = json.loads(body)
        self.objects[key] = {
            "payload": payload,
            "etag": f"etag-{len(self.put_calls)}",
            "content_type": content_type,
        }
        return {"ETag": self.objects[key]["etag"]}  # type: ignore[index]

    async def get_json_with_etag(self, key: str) -> dict[str, object] | None:
        if self.head_reads:
            return self.head_reads.pop(0)
        record = self.objects.get(key)
        if record is None:
            return None
        return {"body": record["payload"], "etag": record["etag"]}

    async def get_object(self, key: str) -> dict[str, object] | None:
        record = self.objects.get(key)
        if record is None:
            return None
        return {"payload": record["payload"]}

    async def list_prefix_page(
        self,
        prefix: str,
        continuation_token: str | None = None,
        max_keys: int = 1000,
    ) -> dict[str, object]:
        del prefix, continuation_token, max_keys
        if self.list_pages:
            return self.list_pages.pop(0)
        return {"contents": [], "next_continuation_token": None, "is_truncated": False}

    async def delete_object(self, key: str) -> dict[str, str]:
        self.deleted_objects.append(key)
        self.objects.pop(key, None)
        return {"deleted": key}

    async def delete_objects(self, keys: list[str]) -> dict[str, object]:
        self.deleted_objects.extend(keys)
        for key in keys:
            self.objects.pop(key, None)
        return {"deleted": keys, "errors": []}


async def no_sleep(_seconds: float) -> None:
    return None


class PollAbortAfterFirstSleep:
    def __init__(self, event):
        self.event = event

    async def __call__(self, _seconds: float) -> None:
        self.event.set()
        return None


def load_fixture(name: str) -> dict[str, object]:
    return json.loads((FIXTURES_DIR / name).read_text(encoding="utf-8"))


OPENCLAW_ROUTE = {
    "agent_id": "main",
    "conversation_id": "agent:main:main",
}


@pytest.mark.asyncio
async def test_publish_identity_includes_canonical_optional_fields() -> None:
    store = ObjectStoreStub()
    transport = R2RelayTransport(
        store=store,
        keyspace=RelayKeyspace(now_ms_factory=lambda: 1764028800000),
        peer_id="relay.hermes.local",
    )

    published = await transport.publish_identity({"display_name": "Hermes Relay Adapter"})

    assert published == {
        "peer": "relay.hermes.local",
        "display_name": "Hermes Relay Adapter",
        "role": "server",
        "last_seen": 1764028800000,
        "protocol": {"name": "r2-relay", "version": 3},
        "software": {"id": "unknown"},
        "capabilities": {
            "messaging": {"text": True, "streaming": False, "reactions": False, "system_events": False},
            "conversations": {"list": False, "create": False, "reset": False, "archive": False, "threading": False},
            "agents": {"list": False, "multiple": False, "switch": False, "per_agent_models": False},
        },
        "limits": None,
        "agents": [],
        "conversations": [],
    }
    assert store.objects["identity/relay.hermes.local.json"]["payload"] == published


@pytest.mark.asyncio
async def test_send_message_retries_after_head_cas_failure() -> None:
    store = ObjectStoreStub()
    store.fail_next_head_writes = 1
    concurrent_head = {
        "head_key": "msg/phone-1/9999999999800-existing.json",
        "head_msg_id": "existing-msg",
        "head_ts": 199,
    }
    store.head_reads = [None, {"body": concurrent_head, "etag": "etag-concurrent"}]
    keyspace = RelayKeyspace(
        id_factory=SequentialIds(["first-key", "first-msg", "second-key", "second-msg"]),
        now_ms_factory=lambda: 123,
    )
    transport = R2RelayTransport(store=store, keyspace=keyspace, peer_id="server-one", sleep=no_sleep)

    result = await transport.send_message("phone-1", {
        "route": OPENCLAW_ROUTE,
        "content": {"type": "text", "text": "hello there"},
    })

    assert result == {
        "key": "msg/phone-1/9999999999876-second-key.json",
        "message_id": "second-msg",
    }
    assert [call["key"] for call in store.put_calls] == [
        "msg/phone-1/9999999999876-first-key.json",
        "head/phone-1.json",
        "msg/phone-1/9999999999876-second-key.json",
        "head/phone-1.json",
    ]
    first_head_write = store.put_calls[1]
    second_head_write = store.put_calls[3]
    assert first_head_write["if_none_match"] == "*"
    assert first_head_write["if_match"] is None
    assert second_head_write["if_match"] == "etag-concurrent"

    second_message = json.loads(store.put_calls[2]["body"])
    assert second_message["prev_key"] == concurrent_head["head_key"]
    assert second_message["route"] == OPENCLAW_ROUTE


@pytest.mark.asyncio
async def test_collect_inbox_messages_returns_oldest_first_order_from_fixture_chain() -> None:
    fixture = load_fixture("inbox-chain.json")
    store = ObjectStoreStub()
    store.head_reads = [{"body": fixture["head"], "etag": "etag-1"}]
    for item in fixture["messages"]:
        store.objects[item["key"]] = {"payload": item["message"], "etag": "etag-msg"}

    transport = R2RelayTransport(store=store, keyspace=RelayKeyspace(), peer_id="relay.hermes.local")

    batch = await transport.collect_inbox_messages("clawchat-ios-alice", last_seen_key=None)

    assert batch["head"] == fixture["head"]
    assert [item["key"] for item in batch["messages"]] == [item["key"] for item in fixture["messages"]]
    assert [item["message"]["msg_id"] for item in batch["messages"]] == [
        item["message"]["msg_id"] for item in fixture["messages"]
    ]


@pytest.mark.asyncio
async def test_send_streaming_snapshots_emits_partial_then_final_messages() -> None:
    partial = load_fixture("message-stream-partial.json")
    final = load_fixture("message-stream-final.json")
    store = ObjectStoreStub()
    keyspace = RelayKeyspace(
        id_factory=SequentialIds([
            partial["delivery"]["stream"]["stream_id"],
            "partial-key",
            partial["msg_id"],
            "final-key",
            final["msg_id"],
        ]),
        now_ms_factory=SequentialTimes([partial["ts_sent"], final["ts_sent"]]),
    )
    transport = R2RelayTransport(store=store, keyspace=keyspace, peer_id=partial["from"])

    result = await transport.send_streaming_snapshots(
        partial["to"],
        [partial["content"]["text"], final["content"]["text"]],
        options={
            "route": partial["route"],
        },
    )

    assert result["stream_id"] == partial["delivery"]["stream"]["stream_id"]
    assert len(result["results"]) == 2

    partial_write = json.loads(store.put_calls[0]["body"])
    final_write = json.loads(store.put_calls[2]["body"])

    for produced, expected in ((partial_write, partial), (final_write, final)):
        assert produced["msg_id"] == expected["msg_id"]
        assert produced["from"] == expected["from"]
        assert produced["to"] == expected["to"]
        assert produced["ts_sent"] == expected["ts_sent"]
        assert produced["content"]["type"] == expected["content"]["type"]
        assert produced["content"]["text"] == expected["content"]["text"]
        assert produced["route"] == expected["route"]
        assert produced["delivery"]["stream"]["stream_id"] == expected["delivery"]["stream"]["stream_id"]
        assert produced["delivery"]["stream"]["seq"] == expected["delivery"]["stream"]["seq"]
        assert produced["delivery"]["stream"]["state"] == expected["delivery"]["stream"]["state"]


@pytest.mark.asyncio
async def test_mark_message_processed_patches_processed_fields() -> None:
    expected = load_fixture("message-text.json")
    message = dict(expected)
    message["status"] = None
    key = "msg/relay.openclaw.dev/8235971204999-9f2c1a7b.json"
    store = ObjectStoreStub()
    store.objects[key] = {"payload": message, "etag": "etag-1"}
    transport = R2RelayTransport(store=store, keyspace=RelayKeyspace(), peer_id="relay.openclaw.dev")

    updated = await transport.mark_message_processed(
        key,
        {
            "processedAt": expected["status"]["processed_at"],
            "processedBy": expected["status"]["processed_by"],
        },
    )

    assert updated["status"]["processed_at"] == expected["status"]["processed_at"]
    assert updated["status"]["processed_by"] == expected["status"]["processed_by"]
    assert updated["status"]["state"] == expected["status"]["state"]
    assert store.objects[key]["payload"]["status"]["state"] == "done"


@pytest.mark.asyncio
async def test_poll_inbox_does_not_checkpoint_failed_message() -> None:
    fixture = load_fixture("inbox-chain.json")
    first_item = fixture["messages"][0]
    head = {
        "head_key": first_item["key"],
        "head_msg_id": first_item["message"]["msg_id"],
        "head_ts": first_item["message"]["ts_sent"],
    }
    store = ObjectStoreStub()
    store.head_reads = [{"body": head, "etag": "etag-1"}]
    store.objects[first_item["key"]] = {"payload": first_item["message"], "etag": "etag-msg"}

    abort_event = asyncio.Event()
    transport = R2RelayTransport(
        store=store,
        keyspace=RelayKeyspace(),
        peer_id="relay.hermes.local",
        sleep=PollAbortAfterFirstSleep(abort_event),
    )

    async def failing_handler(_message, _key):
        raise RuntimeError("boom")

    with pytest.raises(RuntimeError, match="boom"):
        await transport.poll_inbox(
            "clawchat-ios-alice",
            failing_handler,
            poll_interval_ms=1,
            backoff_max_ms=2,
            delete_after_processing=True,
            abort_event=abort_event,
        )

    state = transport._load_checkpoint_state()
    assert state["last_head_key"] is None
    assert state["seen"] == []
    assert store.deleted_objects == []


def test_checkpoint_helpers_remember_recent_messages() -> None:
    state = default_checkpoint_state()

    state = remember_message(state, object_key="msg/one", msg_id="id-1")
    state = remember_message(state, object_key="msg/two", msg_id="id-2")

    assert has_seen_message(state, object_key="msg/one") is True
    assert has_seen_message(state, object_key="msg/two") is True
    assert has_seen_message(state, msg_id="id-1") is True
    assert has_seen_message(state, msg_id="id-2") is True
    assert state["seen"] == ["msg/two", "msg/one"]
    assert state["seen_msg_ids"] == ["id-2", "id-1"]


@pytest.mark.asyncio
async def test_poll_inbox_deduplicates_republished_message_by_msg_id() -> None:
    message = load_fixture("message-text.json")
    first_key = "msg/relay.openclaw.dev/8235971205001-first.json"
    second_key = "msg/relay.openclaw.dev/8235971205002-second.json"
    head = {
        "head_key": second_key,
        "head_msg_id": message["msg_id"],
        "head_ts": message["ts_sent"],
    }
    store = ObjectStoreStub()
    store.head_reads = [{"body": head, "etag": "etag-head"}]
    store.objects[second_key] = {"payload": {**message, "prev_key": first_key}, "etag": "etag-2"}
    store.objects[first_key] = {"payload": {**message, "prev_key": None}, "etag": "etag-1"}

    abort_event = asyncio.Event()
    handled: list[str] = []
    checkpoint_store = InMemoryCheckpointStore(
        {
            "last_head_key": None,
            "seen": [],
            "seen_msg_ids": [message["msg_id"]],
        }
    )
    transport = R2RelayTransport(
        store=store,
        keyspace=RelayKeyspace(),
        peer_id="relay.openclaw.dev",
        checkpoint_store=checkpoint_store,
        sleep=PollAbortAfterFirstSleep(abort_event),
    )

    async def handler(_message, key):
        handled.append(key)

    await transport.poll_inbox(
        "relay.openclaw.dev",
        handler,
        poll_interval_ms=1,
        backoff_max_ms=2,
        delete_after_processing=False,
        abort_event=abort_event,
    )

    assert handled == []
    state = transport._load_checkpoint_state()
    assert state["last_head_key"] == second_key
    assert state["seen_msg_ids"] == [message["msg_id"]]
