#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/org/secret-get.sh <service> <account>

Returns the matching macOS Keychain generic password to stdout.
EOF
}

if [ "$#" -ne 2 ]; then
  usage
  exit 2
fi

service="$1"
account="$2"

if [ -z "$service" ] || [ -z "$account" ]; then
  echo "service and account must be non-empty" >&2
  exit 2
fi

if ! command -v security >/dev/null 2>&1; then
  echo "macOS security command not found" >&2
  exit 127
fi

security find-generic-password -s "$service" -a "$account" -w
