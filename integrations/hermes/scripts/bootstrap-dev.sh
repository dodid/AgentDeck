#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v uv >/dev/null 2>&1; then
  uv venv --seed --clear .venv
  uv pip install --python .venv/bin/python -e '.[dev]'
else
  rm -rf .venv
  python3 -m venv .venv
  source .venv/bin/activate
  python -m pip install --upgrade pip setuptools wheel
  python -m pip install -e '.[dev]'
fi
echo "Bootstrapped dev environment in $(pwd)/.venv"
