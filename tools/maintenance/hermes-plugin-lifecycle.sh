#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERMES_REPO=${1:?usage: hermes-plugin-lifecycle.sh /path/to/hermes-agent}
BOOTSTRAP_PYTHON=${AGENTDECK_HERMES_PYTHON:-python3}
ARTIFACTS=${AGENTDECK_LIFECYCLE_ARTIFACTS:-$(mktemp -d)}
LIFECYCLE_ROOT=$(mktemp -d)
PLATFORM_VENV="$LIFECYCLE_ROOT/platform-venv"
PLUGIN_SOURCE="$LIFECYCLE_ROOT/r2-relay-source"
export HERMES_HOME="$LIFECYCLE_ROOT/hermes-home"

cleanup() {
  if [[ -z ${AGENTDECK_KEEP_LIFECYCLE_HOME:-} ]]; then
    rm -rf "$LIFECYCLE_ROOT"
  else
    echo "Lifecycle home retained at $LIFECYCLE_ROOT"
  fi
}
trap cleanup EXIT

mkdir -p "$ARTIFACTS" "$HERMES_HOME" "$PLUGIN_SOURCE"
"$BOOTSTRAP_PYTHON" - <<'PY'
import sys
if sys.version_info < (3, 12):
    raise SystemExit("Hermes lifecycle requires Python 3.12 or newer")
PY
"$BOOTSTRAP_PYTHON" -m venv "$PLATFORM_VENV"
HERMES_PYTHON="$PLATFORM_VENV/bin/python"
"$HERMES_PYTHON" -m pip install --disable-pip-version-check 'boto3>=1.34.0' 'PyYAML>=6.0.0' 'rich>=14.0.0' 'python-dotenv>=1.0.0'

copy_candidate() {
  tar \
    --exclude=.venv \
    --exclude=.pytest_cache \
    --exclude=__pycache__ \
    --exclude=dist \
    -C "$REPO_ROOT/integrations/hermes" -cf - . \
    | tar -C "$PLUGIN_SOURCE" -xf -
}

copy_candidate
"$HERMES_PYTHON" - "$PLUGIN_SOURCE/plugin.yaml" <<'PY'
from pathlib import Path
import sys
import yaml

