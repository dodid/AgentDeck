"""Interactive configuration wizard for enabling the R2 relay in Hermes."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import Mapping

from .config import derive_default_display_name, resolve_default_server_id

REQUIRED_ENV_VARS = [
    "R2_RELAY_ENDPOINT",
    "R2_RELAY_BUCKET",
    "R2_RELAY_ACCESS_KEY_ID",
    "R2_RELAY_SECRET_ACCESS_KEY",
    "R2_RELAY_SERVER_ID",
]

DERIVED_ENV_VARS = [
    "R2_RELAY_DISPLAY_NAME",
    "R2_RELAY_DISCOVERY_CONVERSATION_ID",
    "R2_RELAY_OVERSIZE_ATTACHMENT_BEHAVIOR",
    "R2_RELAY_POLL_INTERVAL_MS",
    "R2_RELAY_BACKOFF_MAX_MS",
]

OPTIONAL_ENV_VARS = [
    "R2_RELAY_HOME_CHANNEL",
    "R2_RELAY_HOME_CHANNEL_NAME",
    "R2_RELAY_HOME_CHANNEL_THREAD_ID",
    "R2_RELAY_DISCOVERY_CONVERSATION_TITLE",
    "R2_RELAY_DISCOVERY_THREAD_ID",
    "R2_RELAY_MODELS",
    "R2_RELAY_DEFAULT_MODEL",
    "R2_RELAY_MAX_INBOUND_IMAGE_BYTES",
    "R2_RELAY_MAX_INBOUND_VIDEO_BYTES",
    "R2_RELAY_MAX_INBOUND_AUDIO_BYTES",
    "R2_RELAY_MAX_INBOUND_FILE_BYTES",
    "R2_RELAY_ALLOWED_USERS",
    "R2_RELAY_ALLOW_ALL_USERS",
]

ALL_ENV_VARS = REQUIRED_ENV_VARS + DERIVED_ENV_VARS + OPTIONAL_ENV_VARS
DEFAULT_DISCOVERY_CONVERSATION_ID = "main"
DEFAULT_OVERSIZE_BEHAVIOR = "reject"
DEFAULT_HOME_CHANNEL_NAME = "R2 Relay Home"


def default_hermes_home() -> Path:
    configured = os.getenv("HERMES_HOME", "").strip()
    if configured:
        return Path(configured).expanduser()
    return Path.home() / ".hermes"


def load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def save_env_file(path: Path, values: Mapping[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"{key}={value}" for key, value in values.items()]
    path.write_text(("\n".join(lines) + "\n") if lines else "", encoding="utf-8")


def apply_r2_relay_settings(
    *,
    hermes_home: Path,
    values: Mapping[str, str | None],
    home_channel: str | None = None,
    home_channel_name: str = DEFAULT_HOME_CHANNEL_NAME,
    home_channel_thread_id: str | None = None,
) -> None:
    env_path = hermes_home / ".env"

    env_values = load_env_file(env_path)
    provided_values = dict(values)

    for key in ALL_ENV_VARS:
        if key not in provided_values:
            continue
        value = provided_values.get(key)
        if value is None or str(value).strip() == "":
            env_values.pop(key, None)
        else:
            env_values[key] = str(value).strip()

    if home_channel is None or str(home_channel).strip() == "":
        env_values.pop("R2_RELAY_HOME_CHANNEL", None)
        env_values.pop("R2_RELAY_HOME_CHANNEL_NAME", None)
        env_values.pop("R2_RELAY_HOME_CHANNEL_THREAD_ID", None)
    else:
        env_values["R2_RELAY_HOME_CHANNEL"] = str(home_channel).strip()
        env_values["R2_RELAY_HOME_CHANNEL_NAME"] = home_channel_name.strip() or DEFAULT_HOME_CHANNEL_NAME
        if home_channel_thread_id and str(home_channel_thread_id).strip():
            env_values["R2_RELAY_HOME_CHANNEL_THREAD_ID"] = str(home_channel_thread_id).strip()
        else:
            env_values.pop("R2_RELAY_HOME_CHANNEL_THREAD_ID", None)
    save_env_file(env_path, env_values)


def prompt_value(label: str, default: str = "", *, secret: bool = False) -> str:
    prompt = f"{label}"
    if default:
        prompt += f" [{default}]"
    prompt += ": "

    if secret:
        try:
            import getpass

            entered = getpass.getpass(prompt)
        except Exception:
            entered = input(prompt)
    else:
        entered = input(prompt)
    return entered.strip() or default


def collect_wizard_values(existing: Mapping[str, str]) -> tuple[dict[str, str], str | None]:
    default_server_id = existing.get("R2_RELAY_SERVER_ID") or resolve_default_server_id()
    default_display_name = existing.get("R2_RELAY_DISPLAY_NAME") or derive_default_display_name(default_server_id)

    print("R2 Relay configuration wizard")
    print("This writes relay settings into ~/.hermes/.env for the Hermes platform plugin.")
    print()

    values = {
        "R2_RELAY_ENDPOINT": prompt_value("R2 endpoint URL", existing.get("R2_RELAY_ENDPOINT", "")),
        "R2_RELAY_BUCKET": prompt_value("R2 bucket", existing.get("R2_RELAY_BUCKET", "")),
        "R2_RELAY_ACCESS_KEY_ID": prompt_value("R2 access key ID", existing.get("R2_RELAY_ACCESS_KEY_ID", "")),
        "R2_RELAY_SECRET_ACCESS_KEY": prompt_value(
            "R2 secret access key",
            existing.get("R2_RELAY_SECRET_ACCESS_KEY", ""),
            secret=True,
        ),
        "R2_RELAY_SERVER_ID": prompt_value("Relay server ID", default_server_id),
    }

    use_advanced = prompt_value("Configure advanced relay options? true/false", "false").lower() in {"1", "true", "yes", "on"}
    if use_advanced:
        values["R2_RELAY_DISPLAY_NAME"] = prompt_value("Display name", existing.get("R2_RELAY_DISPLAY_NAME", default_display_name))
        values["R2_RELAY_DISCOVERY_CONVERSATION_ID"] = prompt_value(
            "Discovery conversation ID",
            existing.get("R2_RELAY_DISCOVERY_CONVERSATION_ID", DEFAULT_DISCOVERY_CONVERSATION_ID),
        )
        values["R2_RELAY_DISCOVERY_CONVERSATION_TITLE"] = prompt_value(
            "Discovery conversation title (optional)",
            existing.get("R2_RELAY_DISCOVERY_CONVERSATION_TITLE", ""),
        )
        values["R2_RELAY_DISCOVERY_THREAD_ID"] = prompt_value(
            "Discovery thread ID (optional)",
            existing.get("R2_RELAY_DISCOVERY_THREAD_ID", ""),
        )
        values["R2_RELAY_MODELS"] = prompt_value(
            "Available models (comma-separated id|label|provider, optional)",
            existing.get("R2_RELAY_MODELS", ""),
        )
        values["R2_RELAY_DEFAULT_MODEL"] = prompt_value(
            "Default model ID (optional)",
            existing.get("R2_RELAY_DEFAULT_MODEL", ""),
        )
        values["R2_RELAY_MAX_INBOUND_IMAGE_BYTES"] = prompt_value(
            "Max inbound image bytes (optional)",
            existing.get("R2_RELAY_MAX_INBOUND_IMAGE_BYTES", ""),
        )
        values["R2_RELAY_MAX_INBOUND_VIDEO_BYTES"] = prompt_value(
            "Max inbound video bytes (optional)",
            existing.get("R2_RELAY_MAX_INBOUND_VIDEO_BYTES", ""),
        )
        values["R2_RELAY_MAX_INBOUND_AUDIO_BYTES"] = prompt_value(
            "Max inbound audio bytes (optional)",
            existing.get("R2_RELAY_MAX_INBOUND_AUDIO_BYTES", ""),
        )
        values["R2_RELAY_MAX_INBOUND_FILE_BYTES"] = prompt_value(
            "Max inbound file bytes (optional)",
            existing.get("R2_RELAY_MAX_INBOUND_FILE_BYTES", ""),
        )
        values["R2_RELAY_OVERSIZE_ATTACHMENT_BEHAVIOR"] = prompt_value(
            "Oversize attachment behavior",
            existing.get("R2_RELAY_OVERSIZE_ATTACHMENT_BEHAVIOR", DEFAULT_OVERSIZE_BEHAVIOR),
        )
        values["R2_RELAY_POLL_INTERVAL_MS"] = prompt_value(
            "Poll interval ms",
            existing.get("R2_RELAY_POLL_INTERVAL_MS", "5000"),
        )
        values["R2_RELAY_BACKOFF_MAX_MS"] = prompt_value(
            "Backoff max ms",
            existing.get("R2_RELAY_BACKOFF_MAX_MS", "40000"),
        )
        values["R2_RELAY_ALLOWED_USERS"] = prompt_value(
            "Allowed peer IDs (comma-separated, optional)",
            existing.get("R2_RELAY_ALLOWED_USERS", ""),
        )
        allow_all_default = existing.get("R2_RELAY_ALLOW_ALL_USERS", "false") or "false"
        values["R2_RELAY_ALLOW_ALL_USERS"] = prompt_value("Allow all users? true/false", allow_all_default).lower()

    home_channel = prompt_value(
        "Home target for cron/delivery (peer or peer=...,session=..., optional)",
        existing.get("R2_RELAY_HOME_CHANNEL", ""),
    )
    return values, (home_channel or None)


def validate_values(values: Mapping[str, str]) -> None:
    missing = [key for key in REQUIRED_ENV_VARS if not str(values.get(key, "")).strip()]
    if missing:
        raise ValueError(f"Missing required values: {', '.join(missing)}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Configure the Hermes R2 relay adapter")
    parser.add_argument("--hermes-home", default=str(default_hermes_home()), help="Hermes home directory")
    parser.add_argument("--home-channel", default="", help="Optional home delivery target to write into ~/.hermes/.env")
    parser.add_argument("--write-only", action="store_true", help="Write current env-backed values without prompting")
    args = parser.parse_args(argv)

    hermes_home = Path(args.hermes_home).expanduser()
    env_path = hermes_home / ".env"
    existing = load_env_file(env_path)

    if args.write_only:
        values = {key: existing.get(key, "") for key in ALL_ENV_VARS}
        validate_values(values)
        home_channel = args.home_channel or existing.get("R2_RELAY_HOME_CHANNEL", "")
    else:
        values, prompted_home_channel = collect_wizard_values(existing)
        validate_values(values)
        home_channel = args.home_channel or prompted_home_channel

    apply_r2_relay_settings(
        hermes_home=hermes_home,
        values=values,
        home_channel=home_channel or None,
    )

    print()
    print(f"Saved R2 relay settings to {env_path}")
    if home_channel:
        print(f"Configured r2_relay home target: {home_channel}")
    print("Restart Hermes gateway after deployment if it is already running.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
