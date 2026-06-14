#!/usr/bin/env bash
# tests/activity/test-bridge-enrichment.sh — bridge event enrichment tests.
# Target: scripts/activity/bridge-kernel-events.sh (Observability v2 課題 #3, T-OS-504).
# Spec: .ai/DESIGN/OBSERVABILITY_LEARNING_V2.md §"課題 #3" 対策(2).
#
# Intent under test:
#   When bridging a kernel task event (e.g. TaskUpdated T-OS-xxx), the bridge
#   should look up that task in the repo's .ai/TASKS.yaml and put the task's
#   human-readable TITLE into the activity event title — not just the bare id.
#   So "TaskUpdated T-OS-xxx" becomes something like
#   "TaskUpdated T-OS-xxx: <task title>".
#
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

# A distinctive title that cannot be confused with the task id itself.
KNOWN_TITLE="Stop フックでセッション要約を生成する"
KNOWN_ID="T-OS-504"

git -C "$FAKE_REPO" init -q

# .ai/TASKS.yaml with a task carrying the known title (new _machine layout keeps
# TASKS.yaml under .ai/, same as the live repo).
mkdir -p "$FAKE_REPO/.ai"
cat > "$FAKE_REPO/.ai/TASKS.yaml" <<EOF
# ORGOS-LEGACY: use scripts/org/update-task.py
tasks:
  - id: T-OS-503
    title: 'unrelated decoy task'
    status: done
  - id: ${KNOWN_ID}
    title: '${KNOWN_TITLE}'
    status: in_progress
    priority: P1
EOF

# Kernel events: a TaskUpdated for the known id (new _machine layout).
mkdir -p "$FAKE_REPO/.ai/_machine/events"
cat > "$FAKE_REPO/.ai/_machine/events/events-202606.jsonl" <<EOF
{"actor":{"id":"claude-manager","role":"manager"},"event_id":"EVT-20260614T120000Z-${KNOWN_ID}-cccc3333","event_type":"TaskUpdated","hash":"h1","payload":{"status":"in_progress"},"prev_hash":"0","schema_version":"orgos-event.v1","task_id":"${KNOWN_ID}","ts":"2026-06-14T12:00:00Z"}
EOF

shard="$STORE/events-202606.jsonl"

( cd "$FAKE_REPO" && bash "$BRIDGE" )
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: bridge exited $rc (expected 0)"; fail=1
fi
if [ ! -f "$shard" ]; then
  echo "FAIL: central shard not created"; fail=1
  exit 1
fi

# --- 1. The bridged event title includes the task TITLE, not just the id ------
if ! python3 - "$shard" "$KNOWN_ID" "$KNOWN_TITLE" <<'PY'
import json, sys
shard, known_id, known_title = sys.argv[1], sys.argv[2], sys.argv[3]
events = [json.loads(l) for l in open(shard, encoding="utf-8") if l.strip()]
ev = [e for e in events
      if e.get("origin_event_id", "").startswith("EVT-20260614T120000Z-")][0]
title = str(ev.get("title", ""))
blob = title + " " + str(ev.get("detail", ""))
assert known_id in blob, "task id missing from enriched event: %r" % blob
assert known_title in blob, (
    "task TITLE missing from enriched event (still id-only?): %r" % blob)
# Guard against a trivial pass where the title is *only* the id with no title text.
assert title.strip() not in (known_id, "TaskUpdated %s" % known_id), (
    "title was not enriched beyond the bare id: %r" % title)
PY
then
  echo "FAIL: bridge did not enrich event title with the task title from TASKS.yaml"; fail=1
fi

# --- 2. Unknown task id still bridges (no crash, exit 0) ----------------------
# A task id that is NOT in TASKS.yaml must not break the bridge; it should fall
# back to the bare-id title and import cleanly.
cat >> "$FAKE_REPO/.ai/_machine/events/events-202606.jsonl" <<'EOF'
{"actor":{"id":"claude-manager","role":"manager"},"event_id":"EVT-20260614T130000Z-T-OS-999-dddd4444","event_type":"TaskUpdated","hash":"h2","payload":{"status":"done"},"prev_hash":"h1","schema_version":"orgos-event.v1","task_id":"T-OS-999","ts":"2026-06-14T13:00:00Z"}
EOF
( cd "$FAKE_REPO" && bash "$BRIDGE" )
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: bridge with unknown task id exited $rc (expected 0)"; fail=1
fi
if ! python3 - "$shard" <<'PY'
import json, sys
events = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
ev = [e for e in events
      if e.get("origin_event_id", "").startswith("EVT-20260614T130000Z-")]
assert len(ev) == 1, "unknown-task event not bridged exactly once: %d" % len(ev)
assert "T-OS-999" in str(ev[0].get("title", "")), ev[0].get("title")
PY
then
  echo "FAIL: bridge did not cleanly handle a task id absent from TASKS.yaml"; fail=1
fi

# --- 3. No TASKS.yaml at all -> bridge still works (graceful degrade) ---------
NO_TASKS_REPO=$(mktemp -d)
git -C "$NO_TASKS_REPO" init -q
mkdir -p "$NO_TASKS_REPO/.ai/_machine/events"
cat > "$NO_TASKS_REPO/.ai/_machine/events/events-202606.jsonl" <<'EOF'
{"actor":{"id":"claude-manager","role":"manager"},"event_id":"EVT-20260614T140000Z-T-OS-700-eeee5555","event_type":"TaskUpdated","hash":"h1","payload":{"status":"done"},"prev_hash":"0","schema_version":"orgos-event.v1","task_id":"T-OS-700","ts":"2026-06-14T14:00:00Z"}
EOF
( cd "$NO_TASKS_REPO" && ORGOS_ACTIVITY_DIR="$STORE" bash "$BRIDGE" )
rc=$?
rm -rf "$NO_TASKS_REPO"
if [ "$rc" -ne 0 ]; then
  echo "FAIL: bridge with no TASKS.yaml exited $rc (expected 0)"; fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "test-bridge-enrichment: all assertions passed"
