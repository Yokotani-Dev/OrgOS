#!/usr/bin/env bash
# tests/activity/test-bridge.sh — kernel event bridge tests.
# Spec: .ai/DESIGN/ACTIVITY_LEDGER.md §4.3 / §7 (6)
# bash 3.2 compatible. Never touches the real ~/.orgos.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
BRIDGE="$REPO_ROOT/scripts/activity/bridge-kernel-events.sh"

STORE=$(mktemp -d)
FAKE_REPO=$(mktemp -d)
trap 'rm -rf "$STORE" "$FAKE_REPO"' EXIT
export ORGOS_ACTIVITY_DIR="$STORE"

fail=0

# Build a fake repo with kernel events (orgos-event.v1).
git -C "$FAKE_REPO" init -q
mkdir -p "$FAKE_REPO/.ai/events"
cat > "$FAKE_REPO/.ai/events/events-202606.jsonl" <<'EOF'
{"actor":{"id":"claude-manager","role":"manager"},"event_id":"EVT-20260610T100000Z-T-K-1-aaaa1111","event_type":"TaskCreated","hash":"h1","payload":{"source":"owner_request"},"prev_hash":"0","schema_version":"orgos-event.v1","task_id":"T-K-1","ts":"2026-06-10T10:00:00Z"}
{"actor":{"id":"integrator.sh","role":"system"},"event_id":"EVT-20260610T110000Z-T-K-2-bbbb2222","event_type":"TaskDone","hash":"h2","payload":{"run_id":"r-1","artifact_count":3},"prev_hash":"h1","schema_version":"orgos-event.v1","task_id":"T-K-2","ts":"2026-06-10T11:00:00Z"}
EOF

shard="$STORE/events-202606.jsonl"

# --- 1. first run imports both events -------------------------------------------
( cd "$FAKE_REPO" && bash "$BRIDGE" )
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: bridge exited $rc (expected 0)"; fail=1
fi
if [ ! -f "$shard" ]; then
  echo "FAIL: central shard not created"; fail=1
  exit 1
fi
count=$(wc -l < "$shard" | tr -d ' ')
if [ "$count" -ne 2 ]; then
  echo "FAIL: expected 2 bridged events, got $count"; fail=1
fi
if ! python3 - "$shard" <<'PY'
import json, sys
events = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
by_origin = {}
for ev in events:
    assert ev["schema_version"] == "orgos-activity.v1"
    assert ev["event_type"] == "kernel", ev["event_type"]
    assert ev["source"] == "kernel-bridge", ev["source"]
    assert ev["origin_event_id"].startswith("EVT-"), ev["origin_event_id"]
    by_origin[ev["origin_event_id"]] = ev
ev1 = by_origin["EVT-20260610T100000Z-T-K-1-aaaa1111"]
assert ev1["task_id"] == "T-K-1"
assert ev1["ts"] == "2026-06-10T10:00:00Z"
assert "TaskCreated" in ev1["title"], ev1["title"]
assert "source=owner_request" in ev1["detail"], ev1["detail"]
ev2 = by_origin["EVT-20260610T110000Z-T-K-2-bbbb2222"]
assert "TaskDone" in ev2["title"]
PY
then
  echo "FAIL: bridged events malformed"; fail=1
fi

# --- 2. idempotency: second run adds nothing ------------------------------------
( cd "$FAKE_REPO" && bash "$BRIDGE" )
count=$(wc -l < "$shard" | tr -d ' ')
if [ "$count" -ne 2 ]; then
  echo "FAIL: second run duplicated events (got $count lines)"; fail=1
fi

# --- 3. incremental: new kernel event gets picked up, no duplicates --------------
cat >> "$FAKE_REPO/.ai/events/events-202606.jsonl" <<'EOF'
{"actor":{"id":"claude-manager","role":"manager"},"event_id":"EVT-20260610T120000Z-T-K-3-cccc3333","event_type":"TickCompleted","hash":"h3","payload":{},"prev_hash":"h2","schema_version":"orgos-event.v1","task_id":"T-K-3","ts":"2026-06-10T12:00:00Z"}
EOF
( cd "$FAKE_REPO" && bash "$BRIDGE" )
count=$(wc -l < "$shard" | tr -d ' ')
if [ "$count" -ne 3 ]; then
  echo "FAIL: incremental run expected 3 total, got $count"; fail=1
