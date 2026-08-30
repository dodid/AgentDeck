from __future__ import annotations

import re
import secrets
import time
from dataclasses import dataclass, field
from typing import Callable


MAX_MS = 9_999_999_999_999
_SAFE_FRAGMENT_RE = re.compile(r"[^a-zA-Z0-9._-]")


def sanitize_fragment(value: str | None) -> str:
    return _SAFE_FRAGMENT_RE.sub("", str(value or ""))


fragment_sanitize = sanitize_fragment


def pad_rev_ts(ts: int) -> str:
    return str(MAX_MS - int(ts)).zfill(13)


padRevTs = pad_rev_ts


def extract_timestamp_from_key(key: str) -> int | None:
    name = key.split("/")[-1].strip()
    prefix = name.split("-", 1)[0]
    if len(prefix) != 13 or not prefix.isdigit():
        return None
    return MAX_MS - int(prefix)


extract_timestamp_from_relay_key = extract_timestamp_from_key


@dataclass(slots=True)
class RelayKeyspace:
    bucket: str = ""
    id_factory: Callable[[], str] = field(default=secrets.token_hex)
    now_ms_factory: Callable[[], int] = field(default=lambda: int(time.time() * 1000))

    def __post_init__(self) -> None:
        if self.id_factory is secrets.token_hex:
            self.id_factory = lambda: secrets.token_hex(4)

    def pad_rev_ts(self, ts: int) -> str:
        return pad_rev_ts(ts)

    def short_uuid(self) -> str:
        return str(self.id_factory())

    def make_msg_key(self, recipient: str, now_ms: int | None = None, suffix: str | None = None) -> str:
        ts = int(now_ms) if now_ms is not None else self._now_ms()
        message_suffix = suffix or self.short_uuid()
        return f"msg/{recipient}/{self.pad_rev_ts(ts)}-{message_suffix}.json"

    def make_att_key(
        self,
        recipient: str,
        message_id: str,
        index: int,
        name: str | None = None,
        now_ms: int | None = None,
    ) -> str:
        ts = int(now_ms) if now_ms is not None else self._now_ms()
        safe_message_id = sanitize_fragment(message_id)
        safe_index = str(index).zfill(2)
        safe_name = sanitize_fragment(name)
        suffix = f"-{safe_name}" if safe_name else ""
        return f"att/{recipient}/{self.pad_rev_ts(ts)}-{safe_message_id}-{safe_index}{suffix}"

    def make_head_key(self, recipient: str) -> str:
        return f"head/{recipient}.json"

    def make_identity_key(self, peer: str) -> str:
        return f"identity/{peer}.json"

    def make_identify_key(self, peer: str) -> str:
        return self.make_identity_key(peer)

    def padRevTs(self, ts: int) -> str:
        return self.pad_rev_ts(ts)

    def shortUuid(self) -> str:
        return self.short_uuid()

    def makeMsgKey(self, recipient: str, nowMs: int | None = None) -> str:
        return self.make_msg_key(recipient, now_ms=nowMs)

    def makeAttKey(
        self,
        recipient: str,
        messageId: str,
        index: int,
        name: str | None = None,
        nowMs: int | None = None,
    ) -> str:
        return self.make_att_key(recipient, messageId, index, name=name, now_ms=nowMs)

    def makeHeadKey(self, recipient: str) -> str:
        return self.make_head_key(recipient)

    def makeIdentityKey(self, peer: str) -> str:
        return self.make_identity_key(peer)

    def makeIdentifyKey(self, peer: str) -> str:
        return self.make_identify_key(peer)

    def _now_ms(self) -> int:
        return int(self.now_ms_factory())


R2RelayProtocol = RelayKeyspace
