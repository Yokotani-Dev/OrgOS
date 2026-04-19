#!/usr/bin/env bash
set -euo pipefail

run_cmd() {
  python3 - "$@" <<'PY'
import subprocess
import sys

cmd = sys.argv[1:]
try:
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    text = (result.stdout or "") + (result.stderr or "")
    print(text.strip())
except Exception:
    pass
PY
}

path="$(command -v codex 2>/dev/null || true)"
status="unavailable"
version=""

if [[ -n "$path" ]]; then
  status="available"
  version="$(run_cmd codex --version | grep -v '^[Ww][Aa][Rr][Nn][Ii][Nn][Gg]:' | sed '/^$/d' | head -n 1 | tr -d '\r' || true)"
fi

STATUS="$status" VERSION="$version" PATH_VALUE="$path" python3 - <<'PY'
import json
import os

print(json.dumps({
    "id": "cli_codex",
    "status": os.environ["STATUS"],
    "auth_status": "not_required",
    "version": os.environ["VERSION"] or None,
    "path": os.environ["PATH_VALUE"] or None,
}))
PY
