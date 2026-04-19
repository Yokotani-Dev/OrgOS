#!/usr/bin/env bash
set -euo pipefail

path="$(command -v git 2>/dev/null || true)"
status="unavailable"
version=""

if [[ -n "$path" ]]; then
  status="available"
  version="$(git --version 2>&1 | head -n 1 | tr -d '\r' || true)"
fi

STATUS="$status" VERSION="$version" PATH_VALUE="$path" python3 - <<'PY'
import json
import os

print(json.dumps({
    "id": "cli_git",
    "status": os.environ["STATUS"],
    "auth_status": "not_required",
    "version": os.environ["VERSION"] or None,
    "path": os.environ["PATH_VALUE"] or None,
}))
PY