fi
dupes=$(python3 - "$shard" <<'PY'
import json, sys
origins = [json.loads(l)["origin_event_id"]
           for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
print(len(origins) - len(set(origins)))
PY
)
if [ "$dupes" -ne 0 ]; then
  echo "FAIL: $dupes duplicate origin_event_id(s) after incremental run"; fail=1
fi

# --- 4. secret-bearing kernel payloads are redacted before central write ---------
GHTOKEN="ghp_$(python3 -c 'print("a"*36)')"
cat >> "$FAKE_REPO/.ai/events/events-202606.jsonl" <<EOF
{"actor":{"id":"claude-manager","role":"manager"},"event_id":"EVT-20260610T130000Z-T-K-4-dddd4444","event_type":"Error AKIAABCDEFGHIJKLMNOP","hash":"h4","payload":{"message":"leak $GHTOKEN here"},"prev_hash":"h3","schema_version":"orgos-event.v1","task_id":"T-K-4","ts":"2026-06-10T13:00:00Z"}
EOF
( cd "$FAKE_REPO" && bash "$BRIDGE" )
count=$(wc -l < "$shard" | tr -d ' ')
if [ "$count" -ne 4 ]; then
  echo "FAIL: redaction run expected 4 total, got $count"; fail=1
fi
if ! python3 - "$shard" <<'PY'
import json, sys
events = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
ev = [e for e in events
      if e["origin_event_id"] == "EVT-20260610T130000Z-T-K-4-dddd4444"][0]
assert "[REDACTED]" in ev["title"], ev["title"]
assert "AKIA" not in ev["title"], ev["title"]
assert "[REDACTED]" in ev["detail"], ev["detail"]
assert "ghp_" not in ev["detail"], ev["detail"]
PY
then
  echo "FAIL: bridge did not redact secret-bearing kernel payload"; fail=1
fi

# --- 5. cursor reset (source rotated/shrank) does not re-import duplicates -------
# Rewrite the source with fewer lines (2 old events + 1 brand-new one); the
# stored cursor (4 lines) is now beyond EOF -> reset path. origin_event_id
# must act as the dedup key: old events skipped, only the new one imported.
head -2 "$FAKE_REPO/.ai/events/events-202606.jsonl" > "$FAKE_REPO/.ai/events/events-202606.jsonl.tmp"
cat >> "$FAKE_REPO/.ai/events/events-202606.jsonl.tmp" <<'EOF'
{"actor":{"id":"claude-manager","role":"manager"},"event_id":"EVT-20260610T140000Z-T-K-5-eeee5555","event_type":"TaskCreated","hash":"h5","payload":{},"prev_hash":"h4","schema_version":"orgos-event.v1","task_id":"T-K-5","ts":"2026-06-10T14:00:00Z"}
EOF
mv "$FAKE_REPO/.ai/events/events-202606.jsonl.tmp" "$FAKE_REPO/.ai/events/events-202606.jsonl"
( cd "$FAKE_REPO" && bash "$BRIDGE" )
count=$(wc -l < "$shard" | tr -d ' ')
if [ "$count" -ne 5 ]; then
  echo "FAIL: cursor-reset run expected 5 total (4 + 1 new), got $count"; fail=1
fi
dupes=$(python3 - "$shard" <<'PY'
import json, sys
origins = [json.loads(l)["origin_event_id"]
           for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
print(len(origins) - len(set(origins)))
PY
)
if [ "$dupes" -ne 0 ]; then
  echo "FAIL: $dupes duplicate origin_event_id(s) after cursor reset"; fail=1
fi
if ! grep -q "EVT-20260610T140000Z-T-K-5-eeee5555" "$shard"; then
  echo "FAIL: new event after cursor reset was not imported"; fail=1
fi

# --- 6. cursor file exists -------------------------------------------------------
cursor_count=$(ls "$STORE/cursors/" 2>/dev/null | grep -c . || true)
if [ "$cursor_count" -lt 1 ]; then
  echo "FAIL: cursor file not written under $STORE/cursors/"; fail=1
fi

# --- 7. repo without .ai/events is a no-op, exit 0 -------------------------------
EMPTY_REPO=$(mktemp -d)
git -C "$EMPTY_REPO" init -q
( cd "$EMPTY_REPO" && bash "$BRIDGE" )
rc=$?
rm -rf "$EMPTY_REPO"
if [ "$rc" -ne 0 ]; then
  echo "FAIL: bridge on repo without events exited $rc (expected 0)"; fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "test-bridge: all assertions passed"
