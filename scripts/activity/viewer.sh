#!/usr/bin/env bash
# OrgOS Activity Ledger viewer launcher.
# Resolves the server relative to this script so it works from anywhere in the repo.
# Usage: scripts/activity/viewer.sh [--port 7777] [--no-browser]
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER="$SCRIPT_DIR/viewer/server.py"

if [ ! -f "$SERVER" ]; then
  echo "error: server not found at $SERVER" >&2
  exit 1
fi

exec python3 "$SERVER" "$@"
