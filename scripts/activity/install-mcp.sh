#!/bin/bash
# scripts/activity/install-mcp.sh — register the orgos-journal MCP server
# at user scope so every repository / project can use it.
#
# Usage: bash scripts/activity/install-mcp.sh
# Self-contained: bash 3.2 only. Requires the `claude` CLI.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SERVER="$SCRIPT_DIR/mcp-journal-server.py"

if [ ! -f "$SERVER" ]; then
  echo "install-mcp.sh: server not found: $SERVER" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "install-mcp.sh: python3 not found" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "install-mcp.sh: claude CLI not found (install Claude Code first)" >&2
  exit 1
fi

# Re-register idempotently (remove may fail if not registered yet — that's fine).
claude mcp remove --scope user orgos-journal >/dev/null 2>&1 || true

if claude mcp add --scope user orgos-journal -- python3 "$SERVER"; then
  echo "install-mcp.sh: registered MCP server 'orgos-journal' (user scope)"
  echo "  tools: journal_get / activity_search / activity_log"
  echo "  store: \${ORGOS_ACTIVITY_DIR:-~/.orgos/activity}"
else
  echo "install-mcp.sh: claude mcp add failed" >&2
  exit 1
fi
