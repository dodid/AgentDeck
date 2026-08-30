#!/usr/bin/env bash
set -euo pipefail
HERMES_REPO="${1:-$HOME/.hermes/hermes-agent}"
VENV_PY="$HERMES_REPO/venv/bin/python"
HERMES_HOME="${HERMES_HOME:-$(cd "$HERMES_REPO/.." && pwd)}"
PLUGIN_NAME="r2-relay"
PLUGIN_DIR="$HERMES_HOME/plugins/$PLUGIN_NAME"
if [[ -x "$VENV_PY" ]]; then
  "$VENV_PY" -m ensurepip --upgrade >/dev/null
  "$VENV_PY" -m pip uninstall -y r2-relay-adapter || true
fi
if [[ -d "$PLUGIN_DIR" ]]; then
  rm -rf "$PLUGIN_DIR"
  echo "Removed user plugin directory $PLUGIN_DIR"
fi
export HERMES_HOME PLUGIN_NAME
if [[ -x "$VENV_PY" ]]; then
  "$VENV_PY" - <<'PY'
import os
from pathlib import Path
import yaml

hermes_home = Path(os.environ["HERMES_HOME"])
plugin_name = os.environ["PLUGIN_NAME"]
config_path = hermes_home / "config.yaml"
if not config_path.exists():
    raise SystemExit(0)

loaded = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
if not isinstance(loaded, dict):
    raise SystemExit(0)

plugins = loaded.get("plugins")
if not isinstance(plugins, dict):
    raise SystemExit(0)

changed = False
for key in ("enabled", "disabled"):
    values = plugins.get(key)
    if isinstance(values, list) and plugin_name in values:
        plugins[key] = [name for name in values if name != plugin_name]
        changed = True

if changed:
    config_path.write_text(yaml.safe_dump(loaded, sort_keys=False), encoding="utf-8")
PY
fi
echo "Package removed. Clean up ~/.hermes/.env values manually if you no longer want the R2 relay enabled."
