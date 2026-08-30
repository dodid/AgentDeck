#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

forbidden_pattern='(^|/)(\.env($|\.)|[^/]+\.(p8|p12|mobileprovision|cer|key|pem)$|r2relay\.(local|config)\.json$|xcuserdata(/|$)|[^/]+\.xcuserstate$)'

if git ls-files | grep -E "$forbidden_pattern"; then
  echo "Refusing to continue: a credential-bearing or machine-local file is tracked." >&2
  exit 1
fi

if git grep -nE '"(secretAccessKey|secret_access_key)"[[:space:]]*:[[:space:]]*"[^"$<{]*(.{20,})"' -- ':!tools/ci/check-no-sensitive-files.sh'; then
  echo "Refusing to continue: a literal secret access key may be tracked." >&2
  exit 1
fi

echo "No forbidden credential or machine-local files are tracked."
