"""r2_relay_adapter package."""

from __future__ import annotations

__version__ = "0.1.0"

__all__ = [
    "__version__",
    "DEFAULT_BACKOFF_MAX_MS",
    "DEFAULT_FORCE_PATH_STYLE",
    "DEFAULT_POLL_INTERVAL_MS",
    "DEFAULT_REGION",
    "MAX_MS",
    "FileCheckpointStore",
    "PreconditionFailedError",
    "R2RelayAdapter",
    "R2RelayClient",
    "R2RelayEnvConfig",
    "PLUGIN_DIR_NAME",
    "PLATFORM_NAME",
    "R2RelayProtocol",
    "R2RelayService",
    "apply_r2_relay_settings",
    "check_r2_relay_requirements",
    "extract_timestamp_from_relay_key",
    "has_seen_message",
    "load_checkpoint",
    "load_env_file",
    "normalize_etag",
    "normalize_server_id",
    "remember_message",
    "resolve_default_server_id",
    "resolve_r2_relay_env_config",
    "save_checkpoint",
    "save_env_file",
]


def __getattr__(name: str):
    if name in {"R2RelayAdapter", "check_r2_relay_requirements"}:
        from .adapter import R2RelayAdapter, check_r2_relay_requirements

        exported = {
            "R2RelayAdapter": R2RelayAdapter,
            "check_r2_relay_requirements": check_r2_relay_requirements,
        }
        return exported[name]

    if name in {"FileCheckpointStore", "has_seen_message", "load_checkpoint", "remember_message", "save_checkpoint"}:
        from .checkpoint_store import FileCheckpointStore, has_seen_message, load_checkpoint, remember_message, save_checkpoint

        exported = {
            "FileCheckpointStore": FileCheckpointStore,
            "has_seen_message": has_seen_message,
            "load_checkpoint": load_checkpoint,
            "remember_message": remember_message,
            "save_checkpoint": save_checkpoint,
        }
        return exported[name]

    if name in {"PreconditionFailedError", "R2RelayClient", "normalize_etag"}:
        from .client import PreconditionFailedError, R2RelayClient, normalize_etag

        exported = {
            "PreconditionFailedError": PreconditionFailedError,
            "R2RelayClient": R2RelayClient,
            "normalize_etag": normalize_etag,
        }
        return exported[name]

    if name in {
        "DEFAULT_BACKOFF_MAX_MS",
        "DEFAULT_FORCE_PATH_STYLE",
        "DEFAULT_POLL_INTERVAL_MS",
        "DEFAULT_REGION",
        "R2RelayEnvConfig",
        "normalize_server_id",
        "resolve_default_server_id",
        "resolve_r2_relay_env_config",
    }:
        from .config import (
            DEFAULT_BACKOFF_MAX_MS,
            DEFAULT_FORCE_PATH_STYLE,
            DEFAULT_POLL_INTERVAL_MS,
            DEFAULT_REGION,
            R2RelayEnvConfig,
            normalize_server_id,
            resolve_default_server_id,
            resolve_r2_relay_env_config,
        )

        exported = {
            "DEFAULT_BACKOFF_MAX_MS": DEFAULT_BACKOFF_MAX_MS,
            "DEFAULT_FORCE_PATH_STYLE": DEFAULT_FORCE_PATH_STYLE,
            "DEFAULT_POLL_INTERVAL_MS": DEFAULT_POLL_INTERVAL_MS,
            "DEFAULT_REGION": DEFAULT_REGION,
            "R2RelayEnvConfig": R2RelayEnvConfig,
            "normalize_server_id": normalize_server_id,
            "resolve_default_server_id": resolve_default_server_id,
            "resolve_r2_relay_env_config": resolve_r2_relay_env_config,
        }
        return exported[name]

    if name in {"apply_r2_relay_settings", "load_env_file", "save_env_file"}:
        from .config_wizard import apply_r2_relay_settings, load_env_file, save_env_file

        exported = {
            "apply_r2_relay_settings": apply_r2_relay_settings,
            "load_env_file": load_env_file,
            "save_env_file": save_env_file,
        }
        return exported[name]

    if name in {"PLATFORM_NAME", "PLUGIN_DIR_NAME"}:
        from .install_manifest import PLATFORM_NAME, PLUGIN_DIR_NAME

        exported = {
            "PLATFORM_NAME": PLATFORM_NAME,
            "PLUGIN_DIR_NAME": PLUGIN_DIR_NAME,
        }
        return exported[name]

    if name in {"MAX_MS", "R2RelayProtocol"}:
        from .protocol import MAX_MS, R2RelayProtocol

        exported = {
            "MAX_MS": MAX_MS,
            "R2RelayProtocol": R2RelayProtocol,
        }
        return exported[name]

    if name in {"R2RelayService", "extract_timestamp_from_relay_key"}:
        from .service import R2RelayService, extract_timestamp_from_relay_key

        exported = {
            "R2RelayService": R2RelayService,
            "extract_timestamp_from_relay_key": extract_timestamp_from_relay_key,
        }
        return exported[name]

    raise AttributeError(name)
