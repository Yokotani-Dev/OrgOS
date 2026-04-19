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

path="$(command -v supabase 2>/dev/null || true)"
status="unavailable"
auth_status="unknown"
version=""

if [[ -n "$path" ]]; then
  status="available"
  version="$(run_cmd supabase --version | head -n 1 | tr -d '\r' || true)"
  auth_output="$(run_cmd supabase projects list)"
  if printf '%s' "$auth_output" | grep -qiE "Access token not provided|not logged in|Authentication required|Unauthorized"; then
    auth_status="unverified"
  elif printf '%s' "$auth_output" | grep -qiE "LINKED|No projects found|project"; then
    auth_status="verified"
  elif [[ -n "$auth_output" ]]; then
    auth_status="unknown"
  fi
fi

STATUS="$status" AUTH_STATUS="$auth_status" VERSION="$version" PATH_VALUE="$path" python3 - <<'PY'
import json
import os

print(json.dumps({
    "id": "cli_supabase",
    "status": os.environ["STATUS"],
    "auth_status": os.environ["AUTH_STATUS"],
    "version": os.environ["VERSION"] or None,
    "path": os.environ["PATH_VALUE"] or None,
}))
PY
