#!/usr/bin/env bash
set -euo pipefail

COMMAND="${1:-install}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/agentdeck"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/agentdeck"
SECRETS_FILE="${AGENTDECK_SECRETS_FILE:-$CONFIG_DIR/staging.env}"
NODE_VERSION="${AGENTDECK_NODE_VERSION:-22.22.3}"
NODE_PLATFORM=""
NODE_HOME=""
OPENCLAW_RUNTIME="$DATA_DIR/openclaw-runtime"
OPENCLAW_STATE="$HOME/.openclaw-agentdeck"
OPENCLAW_PROFILE="agentdeck"
OPENCLAW_PORT="${AGENTDECK_OPENCLAW_PORT:-18791}"
HERMES_RUNTIME="$DATA_DIR/hermes-runtime"
HERMES_HOME="$HOME/.hermes/profiles/agentdeck"

OPENCLAW_SERVICE="openclaw-gateway-agentdeck.service"
HERMES_SERVICE="hermes-gateway-agentdeck.service"

read_compatibility() {
  OPENCLAW_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["openclaw"]["tested_version"])' "$REPO_ROOT/compatibility.json")"
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

install_host_prerequisites() {
  require_command sudo
  require_command apt-get

  local packages=()
  command -v curl >/dev/null 2>&1 || packages+=(curl)
  command -v git >/dev/null 2>&1 || packages+=(git)
  command -v sha256sum >/dev/null 2>&1 || packages+=(coreutils)
  command -v tar >/dev/null 2>&1 || packages+=(tar)
  command -v systemctl >/dev/null 2>&1 || packages+=(systemd)

  if ! command -v python3 >/dev/null 2>&1; then
    packages+=(python3 python3-venv)
  elif ! python3 -c 'import ensurepip, venv' >/dev/null 2>&1; then
    packages+=(python3-venv)
  fi

  if [[ ${#packages[@]} -gt 0 ]]; then
    printf 'Installing missing host prerequisites: %s\n' "${packages[*]}"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
  fi
}

load_secrets() {
  [[ -f "$SECRETS_FILE" ]] || fail "missing $SECRETS_FILE; copy $SCRIPT_DIR/staging.env.example there, fill it in, and chmod 600"
  chmod 600 "$SECRETS_FILE"

  while IFS='=' read -r key value; do
    key="${key%$'\r'}"
    value="${value%$'\r'}"
    [[ -z "$key" || "$key" == \#* ]] && continue
    case "$key" in
      OPENROUTER_API_KEY|R2_RELAY_ENDPOINT|R2_RELAY_BUCKET|R2_RELAY_ACCESS_KEY_ID|R2_RELAY_SECRET_ACCESS_KEY|AGENTDECK_MODEL|OPENCLAW_SERVER_ID|HERMES_SERVER_ID)
        export "$key=$value"
        ;;
    esac
  done < "$SECRETS_FILE"

  : "${OPENROUTER_API_KEY:?set OPENROUTER_API_KEY in $SECRETS_FILE}"
  : "${R2_RELAY_ENDPOINT:?set R2_RELAY_ENDPOINT in $SECRETS_FILE}"
  : "${R2_RELAY_BUCKET:?set R2_RELAY_BUCKET in $SECRETS_FILE}"
  : "${R2_RELAY_ACCESS_KEY_ID:?set R2_RELAY_ACCESS_KEY_ID in $SECRETS_FILE}"
  : "${R2_RELAY_SECRET_ACCESS_KEY:?set R2_RELAY_SECRET_ACCESS_KEY in $SECRETS_FILE}"

  AGENTDECK_MODEL="${AGENTDECK_MODEL:-openrouter/auto}"
  OPENCLAW_SERVER_ID="${OPENCLAW_SERVER_ID:-agentdeck-openclaw}"
  HERMES_SERVER_ID="${HERMES_SERVER_ID:-agentdeck-hermes}"
  export AGENTDECK_MODEL OPENCLAW_SERVER_ID HERMES_SERVER_ID
}

check_host() {
  [[ "$(uname -s)" == "Linux" ]] || fail "this script supports Linux only"
  case "$(uname -m)" in
    x86_64) NODE_PLATFORM="linux-x64" ;;
    aarch64|arm64) NODE_PLATFORM="linux-arm64" ;;
    *) fail "unsupported Linux architecture: $(uname -m)" ;;
  esac
  NODE_HOME="$DATA_DIR/node-v${NODE_VERSION}-${NODE_PLATFORM}"
  install_host_prerequisites
  require_command curl
  require_command git
  require_command python3
  require_command sha256sum
  require_command systemctl
  require_command tar
  python3 -c 'import ensurepip, venv' || fail "Python venv support is required"
  systemctl --user show-environment >/dev/null 2>&1 || fail "systemd --user is unavailable; enable linger for $USER and log in again"
}

install_node() {
  if [[ -x "$NODE_HOME/bin/node" && "$("$NODE_HOME"/bin/node --version)" == "v$NODE_VERSION" ]]; then
    return
  fi
  [[ ! -e "$NODE_HOME" ]] || fail "$NODE_HOME exists but is not Node v$NODE_VERSION; move it aside and rerun"

  local archive="node-v${NODE_VERSION}-${NODE_PLATFORM}.tar.xz"
  local temp_dir
  temp_dir="$(mktemp -d)"
  (
    cd "$temp_dir"
    curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${archive}"
    curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt"
    grep " ${archive}$" SHASUMS256.txt | sha256sum -c -
    mkdir -p "$DATA_DIR"
    tar -xJf "$archive" -C "$DATA_DIR"
  )
  rm -rf "$temp_dir"
}

remove_openclaw() {
  local openclaw="$OPENCLAW_RUNTIME/node_modules/.bin/openclaw"
  if [[ -x "$openclaw" ]]; then
    "$openclaw" --profile "$OPENCLAW_PROFILE" gateway stop || true
    "$openclaw" --profile "$OPENCLAW_PROFILE" gateway uninstall || true
    if "$openclaw" --profile "$OPENCLAW_PROFILE" plugins inspect r2-relay-channel >/dev/null 2>&1; then
      "$openclaw" --profile "$OPENCLAW_PROFILE" plugins uninstall r2-relay-channel --force
    fi
  fi
  rm -rf "$OPENCLAW_RUNTIME"
}

write_openclaw_files() {
  mkdir -p "$OPENCLAW_STATE"
  chmod 700 "$OPENCLAW_STATE"
  printf 'OPENROUTER_API_KEY=%s\n' "$OPENROUTER_API_KEY" > "$OPENCLAW_STATE/.env"
  chmod 600 "$OPENCLAW_STATE/.env"

  export OPENCLAW_RELAY_CONFIG="$OPENCLAW_STATE/r2relay.config.json"
  python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["OPENCLAW_RELAY_CONFIG"])
payload = {
    "enabled": True,
    "endpoint": os.environ["R2_RELAY_ENDPOINT"].rstrip("/"),
    "bucket": os.environ["R2_RELAY_BUCKET"],
    "accessKeyId": os.environ["R2_RELAY_ACCESS_KEY_ID"],
    "secretAccessKey": os.environ["R2_RELAY_SECRET_ACCESS_KEY"],
    "serverId": os.environ["OPENCLAW_SERVER_ID"],
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
path.chmod(0o600)
PY
}

install_openclaw() {
  local node="$NODE_HOME/bin/node"
  local npm="$NODE_HOME/bin/npm"
  local openclaw="$OPENCLAW_RUNTIME/node_modules/.bin/openclaw"
  export PATH="$NODE_HOME/bin:$PATH"

  remove_openclaw
  mkdir -p "$OPENCLAW_RUNTIME"
  "$npm" install --no-audit --no-fund --prefix "$OPENCLAW_RUNTIME" "openclaw@$OPENCLAW_VERSION"
  write_openclaw_files

  "$openclaw" --profile "$OPENCLAW_PROFILE" plugins install clawhub:r2-relay-channel
  "$openclaw" --profile "$OPENCLAW_PROFILE" plugins enable r2-relay-channel
  "$openclaw" --profile "$OPENCLAW_PROFILE" plugins inspect r2-relay-channel >/dev/null
  "$openclaw" --profile "$OPENCLAW_PROFILE" config set gateway.mode local
  "$openclaw" --profile "$OPENCLAW_PROFILE" config set gateway.port "$OPENCLAW_PORT" --strict-json
  "$openclaw" --profile "$OPENCLAW_PROFILE" config set channels.r2-relay-channel "{\"enabled\":true,\"configFile\":\"$OPENCLAW_STATE/r2relay.config.json\"}" --strict-json
  "$openclaw" --profile "$OPENCLAW_PROFILE" config validate

  local model="$AGENTDECK_MODEL"
  [[ "$model" == openrouter/* ]] || model="openrouter/$model"
  OPENROUTER_API_KEY="$OPENROUTER_API_KEY" "$openclaw" --profile "$OPENCLAW_PROFILE" models set "$model"
  "$openclaw" --profile "$OPENCLAW_PROFILE" gateway install --force --port "$OPENCLAW_PORT"

  # gateway install starts the service. A second restart here can race its
  # first-run migrations and leave the profile temporarily locked.

  "$node" --version >/dev/null
}

write_hermes_env() {
  mkdir -p "$HERMES_HOME"
  chmod 700 "$HERMES_HOME"
  {
    printf 'PATH=%s\n' "$PATH"
    printf 'OPENROUTER_API_KEY=%s\n' "$OPENROUTER_API_KEY"
    printf 'R2_RELAY_ENDPOINT=%s\n' "$R2_RELAY_ENDPOINT"
    printf 'R2_RELAY_BUCKET=%s\n' "$R2_RELAY_BUCKET"
    printf 'R2_RELAY_ACCESS_KEY_ID=%s\n' "$R2_RELAY_ACCESS_KEY_ID"
    printf 'R2_RELAY_SECRET_ACCESS_KEY=%s\n' "$R2_RELAY_SECRET_ACCESS_KEY"
    printf 'R2_RELAY_SERVER_ID=%s\n' "$HERMES_SERVER_ID"
    printf 'R2_RELAY_DISPLAY_NAME=Hermes on AgentDeck staging\n'
    printf 'R2_RELAY_MODELS=%s|%s|openrouter\n' "$AGENTDECK_MODEL" "$AGENTDECK_MODEL"
    printf 'R2_RELAY_DEFAULT_MODEL=%s\n' "$AGENTDECK_MODEL"
  } > "$HERMES_HOME/.env"
  chmod 600 "$HERMES_HOME/.env"
}

install_hermes() {
  if [[ -x "$HERMES_RUNTIME/venv/bin/hermes" ]]; then
    HERMES_HOME="$HERMES_HOME" "$HERMES_RUNTIME/venv/bin/hermes" gateway stop || true
    HERMES_HOME="$HERMES_HOME" "$HERMES_RUNTIME/venv/bin/hermes" gateway uninstall || true
    HERMES_HOME="$HERMES_HOME" "$HERMES_RUNTIME/venv/bin/hermes" plugins remove r2-relay || true
  fi
  rm -rf "$HERMES_RUNTIME"
  mkdir -p "$HERMES_RUNTIME"
  python3 -m venv "$HERMES_RUNTIME/venv"
  "$HERMES_RUNTIME/venv/bin/python" -m pip install --disable-pip-version-check --upgrade pip wheel
  "$HERMES_RUNTIME/venv/bin/python" -m pip install --disable-pip-version-check --upgrade hermes-agent
  "$HERMES_RUNTIME/venv/bin/python" -m pip install --upgrade r2-relay-adapter

  export PATH="$HERMES_RUNTIME/venv/bin:$NODE_HOME/bin:$OPENCLAW_RUNTIME/node_modules/.bin:$PATH"
  export HERMES_HOME
  write_hermes_env

  local hermes="$HERMES_RUNTIME/venv/bin/hermes"
  # Keep staging installs noninteractive and do not grant built-in tool override.
  HERMES_HOME="$HERMES_HOME" "$hermes" plugins enable r2-relay --no-allow-tool-override
  HERMES_HOME="$HERMES_HOME" "$hermes" plugins list | grep -q 'r2-relay'
  HERMES_HOME="$HERMES_HOME" "$hermes" config set model.provider openrouter
  HERMES_HOME="$HERMES_HOME" "$hermes" config set model.default "$AGENTDECK_MODEL"
  HERMES_HOME="$HERMES_HOME" "$hermes" gateway install --force
  HERMES_HOME="$HERMES_HOME" "$hermes" gateway restart
}

service_action() {
  local action="$1"
  systemctl --user "$action" "$OPENCLAW_SERVICE" "$HERMES_SERVICE"
}

show_status() {
  systemctl --user --no-pager --full status "$OPENCLAW_SERVICE" "$HERMES_SERVICE" || true
}

verify_relay() {
  load_secrets
  [[ -x "$HERMES_RUNTIME/venv/bin/python" ]] || fail "Hermes is not installed; run install first"
  "$HERMES_RUNTIME/venv/bin/python" - <<'PY'
import os
import boto3
from botocore.config import Config

client = boto3.client(
    "s3",
    endpoint_url=os.environ["R2_RELAY_ENDPOINT"],
    aws_access_key_id=os.environ["R2_RELAY_ACCESS_KEY_ID"],
    aws_secret_access_key=os.environ["R2_RELAY_SECRET_ACCESS_KEY"],
    region_name="auto",
    config=Config(s3={"addressing_style": "path"}),
)
response = client.list_objects_v2(Bucket=os.environ["R2_RELAY_BUCKET"], Prefix="identity/")
keys = sorted(item["Key"] for item in response.get("Contents", []))
if not keys:
    raise SystemExit("No relay identity documents found. Check service logs.")
print("Relay identities:")
for key in keys:
    print(f"  {key}")
PY
}

case "$COMMAND" in
  install)
    check_host
    read_compatibility
    load_secrets
    mkdir -p "$DATA_DIR"
    install_node
    install_openclaw
    install_hermes
    show_status
    printf '\nSetup complete. Wait a few seconds, then run: %s verify\n' "$0"
    ;;
  start|stop|restart)
    service_action "$COMMAND"
    show_status
    ;;
  status)
    show_status
    ;;
  logs)
    exec journalctl --user -u "$OPENCLAW_SERVICE" -u "$HERMES_SERVICE" -n 200 -f
    ;;
  verify)
    verify_relay
    ;;
  *)
    fail "usage: $0 {install|start|stop|restart|status|logs|verify}"
    ;;
esac
