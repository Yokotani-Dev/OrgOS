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

path="$(command -v aws 2>/dev/null || true)"
status="unavailable"
auth_status="unknown"
version=""
error_detail=""

if [[ -n "$path" ]]; then
  status="available"
  version="$(run_cmd aws --version | head -n 1 | tr -d '\r' || true)"
  identity_output="$(run_cmd aws sts get-caller-identity)"
  if printf '%s' "$identity_output" | grep -qiE "\"Account\"|\"Arn\""; then
    auth_status="verified"
  elif printf '%s' "$identity_output" | grep -qiE "ENOTFOUND|timeout|timed out|Could not connect to the endpoint URL|endpoint URL|Name or service not known|Temporary failure in name resolution|Connection refused|network"; then
    status="degraded"
    auth_status="probe_error"
    error_detail="network_error"
  elif printf '%s' "$identity_output" | grep -qiE "Unable to locate credentials|ExpiredToken|AccessDenied|InvalidClientTokenId|could not be found"; then
    auth_status="unverified"
  elif [[ -n "$identity_output" ]]; then
    auth_status="unknown"
  fi
fi

STATUS="$status" AUTH_STATUS="$auth_status" VERSION="$version" PATH_VALUE="$path" ERROR_DETAIL="$error_detail" python3 - <<'PY'
import json
import os

payload = {
    "id": "cli_aws",
    "status": os.environ["STATUS"],
    "auth_status": os.environ["AUTH_STATUS"],
    "version": os.environ["VERSION"] or None,
    "path": os.environ["PATH_VALUE"] or None,
}
if os.environ["ERROR_DETAIL"]:
    payload["error_detail"] = os.environ["ERROR_DETAIL"]
print(json.dumps(payload))
PY
