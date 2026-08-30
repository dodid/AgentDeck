#!/usr/bin/env bash
set -euo pipefail
HERMES_REPO="${1:-$HOME/.hermes/hermes-agent}"
PY="$HERMES_REPO/venv/bin/python"
HERMES_HOME="${HERMES_HOME:-$(cd "$HERMES_REPO/.." && pwd)}"
export HERMES_REPO
export HERMES_HOME
if [[ ! -x "$PY" ]]; then
  echo "Hermes venv python not found: $PY" >&2
  exit 1
fi
"$PY" - <<'PY'
import r2_relay_adapter
from gateway.config import Platform, load_gateway_config
from hermes_cli.plugins import discover_plugins
from gateway.platform_registry import platform_registry
import os
from pathlib import Path

print('r2_relay_adapter import ok:', getattr(r2_relay_adapter, '__version__', 'unknown'))
discover_plugins()
platform = Platform('r2_relay')
entry = platform_registry.get('r2_relay')
config = load_gateway_config()
plugin_dir = Path(os.environ['HERMES_HOME']) / 'plugins' / 'r2-relay'
print('plugin dir exists:', plugin_dir.exists())
print('platform registry has r2_relay:', entry is not None)
print('config entry enabled:', bool(config.platforms.get(platform) and config.platforms[platform].enabled))
print('connected platforms includes r2_relay:', platform in config.get_connected_platforms())
PY
