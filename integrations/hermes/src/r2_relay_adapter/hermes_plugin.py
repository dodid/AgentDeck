"""Hermes platform-plugin registration for the R2 relay adapter."""

from __future__ import annotations

import logging
import mimetypes
import os
import time
from pathlib import Path
from typing import Any

from .adapter import R2RelayAdapter, check_r2_relay_requirements
from .config import resolve_r2_relay_env_config
from .install_manifest import PLATFORM_NAME

logger = logging.getLogger(__name__)


def _validate_config(config: Any) -> bool:
    extra = getattr(config, "extra", {}) or {}
    return resolve_r2_relay_env_config(extra).configured


def _env_enablement() -> dict[str, Any] | None:
    cfg = resolve_r2_relay_env_config({})
    if not cfg.configured:
        return None

    seed: dict[str, Any] = {
        "endpoint": cfg.endpoint,
        "bucket": cfg.bucket,
        "access_key_id": cfg.access_key_id,
        "server_id": cfg.server_id,
        "display_name": cfg.display_name,
    }

    home_chat_id = os.getenv("R2_RELAY_HOME_CHANNEL", "").strip()
    if home_chat_id:
        seed["home_channel"] = {
            "chat_id": home_chat_id,
            "name": os.getenv("R2_RELAY_HOME_CHANNEL_NAME", "R2 Relay Home").strip() or "R2 Relay Home",
            "thread_id": os.getenv("R2_RELAY_HOME_CHANNEL_THREAD_ID", "").strip() or None,
        }
    return seed


async def _standalone_send(
    pconfig: Any,
    chat_id: str,
    message: str,
    *,
    thread_id: str | None = None,
    media_files: list | None = None,
    force_document: bool = False,
) -> dict[str, Any]:
    """Deliver a message via R2 relay without a live gateway adapter.

    Used by ``tools/send_message_tool`` when ``hermes cron`` runs in a
    separate process from ``hermes gateway`` and there is no live adapter
    weakref to call through.  Opens an ephemeral R2RelayClient, sends, and
    returns.
    """
    from .address_mapping import parse_relay_target, build_source_chat_id
    from .checkpoint_store import FileCheckpointStore
    from .client import R2RelayClient
    from .outbound_mapping import build_send_options
    from .service_factory import build_relay_service

    extra = getattr(pconfig, "extra", {}) or {}
    cfg = resolve_r2_relay_env_config(extra)
    if not cfg.configured:
        return {"error": "R2 relay standalone send: R2_RELAY_ENDPOINT, R2_RELAY_BUCKET, R2_RELAY_ACCESS_KEY_ID, and R2_RELAY_SECRET_ACCESS_KEY are all required"}

    try:
        client = R2RelayClient.from_env_config(cfg)
        hermes_home = Path(os.getenv("HERMES_HOME", "").strip() or Path.home() / ".hermes")
        checkpoint_path = hermes_home / "r2-relay-adapter" / "checkpoint.json"
        service = build_relay_service(
            config=cfg,
            client=client,
            checkpoint_store=FileCheckpointStore(checkpoint_path),
        )
        target_peer, target_conversation_id = parse_relay_target(chat_id)
        attachments = None
        if media_files:
            att_list = []
            for file_path in media_files:
                try:
                    p = Path(file_path)
                    data = p.read_bytes()
                    file_name = p.name
                    content_type = mimetypes.guess_type(file_name)[0] or "application/octet-stream"
                    message_id = f"standalone-{int(time.time() * 1000)}"
                    att = await service.store_attachment(
                        recipient=target_peer,
                        message_id=message_id,
                        index=len(att_list) + 1,
                        data=data,
                        file_name=file_name,
                        content_type=content_type,
                    )
                    att_list.append(att)
                except Exception as exc:
                    logger.warning("r2 relay standalone send: skipping media_file %s: %s", file_path, exc)
            attachments = att_list or None

        metadata = {"instance_id": thread_id} if thread_id else None
        options = build_send_options(target_conversation_id, message, attachments, metadata)

        result = await service.send_message(target_peer, options)
        return {"success": True, "message_id": result.get("message_id")}
    except Exception as exc:
        logger.debug("r2 relay standalone send raised", exc_info=True)
        return {"error": f"R2 relay standalone send failed: {exc}"}


def register(ctx) -> None:
    """Register the R2 relay adapter with Hermes' platform registry."""
    ctx.register_platform(
        name=PLATFORM_NAME,
        label="R2 Relay",
        adapter_factory=lambda cfg: R2RelayAdapter(cfg),
        check_fn=check_r2_relay_requirements,
        validate_config=_validate_config,
        is_connected=_validate_config,
        required_env=[
            "R2_RELAY_ENDPOINT",
            "R2_RELAY_BUCKET",
            "R2_RELAY_ACCESS_KEY_ID",
            "R2_RELAY_SECRET_ACCESS_KEY",
        ],
        install_hint="pip install r2-relay-adapter",
        env_enablement_fn=_env_enablement,
        standalone_sender_fn=_standalone_send,
        cron_deliver_env_var="R2_RELAY_HOME_CHANNEL",
        allowed_users_env="R2_RELAY_ALLOWED_USERS",
        allow_all_env="R2_RELAY_ALLOW_ALL_USERS",
        emoji="☁️",
        allow_update_command=True,
        platform_hint=(
            "You are chatting through the R2 Relay transport. Plain text is safe. "
            "File, image, audio, and video attachments are supported when the local "
            "file path is available. Use MEDIA:/absolute/path when you need Hermes "
            "to upload a local file."
        ),
    )
