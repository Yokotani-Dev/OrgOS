#!/usr/bin/env bash
# tests/activity/test-log-event.sh — Central Activity Ledger writer tests.
# Spec: .ai/DESIGN/ACTIVITY_LEDGER.md §4.1 / §7 (1-4)
# bash 3.2 compatible. Never touches the real ~/.orgos.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
LOG="$REPO_ROOT/scripts/activity/log-event.sh"

STORE=$(mktemp -d)
RO_PARENT=$(mktemp -d)
cleanup() {
  chmod -R u+w "$RO_PARENT" 2>/dev/null || true
  rm -rf "$STORE" "$RO_PARENT"
}
trap cleanup EXIT
export ORGOS_ACTIVITY_DIR="$STORE"

fail=0
shard="$STORE/events-$(date -u +%Y%m).jsonl"

# --- 1. basic append: one JSONL line, schema-conformant -----------------------
bash "$LOG" --type note --title "hello ledger" --task-id T-TEST-1 \
  --detail "basic detail" --source cli </dev/null
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: basic append exited $rc (expected 0)"; fail=1
fi
if [ ! -f "$shard" ]; then
  echo "FAIL: shard not created: $shard"; fail=1
else
  lines=$(wc -l < "$shard" | tr -d ' ')
  if [ "$lines" -ne 1 ]; then
    echo "FAIL: expected 1 line in shard, got $lines"; fail=1
  fi
  if ! python3 - "$shard" <<'PY'
import json, re, sys
line = open(sys.argv[1], encoding="utf-8").readlines()[-1]
ev = json.loads(line)
assert ev["schema_version"] == "orgos-activity.v1", ev["schema_version"]
assert re.match(r"^ACT-\d{8}T\d{6}Z-[0-9a-f]{8}$", ev["event_id"]), ev["event_id"]
assert re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", ev["ts"]), ev["ts"]
assert ev["event_type"] == "note"
assert ev["task_id"] == "T-TEST-1"
assert ev["title"] == "hello ledger"
assert ev["detail"] == "basic detail"
assert ev["source"] == "cli"
assert isinstance(ev["repo"], dict)
for k in ("name", "path", "remote"):
    assert k in ev["repo"], "repo.%s missing" % k
assert ev["repo"]["name"], "repo.name empty"
assert isinstance(ev["actor"], dict)
assert ev["actor"]["role"] == "manager"
assert ev["actor"]["id"] == "claude-manager"
for k in ("branch", "session_id", "origin_event_id"):
    assert k in ev, "%s missing" % k
PY
  then
    echo "FAIL: basic event does not conform to orgos-activity.v1"; fail=1
  fi
fi

# --- 2. --stdin-hook extracts session_id from hook JSON ----------------------
echo '{"session_id":"sess-abc-123","hook_event_name":"SessionStart"}' \
  | bash "$LOG" --type session_start --title "session start" --source hook --stdin-hook
if ! python3 - "$shard" <<'PY'
import json, sys
ev = json.loads(open(sys.argv[1], encoding="utf-8").readlines()[-1])
assert ev["event_type"] == "session_start", ev["event_type"]
assert ev["session_id"] == "sess-abc-123", ev["session_id"]
assert ev["source"] == "hook"
PY
then
  echo "FAIL: --stdin-hook did not extract session_id"; fail=1
fi

# --- 3. secret patterns are redacted ------------------------------------------
GHTOKEN="ghp_$(python3 -c 'print("a"*36)')"
bash "$LOG" --type note \
  --title "aws key AKIAABCDEFGHIJKLMNOP leaked" \
  --detail "github $GHTOKEN and sk-abcdefghijklmnopqrstuvwxyz123456" </dev/null
if ! python3 - "$shard" <<'PY'
import json, sys
ev = json.loads(open(sys.argv[1], encoding="utf-8").readlines()[-1])
assert "[REDACTED]" in ev["title"], ev["title"]
assert "AKIA" not in ev["title"], ev["title"]
assert "[REDACTED]" in ev["detail"], ev["detail"]
assert "ghp_" not in ev["detail"], ev["detail"]
assert "sk-abcdef" not in ev["detail"], ev["detail"]
PY
then
  echo "FAIL: secret patterns were not redacted"; fail=1
fi

# --- 4. unwritable store still exits 0 (hook-safe) ----------------------------
chmod 500 "$RO_PARENT"
ORGOS_ACTIVITY_DIR="$RO_PARENT/sub" bash "$LOG" --type note --title "x" </dev/null
rc=$?
chmod 700 "$RO_PARENT"
if [ "$rc" -ne 0 ]; then
  echo "FAIL: unwritable store caused exit $rc (expected 0)"; fail=1
fi

# --- 5. invalid type: exit 0 (hook-safe) and error logged, no event written ---
before=$(wc -l < "$shard" | tr -d ' ')
bash "$LOG" --type bogus_type --title "x" </dev/null
rc=$?
after=$(wc -l < "$shard" | tr -d ' ')
if [ "$rc" -ne 0 ]; then
  echo "FAIL: invalid --type caused exit $rc (expected 0)"; fail=1
fi
if [ "$after" -ne "$before" ]; then
  echo "FAIL: invalid --type appended an event"; fail=1
fi
if [ ! -s "$STORE/errors.log" ]; then
  echo "FAIL: invalid --type did not write errors.log"; fail=1
fi

# --- 6. repos.json upserted ----------------------------------------------------
if ! python3 - "$STORE/repos.json" <<'PY'
import json, sys
repos = json.load(open(sys.argv[1], encoding="utf-8"))
assert isinstance(repos, dict) and repos, "repos.json empty"
entry = list(repos.values())[0]
for k in ("path", "remote", "last_seen"):
    assert k in entry, "repos.json entry missing %s" % k
PY
then
  echo "FAIL: repos.json missing or malformed"; fail=1
fi

# --- 7. title is single-line + capped; detail capped (4KB line guarantee) ------
LONG_TITLE=$(python3 -c 'print("t"*600)')
LONG_DETAIL=$(python3 -c 'print("d"*3000)')
bash "$LOG" --type note --title $'line1\nline2' </dev/null
bash "$LOG" --type note --title "$LONG_TITLE" --detail "$LONG_DETAIL" </dev/null
if ! python3 - "$shard" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
multi = json.loads(lines[-2])
assert multi["title"] == "line1 line2", multi["title"]
long = json.loads(lines[-1])
assert len(long["title"]) <= 500, len(long["title"])
assert long["title"].endswith("…"), long["title"][-5:]
assert len(long["detail"]) <= 2000, len(long["detail"])
assert len(lines[-1].encode("utf-8")) < 4096, "event line exceeds 4KB"
PY
then
  echo "FAIL: title/detail caps or single-line title not enforced"; fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "test-log-event: all assertions passed"
