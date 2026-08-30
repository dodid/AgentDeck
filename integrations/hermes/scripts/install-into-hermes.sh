#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_REPO="${1:-$HOME/.hermes/hermes-agent}"
MODE="${2:-}"
VENV_PY="$HERMES_REPO/venv/bin/python"
HERMES_HOME="${HERMES_HOME:-$(cd "$HERMES_REPO/.." && pwd)}"
PLUGIN_NAME="r2-relay"
PLUGIN_SRC_DIR="$ROOT/hermes-plugin/r2_relay"
PLUGIN_DEST_DIR="$HERMES_HOME/plugins/$PLUGIN_NAME"
if [[ ! -x "$VENV_PY" ]]; then
  echo "Hermes venv python not found: $VENV_PY" >&2
  exit 1
fi
"$VENV_PY" -m ensurepip --upgrade >/dev/null
if [[ "$MODE" == "--editable" ]]; then
  "$VENV_PY" -m pip install --no-deps -e "$ROOT"
else
  "$ROOT/scripts/build.sh"
  "$VENV_PY" -m pip install --no-deps --upgrade "$ROOT"/dist/r2_relay_adapter-*.whl
fi
"$VENV_PY" -m pip install --upgrade \
  boto3 \
  httpx \
  PyYAML
mkdir -p "$PLUGIN_DEST_DIR"
cp "$PLUGIN_SRC_DIR/"* "$PLUGIN_DEST_DIR/"
export HERMES_HOME PLUGIN_NAME
"$VENV_PY" - <<'PY'
import os
from pathlib import Path
import yaml

hermes_home = Path(os.environ["HERMES_HOME"])
plugin_name = os.environ["PLUGIN_NAME"]
config_path = hermes_home / "config.yaml"
config = {}
if config_path.exists():
    loaded = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    if isinstance(loaded, dict):
        config = loaded

plugins = config.setdefault("plugins", {})
if not isinstance(plugins, dict):
    plugins = {}
    config["plugins"] = plugins

enabled = plugins.setdefault("enabled", [])
if not isinstance(enabled, list):
    enabled = []
    plugins["enabled"] = enabled
if plugin_name not in enabled:
    enabled.append(plugin_name)

disabled = plugins.get("disabled", [])
if isinstance(disabled, list) and plugin_name in disabled:
    plugins["disabled"] = [name for name in disabled if name != plugin_name]

config_path.parent.mkdir(parents=True, exist_ok=True)
config_path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
PY
"$ROOT/scripts/verify-hermes-install.sh" "$HERMES_REPO"
echo "Installed r2-relay-adapter into $HERMES_REPO"
echo "Hermes user plugin installed at $PLUGIN_DEST_DIR"
echo "Enabled plugin '$PLUGIN_NAME' in $HERMES_HOME/config.yaml"
echo "Run ./scripts/config-wizard.sh if you still need to populate ~/.hermes/.env"