path = Path(sys.argv[1])
manifest = yaml.safe_load(path.read_text(encoding="utf-8"))
manifest["version"] = "0.0.0-lifecycle"
path.write_text(yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8")
PY
git -C "$PLUGIN_SOURCE" init --initial-branch=main
git -C "$PLUGIN_SOURCE" config user.name agentdeck-lifecycle
git -C "$PLUGIN_SOURCE" config user.email agentdeck-lifecycle@example.invalid
git -C "$PLUGIN_SOURCE" add .
git -C "$PLUGIN_SOURCE" commit -m 'previous plugin fixture'

printf '%s\n' \
  'R2_RELAY_ENDPOINT=http://127.0.0.1:9000' \
  'R2_RELAY_BUCKET=lifecycle' \
  'R2_RELAY_ACCESS_KEY_ID=test-access' \
  'R2_RELAY_SECRET_ACCESS_KEY=test-secret' \
  'R2_RELAY_SERVER_ID=lifecycle-hermes' \
  > "$HERMES_HOME/.env"
export R2_RELAY_ENDPOINT=http://127.0.0.1:9000
export R2_RELAY_BUCKET=lifecycle
export R2_RELAY_ACCESS_KEY_ID=test-access
export R2_RELAY_SECRET_ACCESS_KEY=test-secret
export R2_RELAY_SERVER_ID=lifecycle-hermes

PLUGIN_CLI="$LIFECYCLE_ROOT/hermes_plugin_cli.py"
printf '%s\n' \
  'import sys' \
  'from hermes_cli.plugins_cmd import cmd_install, cmd_list, cmd_remove, cmd_update' \
  'action = sys.argv[1]' \
  'if action == "install": cmd_install(sys.argv[2], force=True, enable=True)' \
  'elif action == "update": cmd_update(sys.argv[2])' \
  'elif action == "remove": cmd_remove(sys.argv[2])' \
  'elif action == "list": cmd_list()' \
  'else: raise SystemExit(f"unsupported plugin lifecycle action: {action}")' \
  > "$PLUGIN_CLI"

hermes() {
  if [[ ${1:-} == plugins ]]; then
    shift
  fi
  PYTHONPATH="$HERMES_REPO" "$HERMES_PYTHON" "$PLUGIN_CLI" "$@"
}

hermes plugins install "file://$PLUGIN_SOURCE" --enable
INSTALLED_PLUGIN="$HERMES_HOME/plugins/r2-relay"
[[ -d "$INSTALLED_PLUGIN/.git" ]]
grep -q 'version: 0.0.0-lifecycle' "$INSTALLED_PLUGIN/plugin.yaml"
hermes plugins list > "$ARTIFACTS/hermes-plugins-fresh.txt"

export AGENTDECK_LIFECYCLE_CHECKPOINT="$HERMES_HOME/r2-relay-adapter/checkpoint.json"
"$HERMES_PYTHON" - <<'PY'
import json
import os
from pathlib import Path
import yaml

home = Path(os.environ["HERMES_HOME"])
config_path = home / "config.yaml"
config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
assert "r2-relay" in config["plugins"]["enabled"]
config["agentdeck_lifecycle_marker"] = "preserve-me"
config_path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
checkpoint = Path(os.environ["AGENTDECK_LIFECYCLE_CHECKPOINT"])
checkpoint.parent.mkdir(parents=True, exist_ok=True)
checkpoint.write_text(json.dumps({"last_head_key": "head-before-upgrade", "seen": [], "seen_msg_ids": []}), encoding="utf-8")
PY

copy_candidate
git -C "$PLUGIN_SOURCE" add .
git -C "$PLUGIN_SOURCE" commit -m 'candidate plugin fixture'
hermes plugins update r2-relay
grep -q 'version: 0.1.0' "$INSTALLED_PLUGIN/plugin.yaml"

PYTHONPATH="$HERMES_REPO" "$HERMES_PYTHON" - <<'PY'
import json
import os
from pathlib import Path
import yaml

from hermes_cli.plugins import discover_plugins, get_plugin_manager

home = Path(os.environ["HERMES_HOME"])
config = yaml.safe_load((home / "config.yaml").read_text(encoding="utf-8"))
assert config["agentdeck_lifecycle_marker"] == "preserve-me"
assert "r2-relay" in config["plugins"]["enabled"]
checkpoint = json.loads(Path(os.environ["AGENTDECK_LIFECYCLE_CHECKPOINT"]).read_text(encoding="utf-8"))
assert checkpoint["last_head_key"] == "head-before-upgrade"
discover_plugins(force=True)
manager = get_plugin_manager()
matches = [item for item in manager.list_plugins() if item.get("name") == "r2-relay"]
assert matches and matches[0]["enabled"] and matches[0]["error"] is None, matches
PY

hermes plugins remove r2-relay
[[ ! -d "$INSTALLED_PLUGIN" ]]
[[ -f "$HERMES_HOME/config.yaml" ]]
[[ -f "$AGENTDECK_LIFECYCLE_CHECKPOINT" ]]
hermes plugins install "file://$PLUGIN_SOURCE" --enable
hermes plugins list > "$ARTIFACTS/hermes-plugins-reinstalled.txt"

"$HERMES_PYTHON" - <<'PY' > "$ARTIFACTS/hermes-lifecycle.json"
import json
print(json.dumps({
    "pluginVersion": "0.1.0",
    "phases": ["fresh-install", "upgrade", "config-preservation", "checkpoint-preservation", "uninstall", "reinstall", "platform-discovery"],
}, indent=2))
PY
cat "$ARTIFACTS/hermes-lifecycle.json"
