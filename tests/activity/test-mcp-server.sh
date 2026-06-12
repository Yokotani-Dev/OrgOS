#!/usr/bin/env bash
# tests/activity/test-mcp-server.sh — MCP server JSON-RPC roundtrip tests.
# Spec: .ai/DESIGN/ACTIVITY_LEDGER.md §4.7 / §7 (9-10)
# bash 3.2 compatible. Never touches the real ~/.orgos.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
SERVER="$REPO_ROOT/scripts/activity/mcp-journal-server.py"

STORE=$(mktemp -d)
trap 'rm -rf "$STORE"' EXIT
export ORGOS_ACTIVITY_DIR="$STORE"
export TZ=UTC

TODAY=$(date -u +%Y-%m-%d)

# Drive a full stdio session: init -> list -> log -> get -> search -> errors.
REQUESTS=$(cat <<EOF
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"activity-test","version":"0.0.1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"activity_log","arguments":{"type":"note","title":"mcp roundtrip note","task_id":"T-MCP-1"}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"journal_get","arguments":{"date":"$TODAY"}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"activity_search","arguments":{"query":"roundtrip"}}}
{"jsonrpc":"2.0","id":6,"method":"no/such/method"}
this is not json
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"no_such_tool","arguments":{}}}
{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"journal_get","arguments":{"date":"bad-date"}}}
EOF
)

OUT_FILE="$STORE/mcp-out.txt"
printf '%s\n' "$REQUESTS" | python3 "$SERVER" > "$OUT_FILE"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: server exited $rc (must not crash)"; exit 1
fi
OUT=$(cat "$OUT_FILE")

if ! python3 - "$OUT_FILE" <<'PY'
import json, sys

resps = {}
parse_errors = 0
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    if msg.get("id") is None:
        if "error" in msg and msg["error"]["code"] == -32700:
            parse_errors += 1
        continue
    resps[msg["id"]] = msg

# 1: initialize
r1 = resps[1]["result"]
assert r1["protocolVersion"], r1
assert r1["serverInfo"]["name"] == "orgos-journal", r1
assert "tools" in r1["capabilities"], r1

# 2: tools/list
names = sorted(t["name"] for t in resps[2]["result"]["tools"])
assert names == ["activity_log", "activity_search", "journal_get"], names
for t in resps[2]["result"]["tools"]:
    assert t["description"]
    assert t["inputSchema"]["type"] == "object"

# 3: activity_log
r3 = resps[3]["result"]
assert r3.get("isError") is False, r3
body = json.loads(r3["content"][0]["text"])
assert body["logged"] is True and body["event_id"].startswith("ACT-"), body

# 4: journal_get digest contains the logged note
text4 = resps[4]["result"]["content"][0]["text"]
assert "OrgOS Journal" in text4, text4
assert "mcp roundtrip note" in text4, text4

# 5: activity_search finds it
body5 = json.loads(resps[5]["result"]["content"][0]["text"])
assert body5["count"] == 1, body5
assert body5["events"][0]["task_id"] == "T-MCP-1", body5

# 6: unknown method -> JSON-RPC error -32601
assert resps[6]["error"]["code"] == -32601, resps[6]

# invalid JSON line -> one -32700 parse error response
assert parse_errors == 1, parse_errors

# 7: unknown tool -> JSON-RPC error -32602
assert resps[7]["error"]["code"] == -32602, resps[7]

# 8: bad tool argument -> tool-level error (isError true), not a crash
r8 = resps[8]["result"]
assert r8.get("isError") is True, r8
assert "error" in r8["content"][0]["text"], r8

print("mcp assertions ok")
PY
then
  echo "FAIL: MCP roundtrip assertions failed"
  printf '%s\n' "$OUT" | head -20
  exit 1
fi

# Store side-effect: the activity_log call must have appended exactly 1 event.
shard="$STORE/events-$(date -u +%Y%m).jsonl"
count=$(wc -l < "$shard" | tr -d ' ')
if [ "$count" -ne 1 ]; then
  echo "FAIL: expected 1 event in store after activity_log, got $count"; exit 1
fi

echo "test-mcp-server: all assertions passed"
