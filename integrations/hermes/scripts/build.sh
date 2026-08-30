#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v uv >/dev/null 2>&1; then
  uv build
elif [[ -x .venv/bin/python ]]; then
  .venv/bin/python -m build
else
  python3 -m build
fi
