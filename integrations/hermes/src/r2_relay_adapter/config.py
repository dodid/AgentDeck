"""Environment-first configuration helpers for the R2 relay adapter."""

from __future__ import annotations

import os
import re
import socket
from dataclasses import dataclass
from typing import Any, Mapping

DEFAULT_POLL_INTERVAL_MS = 5_000
DEFAULT_BACKOFF_MAX_MS = 40_000
DEFAULT_REGION = "auto"
DEFAULT_FORCE_PATH_STYLE = True

_SERVER_ID_RE = re.compile(r"[^a-zA-Z0-9._-]")


@dataclass(frozen=True, slots=True)
class R2RelayEnvConfig:
    enabled: bool
    configured: bool
    config_file: str
    endpoint: str
    bucket: str
    access_key_id: str
    secret_access_key: str
    server_id: str
    display_name: str
    discovery_conversation_id: str
    discovery_conversation_title: str | None
    discovery_thread_id: str | None
    available_models: tuple[dict[str, str | None], ...]
    default_model: str | None
    inbound_attachment_max_bytes: dict[str, int] | None
    oversize_attachment_behavior: str | None
    region: str
    force_path_style: bool
    poll_interval_ms: int
    backoff_max_ms: int

    def boto3_client_kwargs(self) -> dict[str, Any]:
        try:
            from botocore.config import Config as BotoConfig
        except ImportError:
            class BotoConfig:  # type: ignore[no-redef]
                def __init__(self, **kwargs: Any) -> None:
                    self.__dict__.update(kwargs)

        return {
            "service_name": "s3",
            "endpoint_url": self.endpoint,
            "aws_access_key_id": self.access_key_id,
            "aws_secret_access_key": self.secret_access_key,
            "region_name": self.region,
            "config": BotoConfig(
                s3={
                    "addressing_style": "path" if self.force_path_style else "virtual",
                }
            ),
        }

    def create_s3_client(self):
        import boto3

        return boto3.client(**self.boto3_client_kwargs())


def normalize_server_id(value: str | None) -> str | None:
    trimmed = (value or "").strip()
    if not trimmed:
        return None
    normalized = re.sub(r"\s+", "-", trimmed)
    normalized = _SERVER_ID_RE.sub("-", normalized)
    collapsed = re.sub(r"-+", "-", normalized).strip("-_.")
    return collapsed or None


def resolve_default_server_id() -> str:
    hostname = socket.gethostname().strip()
    return normalize_server_id(hostname) or "r2-relay-server"


def derive_default_display_name(server_id: str) -> str:
    normalized = str(server_id or '').strip()
    if not normalized:
        return 'Gateway'
    return re.sub(r'\s+', ' ', re.sub(r'[-_.]+', ' ', normalized)).strip().title() or 'Gateway'


def _coerce_bool(value: Any, *, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"1", "true", "yes", "on"}:
            return True
        if lowered in {"0", "false", "no", "off"}:
            return False
    return default


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        value = int(raw)
    except ValueError:
        return default
    return value if value > 0 else default


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    return _coerce_bool(raw, default=default)


def _env_optional_text(name: str) -> str | None:
    raw = os.getenv(name, '').strip()
    return raw or None


def _env_optional_positive_int(name: str) -> int | None:
    raw = os.getenv(name, '').strip()
    if not raw:
        return None
    try:
        value = int(raw)
    except ValueError:
        return None
    return value if value > 0 else None


def _parse_model_entry(raw_entry: str) -> dict[str, str | None] | None:
    raw = raw_entry.strip()
    if not raw:
        return None
    parts = [part.strip() for part in raw.split("|")]
    model_id = parts[0] if parts else ""
    if not model_id:
        return None
    label = parts[1] if len(parts) > 1 and parts[1] else None
    provider = parts[2] if len(parts) > 2 and parts[2] else None
    if provider is None and "/" in model_id:
        provider = model_id.split("/", 1)[0] or None
    return {
        "id": model_id,
        "label": label,
        "provider": provider,
    }


