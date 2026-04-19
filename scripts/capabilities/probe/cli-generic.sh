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

tool="${1:-}"
if [[ -z "$tool" ]]; then
  python3 - <<'PY'
import json

print(json.dumps({
    "id": "cli_generic",
    "status": "unknown",
    "auth_status": "not_required",
    "version": None,
    "path": None,
    "error": "usage: cli-generic.sh <name>",
}))
PY
  exit 0
fi

path="$(command -v "$tool" 2>/dev/null || true)"
status="unavailable"
version=""
auth_status="not_required"

if [[ -n "$path" ]]; then
  status="available"
  version="$(run_cmd "$tool" --version | grep -v '^[Ww][Aa][Rr][Nn][Ii][Nn][Gg]:' | sed '/^$/d' | head -n 1 | tr -d '\r' || true)"
  if [[ -z "$version" ]]; then
    version="$(run_cmd "$tool" -V | grep -v '^[Ww][Aa][Rr][Nn][Ii][Nn][Gg]:' | sed '/^$/d' | head -n 1 | tr -d '\r' || true)"
  fi
  if [[ -z "$version" ]]; then
    version="$(run_cmd "$tool" version | grep -v '^[Ww][Aa][Rr][Nn][Ii][Nn][Gg]:' | sed '/^$/d' | head -n 1 | tr -d '\r' || true)"
  fi
fi

TOOL="$tool" STATUS="$status" AUTH_STATUS="$auth_status" VERSION="$version" PATH_VALUE="$path" python3 - <<'PY'
import json
import os

tool = os.environ["TOOL"]
print(json.dumps({
    "id": f"cli_{tool.replace('-', '_')}",
    "status": os.environ["STATUS"],
    "auth_status": os.environ["AUTH_STATUS"],
    "version": os.environ["VERSION"] or None,
    "path": os.environ["PATH_VALUE"] or None,
}))
PY
