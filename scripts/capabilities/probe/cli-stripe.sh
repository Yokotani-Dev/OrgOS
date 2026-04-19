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

path="$(command -v stripe 2>/dev/null || true)"
status="unavailable"
auth_status="unknown"
version=""

if [[ -n "$path" ]]; then
  status="available"
  version="$(run_cmd stripe --version | head -n 1 | tr -d '\r' || true)"
  config_output="$(run_cmd stripe config --list)"
  if printf '%s' "$config_output" | grep -qiE "test_mode_api_key|live_mode_api_key|device_name"; then
    auth_status="verified"
  elif printf '%s' "$config_output" | grep -qiE "not logged in|No configuration|No profile"; then
    auth_status="unverified"
  elif [[ -n "$config_output" ]]; then
    auth_status="unknown"
  fi
fi

STATUS="$status" AUTH_STATUS="$auth_status" VERSION="$version" PATH_VALUE="$path" python3 - <<'PY'
import json
import os

print(json.dumps({
    "id": "cli_stripe",
    "status": os.environ["STATUS"],
    "auth_status": os.environ["AUTH_STATUS"],
    "version": os.environ["VERSION"] or None,
    "path": os.environ["PATH_VALUE"] or None,
}))
PY
