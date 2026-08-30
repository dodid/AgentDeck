#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

diff -u \
  "$repo_root/packages/relay-core/ts/src/types.ts" \
  "$repo_root/integrations/openclaw/src/relay-core/types.ts"
diff -u \
  "$repo_root/packages/relay-core/ts/src/transport.ts" \
  "$repo_root/integrations/openclaw/src/relay-core/transport.ts"
diff -u \
  "$repo_root/packages/relay-core/python/r2_relay_core/types.py" \
  "$repo_root/integrations/hermes/src/r2_relay_adapter/relay_core/types.py"
diff -u \
  "$repo_root/packages/relay-core/python/r2_relay_core/transport.py" \
  "$repo_root/integrations/hermes/src/r2_relay_adapter/relay_core/transport.py"

echo "Vendored relay core copies match their reference implementations."
