from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Awaitable, Callable

from .checkpoint import CheckpointStore, InMemoryCheckpointStore, default_checkpoint_state, has_seen_message, remember_message
from .errors import CASRetryExceededError, PreconditionFailedError
from .keyspace import RelayKeyspace, extract_timestamp_from_key
from .object_store import ObjectStore
from .types import CheckpointState, InboxBatch, JSONDict


logger = logging.getLogger(__name__)


class R2RelayTransport:
    def __init__(
        self,
        store: ObjectStore,
        keyspace: RelayKeyspace,
        peer_id: str,
        checkpoint_store: CheckpointStore | None = None,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ) -> None:
        self.store = store
        self.keyspace = keyspace
        self.peer_id = peer_id
        self.checkpoint_store = checkpoint_store or InMemoryCheckpointStore(default_checkpoint_state())
        self.sleep = sleep
        self._send_lanes: dict[str, asyncio.Lock] = {}
        self._checkpoint_state: CheckpointState | None = None

    async def publish_identity(self, payload: JSONDict | None = None) -> JSONDict:
        identity: JSONDict = {
            "peer": self.peer_id,
            "display_name": self.peer_id,
            "role": "server",
            "last_seen": self._now_ms(),
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
        if payload:
            identity.update(payload)
        key = self.keyspace.make_identity_key(str(identity["peer"]))
        await self.store.put_object(key, json.dumps(identity), "application/json")
        return identity

    async def get_head_state(self, peer: str) -> dict[str, Any] | None:
        return await self.store.get_json_with_etag(self.keyspace.make_head_key(peer))

    async def read_message(self, key: str) -> JSONDict | None:
        response = await self.store.get_object(key)
        if response is None:
            return None
        if isinstance(response, dict) and "payload" in response:
            payload = response["payload"]
            if isinstance(payload, dict):
                return dict(payload)
            if isinstance(payload, str):
                parsed = json.loads(payload)
                return parsed if isinstance(parsed, dict) else None
        if isinstance(response, dict) and "Body" in response:
            text = await _body_to_text(response["Body"])
            parsed = json.loads(text)
            return parsed if isinstance(parsed, dict) else None
        if isinstance(response, dict):
            return dict(response)
        if isinstance(response, str):
            parsed = json.loads(response)
            return parsed if isinstance(parsed, dict) else None
        return None

    async def send_message(
        self,
        to: str,
        options: dict[str, Any],
    ) -> dict[str, str]:
        lock = self._send_lanes.setdefault(to, asyncio.Lock())
        async with lock:
            return await self._send_message_unlocked(to, dict(options))

    async def send_streaming_snapshots(
        self,
        to: str,
        snapshots: list[str],
        options: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        resolved_options = dict(options or {})
        route = resolved_options["route"]
        stream_id = resolved_options.get("stream_id") or self.keyspace.short_uuid()
        base_attachments = resolved_options.get("attachments")
        results: list[dict[str, str]] = []
        non_empty = [str(s or "") for s in snapshots if str(s or "").strip()]
        for index, text in enumerate(non_empty):
            content: dict[str, Any] = {"type": "text", "text": text}
            if base_attachments:
                content["attachments"] = base_attachments
            delivery: dict[str, Any] = {
                "stream": {
                    "stream_id": stream_id,
                    "seq": index + 1,
                    "state": "final" if index == len(non_empty) - 1 else "partial",
                }
            }
            results.append(
                await self.send_message(to, {"route": route, "content": content, "delivery": delivery})
            )
        return {"stream_id": stream_id, "results": results}

    async def collect_inbox_messages(self, self_id: str, last_seen_key: str | None) -> InboxBatch:
        head_state = await self.get_head_state(self_id)
        head = head_state.get("body") if isinstance(head_state, dict) else None
        if not head or not head.get("head_key"):
            return {"head": head, "messages": []}
        if head.get("head_key") == last_seen_key:
            return {"head": head, "messages": []}

        current = str(head["head_key"])
        messages: list[dict[str, Any]] = []
        visited: set[str] = set()
        while current and current != last_seen_key:
            if current in visited:
                break
            if len(messages) >= 500:
                break
            visited.add(current)
            message = await self.read_message(current)
            if not message:
                break
            messages.append({"key": current, "message": message})
            current = message.get("prev_key") or None

        messages.reverse()
        return {"head": head, "messages": messages}

    async def mark_message_processed(self, key: str, patch: dict[str, Any] | None = None) -> JSONDict | None:
        message = await self.read_message(key)
        if message is None:
            return None
        resolved_patch = dict(patch or {})
        updated: JSONDict = {
            **message,
            "status": {
                "state": resolved_patch.get("state", "done"),
                "processed_at": resolved_patch.get("processedAt", self._now_ms()),
                "processed_by": resolved_patch.get("processedBy", self.peer_id),
            },
        }
        await self.store.put_object(key, json.dumps(updated), "application/json")
        return updated

    async def sweep_by_key_timestamp(self, prefix: str, ttl_days: int) -> dict[str, Any]:
        cutoff_ms = self._now_ms() - ttl_days * 24 * 60 * 60 * 1000
        continuation_token = None
        scanned = 0
        deleted = 0
        while True:
            page = await self.store.list_prefix_page(prefix, continuation_token=continuation_token, max_keys=1000)
            to_delete: list[str] = []
            for item in page.get("contents") or []:
                key = item.get("Key") if isinstance(item, dict) else None
                if not key:
                    continue
                scanned += 1
                ts = extract_timestamp_from_key(key)
                if ts is not None and ts < cutoff_ms:
                    to_delete.append(key)
            if to_delete:
                await self.store.delete_objects(to_delete)
                deleted += len(to_delete)
            if not page.get("is_truncated") or not page.get("next_continuation_token"):
                break
            continuation_token = page["next_continuation_token"]
        return {"prefix": prefix, "scanned": scanned, "deleted": deleted}

    async def poll_inbox(
        self,
        self_id: str,
        handler: Callable[[JSONDict, str], Awaitable[None]],
        poll_interval_ms: int = 5000,
        backoff_max_ms: int = 40000,
        delete_after_processing: bool = True,
        abort_event: asyncio.Event | None = None,
    ) -> None:
        interval_ms = poll_interval_ms
        state = self._load_checkpoint_state()
        try:
            while not (abort_event and abort_event.is_set()):
                batch = await self.collect_inbox_messages(self_id, state.get("last_head_key"))
                if batch["messages"]:
                    for item in batch["messages"]:
                        msg_id = item["message"].get("msg_id") if isinstance(item.get("message"), dict) else None
                        if has_seen_message(state, object_key=item["key"], msg_id=msg_id):
                            state["last_head_key"] = item["key"]
                            self._save_checkpoint_state(state)
                            continue

                        await handler(item["message"], item["key"])
                        state = remember_message(state, object_key=item["key"], msg_id=msg_id)
                        state["last_head_key"] = item["key"]
                        self._save_checkpoint_state(state)

                        if delete_after_processing:
                            await self.store.delete_object(item["key"])
                    interval_ms = poll_interval_ms
                else:
                    await self.sleep(interval_ms / 1000)
                    if not (batch.get("head") or {}).get("head_key"):
                        interval_ms = min(interval_ms * 2, backoff_max_ms)
                    continue
                await self.sleep(interval_ms / 1000)
        finally:
            self._save_checkpoint_state(state)

    async def _send_message_unlocked(
        self,
        to: str,
        options: dict[str, Any],
    ) -> dict[str, str]:
        now_ms = self._now_ms()
        head_key = self.keyspace.make_head_key(to)
        route = options["route"]
        content = options["content"]
        delivery = options.get("delivery")
        for _attempt in range(1, 9):
            current_head = await self.get_head_state(to)
            current_head_body = current_head.get("body") if isinstance(current_head, dict) else None
            prev_key = current_head_body.get("head_key") if isinstance(current_head_body, dict) else None
            key = self.keyspace.make_msg_key(to, now_ms=now_ms)
            message_id = self.keyspace.short_uuid()
            text = content.get("text", "") if isinstance(content, dict) else ""
            message: JSONDict = {
                "msg_id": message_id,
                "from": self.peer_id,
                "to": to,
                "ts_sent": now_ms,
                "prev_key": prev_key,
                "route": route,
                "content": content,
                "delivery": delivery,
                "status": None,
                "size": len(text.encode("utf-8")) if content.get("type") == "text" else None,
            }
            new_head = {
                "head_key": key,
                "head_msg_id": message_id,
                "head_ts": now_ms,
            }
            await self.store.put_object(key, json.dumps(message), "application/json", if_none_match="*")
            try:
                if current_head and current_head.get("etag"):
                    await self.store.put_object(
                        head_key,
                        json.dumps(new_head),
                        "application/json",
                        if_match=current_head["etag"],
                    )
                else:
                    await self.store.put_object(
                        head_key,
                        json.dumps(new_head),
                        "application/json",
                        if_none_match="*",
                    )
                return {"key": key, "message_id": message_id}
            except PreconditionFailedError:
                await self.sleep(0.02)
        raise CASRetryExceededError("Failed to append message after CAS retries")

    def _load_checkpoint_state(self) -> CheckpointState:
        if self._checkpoint_state is None:
            self._checkpoint_state = self.checkpoint_store.load()
        return {
            "last_head_key": self._checkpoint_state.get("last_head_key"),
            "seen": list(self._checkpoint_state.get("seen") or []),
            "seen_msg_ids": list(self._checkpoint_state.get("seen_msg_ids") or []),
        }

    def _save_checkpoint_state(self, state: CheckpointState) -> None:
        snapshot: CheckpointState = {
            "last_head_key": state.get("last_head_key"),
            "seen": list(state.get("seen") or []),
            "seen_msg_ids": list(state.get("seen_msg_ids") or []),
        }
        self.checkpoint_store.save(snapshot)
        self._checkpoint_state = snapshot

    def _now_ms(self) -> int:
        return self.keyspace.now_ms_factory()


async def _body_to_text(body: Any) -> str:
    chunks = await _body_to_chunks(body)
    return b"".join(chunks).decode("utf-8")


async def _body_to_chunks(body: Any) -> list[bytes]:
    if hasattr(body, "__aiter__"):
        chunks: list[bytes] = []
        async for chunk in body:
            chunks.append(chunk if isinstance(chunk, bytes) else bytes(chunk))
        return chunks
    return await asyncio.to_thread(_sync_body_to_chunks, body)


def _sync_body_to_chunks(body: Any) -> list[bytes]:
    if hasattr(body, "iter_chunks") and callable(body.iter_chunks):
        iterator = body.iter_chunks()
    elif hasattr(body, "read") and callable(body.read):
        data = body.read()
        if data is None:
            return []
        iterator = [data]
    elif hasattr(body, "__iter__"):
        iterator = iter(body)
    else:
        raise TypeError(f"Unsupported response body type: {type(body)!r}")
    chunks: list[bytes] = []
    for chunk in iterator:
        if isinstance(chunk, tuple) and chunk:
            chunk = chunk[0]
        if chunk is None:
            continue
        chunks.append(chunk if isinstance(chunk, bytes) else bytes(chunk))
    return chunks


R2RelayService = R2RelayTransport