def _env_model_list(name: str) -> tuple[dict[str, str | None], ...]:
    raw = os.getenv(name, "").strip()
    if not raw:
        return ()
    entries: list[dict[str, str | None]] = []
    seen_ids: set[str] = set()
    for candidate in raw.split(","):
        parsed = _parse_model_entry(candidate)
        if parsed is None:
            continue
        model_id = str(parsed["id"])
        if model_id in seen_ids:
            continue
        seen_ids.add(model_id)
        entries.append(parsed)
    return tuple(entries)


def _extra_config_file(extra: Mapping[str, Any]) -> str:
    raw = extra.get("config_file") or extra.get("configFile") or ""
    return str(raw).strip() if raw is not None else ""


def resolve_r2_relay_env_config(extra: Mapping[str, Any] | None = None) -> R2RelayEnvConfig:
    extra = dict(extra or {})
    endpoint = os.getenv("R2_RELAY_ENDPOINT", "").strip()
    bucket = os.getenv("R2_RELAY_BUCKET", "").strip()
    access_key_id = os.getenv("R2_RELAY_ACCESS_KEY_ID", "").strip()
    secret_access_key = os.getenv("R2_RELAY_SECRET_ACCESS_KEY", "").strip()
    server_id = normalize_server_id(os.getenv("R2_RELAY_SERVER_ID")) or resolve_default_server_id()
    display_name = _env_optional_text('R2_RELAY_DISPLAY_NAME') or derive_default_display_name(server_id)
    poll_interval_ms = _env_int("R2_RELAY_POLL_INTERVAL_MS", DEFAULT_POLL_INTERVAL_MS)
    backoff_max_ms = _env_int("R2_RELAY_BACKOFF_MAX_MS", DEFAULT_BACKOFF_MAX_MS)
    configured = all((endpoint, bucket, access_key_id, secret_access_key))
    discovery_conversation_id = _env_optional_text('R2_RELAY_DISCOVERY_CONVERSATION_ID') or 'main'
    discovery_conversation_title = _env_optional_text('R2_RELAY_DISCOVERY_CONVERSATION_TITLE')
    discovery_thread_id = _env_optional_text('R2_RELAY_DISCOVERY_THREAD_ID')
    available_models = _env_model_list('R2_RELAY_MODELS')
    default_model = _env_optional_text('R2_RELAY_DEFAULT_MODEL')
    inbound_attachment_max_bytes = {
        key: value
        for key, value in {
            'image': _env_optional_positive_int('R2_RELAY_MAX_INBOUND_IMAGE_BYTES'),
            'video': _env_optional_positive_int('R2_RELAY_MAX_INBOUND_VIDEO_BYTES'),
            'audio': _env_optional_positive_int('R2_RELAY_MAX_INBOUND_AUDIO_BYTES'),
            'file': _env_optional_positive_int('R2_RELAY_MAX_INBOUND_FILE_BYTES'),
        }.items()
        if value is not None
    } or None

    return R2RelayEnvConfig(
        enabled=_coerce_bool(extra.get("enabled"), default=True),
        configured=configured,
        config_file=_extra_config_file(extra),
        endpoint=endpoint,
        bucket=bucket,
        access_key_id=access_key_id,
        secret_access_key=secret_access_key,
        server_id=server_id,
        display_name=display_name,
        discovery_conversation_id=discovery_conversation_id,
        discovery_conversation_title=discovery_conversation_title,
        discovery_thread_id=discovery_thread_id,
        available_models=available_models,
        default_model=default_model,
        inbound_attachment_max_bytes=inbound_attachment_max_bytes,
        oversize_attachment_behavior=_env_optional_text('R2_RELAY_OVERSIZE_ATTACHMENT_BEHAVIOR'),
        region=os.getenv("R2_RELAY_REGION", DEFAULT_REGION).strip() or DEFAULT_REGION,
        force_path_style=_env_bool("R2_RELAY_FORCE_PATH_STYLE", DEFAULT_FORCE_PATH_STYLE),
        poll_interval_ms=poll_interval_ms,
        backoff_max_ms=backoff_max_ms,
    )
