#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/org/secret-set.sh <service> <account> [--read-stdin | --prompt]

Stores or updates a macOS Keychain generic password.
EOF
}

if [ "$#" -ne 3 ]; then
  usage
  exit 2
fi

service="$1"
account="$2"
mode="$3"

if [ -z "$service" ] || [ -z "$account" ]; then
  echo "service and account must be non-empty" >&2
  exit 2
fi

if ! command -v security >/dev/null 2>&1; then
  echo "macOS security command not found" >&2
  exit 127
fi

case "$mode" in
  --read-stdin)
    secret=$(cat)
    ;;
  --prompt)
    if [ ! -t 0 ]; then
      echo "--prompt requires an interactive terminal" >&2
      exit 2
    fi
    printf 'Secret for %s/%s: ' "$service" "$account" >&2
    IFS= read -r -s secret
    printf '\n' >&2
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "unknown mode: $mode" >&2
    usage
    exit 2
    ;;
esac

if [ -z "$secret" ]; then
  echo "secret must be non-empty" >&2
  exit 2
fi

security add-generic-password -s "$service" -a "$account" -w "$secret" -U
