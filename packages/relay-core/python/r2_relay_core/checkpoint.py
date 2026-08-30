from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Protocol

from .types import CheckpointState


RECENT_MESSAGE_IDS_LIMIT = 200
DEFAULT_CHECKPOINT: CheckpointState = {
    "last_head_key": None,
    "seen": [],
    "seen_msg_ids": [],
}


class CheckpointStore(Protocol):
    def load(self) -> CheckpointState:
        ...

    def save(self, state: CheckpointState) -> None:
        ...


def default_checkpoint_state() -> CheckpointState:
    return {
        "last_head_key": DEFAULT_CHECKPOINT["last_head_key"],
        "seen": list(DEFAULT_CHECKPOINT["seen"]),
        "seen_msg_ids": list(DEFAULT_CHECKPOINT["seen_msg_ids"]),
    }


def _normalize_checkpoint(data: dict[str, Any] | None) -> CheckpointState:
    raw = dict(data or {})
    seen = raw.get("seen")
    if not isinstance(seen, list):
        seen = []
    filtered_seen = [value for value in seen if isinstance(value, str)]
    seen_msg_ids = raw.get("seen_msg_ids")
    if not isinstance(seen_msg_ids, list):
        seen_msg_ids = []
    filtered_msg_ids = [value for value in seen_msg_ids if isinstance(value, str)]
    last_head_key = raw.get("last_head_key")
    if last_head_key is not None and not isinstance(last_head_key, str):
        last_head_key = None
    return {
        "last_head_key": last_head_key,
        "seen": filtered_seen[:RECENT_MESSAGE_IDS_LIMIT],
        "seen_msg_ids": filtered_msg_ids[:RECENT_MESSAGE_IDS_LIMIT],
    }


class InMemoryCheckpointStore:
    def __init__(self, state: dict[str, Any] | None = None) -> None:
        self._state = _normalize_checkpoint(state)

    def load(self) -> CheckpointState:
        return _normalize_checkpoint(self._state)

    def save(self, state: CheckpointState) -> None:
        self._state = _normalize_checkpoint(state)


class FileCheckpointStore:
    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)

    def load(self) -> CheckpointState:
        return load_checkpoint(self.path)

    def save(self, state: CheckpointState) -> None:
        save_checkpoint(self.path, state)


def load_checkpoint(path: str | Path) -> CheckpointState:
    checkpoint_path = Path(path)
    if not checkpoint_path.exists():
        return default_checkpoint_state()
    try:
        payload = json.loads(checkpoint_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default_checkpoint_state()
    if not isinstance(payload, dict):
        return default_checkpoint_state()
    return _normalize_checkpoint(payload)


def save_checkpoint(path: str | Path, state: dict[str, Any]) -> None:
    checkpoint_path = Path(path)
    checkpoint_path.parent.mkdir(parents=True, exist_ok=True)
    normalized = _normalize_checkpoint(state)
    tmp_path = checkpoint_path.with_suffix(checkpoint_path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(normalized, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp_path.replace(checkpoint_path)


def remember_message(
    state: dict[str, Any],
    *,
    object_key: str | None = None,
    msg_id: str | None = None,
) -> CheckpointState:
    normalized = _normalize_checkpoint(state)
    seen = list(normalized["seen"])
    seen_msg_ids = list(normalized["seen_msg_ids"])
    if object_key:
        seen = [object_key, *[value for value in seen if value != object_key]]
    if msg_id:
        seen_msg_ids = [msg_id, *[value for value in seen_msg_ids if value != msg_id]]
    return {
        "last_head_key": normalized["last_head_key"],
        "seen": seen[:RECENT_MESSAGE_IDS_LIMIT],
        "seen_msg_ids": seen_msg_ids[:RECENT_MESSAGE_IDS_LIMIT],
    }


def has_seen_message(
    state: dict[str, Any],
    *,
    object_key: str | None = None,
    msg_id: str | None = None,
) -> bool:
    normalized = _normalize_checkpoint(state)
    return bool(
        (object_key and object_key in normalized["seen"])
        or (msg_id and msg_id in normalized["seen_msg_ids"])
    )
