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

path="$(command -v gh 2>/dev/null || true)"
status="unavailable"
auth_status="unknown"
version=""

if [[ -n "$path" ]]; then
  status="available"
  version="$(run_cmd gh --version | head -n 1 | tr -d '\r' || true)"
  auth_output="$(run_cmd gh auth status)"
  if printf '%s' "$auth_output" | grep -qi "Logged in to"; then
    auth_status="verified"
  elif printf '%s' "$auth_output" | grep -qiE "token .* invalid|expired"; then
    auth_status="expired"
  elif printf '%s' "$auth_output" | grep -qi "not logged into any"; then
    auth_status="unverified"
  else
    auth_status="unknown"
  fi
fi

STATUS="$status" AUTH_STATUS="$auth_status" VERSION="$version" PATH_VALUE="$path" python3 - <<'PY'
import json
import os

print(json.dumps({
    "id": "cli_gh",
    "status": os.environ["STATUS"],
    "auth_status": os.environ["AUTH_STATUS"],
    "version": os.environ["VERSION"] or None,
    "path": os.environ["PATH_VALUE"] or None,
}))
PY
