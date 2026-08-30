#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_REPO="${1:-$HOME/.hermes/hermes-agent}"
MODE="${2:-}"
RUN_WIZARD="${R2_RELAY_RUN_WIZARD:-1}"

if [[ ! -d "$HERMES_REPO" ]]; then
  echo "Hermes repo not found: $HERMES_REPO" >&2
  exit 1
fi

if [[ "$MODE" != "--wheel" ]]; then
  MODE="--editable"
fi

"$ROOT/scripts/install-into-hermes.sh" "$HERMES_REPO" "$MODE"

if [[ "$RUN_WIZARD" == "1" ]]; then
  echo
  echo "Launching R2 relay config wizard..."
  "$ROOT/scripts/config-wizard.sh"
fi
