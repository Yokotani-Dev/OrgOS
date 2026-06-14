#!/usr/bin/env bash
# tests/activity/test-journal-denoise.sh — journal session-noise suppression tests.
# Target: scripts/activity/journal.sh (Observability v2 課題 #3, T-OS-504).
# Spec: .ai/DESIGN/OBSERVABILITY_LEARNING_V2.md §"課題 #3" 対策(3).
#
# Intent under test (the "session end ×15" problem):
#   In the Markdown digest, BARE session boundary events (session_start /
#   plain "session end" with no summary) must be COLLAPSED into a single
#   count line instead of N separate lines. The signal events — commits,
#   task_done, and a RICH session_end (one that carries an actual summary) —
#   must remain visible / front-and-centre.
#
# bash 3.2 compatible. Never touches the real ~/.orgos.
# TZ=UTC so local-date filtering equals the UTC timestamps we seed.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
JOURNAL="$REPO_ROOT/scripts/activity/journal.sh"

STORE=$(mktemp -d)
trap 'rm -rf "$STORE"' EXIT
export ORGOS_ACTIVITY_DIR="$STORE"
export TZ=UTC

fail=0

TODAY=$(date -u +%Y-%m-%d)
MONTH=$(date -u +%Y%m)
SHARD="$STORE/events-$MONTH.jsonl"

# mkevent <ts> <repo> <type> <task_id> <title> [detail]
mkevent() {
  python3 - "$1" "$2" "$3" "$4" "$5" "${6:-}" <<'PY'
import json, sys
ts, repo, etype, task_id, title, detail = sys.argv[1:7]
print(json.dumps({
    "schema_version": "orgos-activity.v1",
    "event_id": "ACT-%s-%s" % (ts.replace("-", "").replace(":", ""),
                               "%08x" % (abs(hash(title)) & 0xffffffff)),
    "ts": ts,
    "repo": {"name": repo, "path": "/tmp/" + repo, "remote": ""},
    "branch": "main",
    "session_id": "",
    "actor": {"role": "manager", "id": "claude-manager"},
    "event_type": etype,
    "task_id": task_id,
    "title": title,
    "detail": detail,
    "source": "cli",
    "origin_event_id": "",
}, sort_keys=True, ensure_ascii=False))
PY
}

# --- Seed: many BARE session boundary events for one repo --------------------
# 6 bare session_start + 6 bare session_end (the noise the redesign must hide).
{
  for h in 00 01 02 03 04 05; do
    mkevent "${TODAY}T${h}:00:00Z" "vsp-admin" "session_start" "" "session start"
    mkevent "${TODAY}T${h}:30:00Z" "vsp-admin" "session_end"   "" "session end"
  done
  # --- One RICH session_end: it carries an actual summary (the v2 output). ---
  mkevent "${TODAY}T06:00:00Z" "vsp-admin" "session_end" "" \
    "3 commits (publish v2.0.1, T-OS-500 close) / 2 tasks" \
    "publish v2.0.1; close T-OS-500"
  # --- Signal events that must survive the denoise. --------------------------
  mkevent "${TODAY}T07:00:00Z" "vsp-admin" "commit" "" "publish v2.0.1 release"
  mkevent "${TODAY}T08:00:00Z" "vsp-admin" "task_done" "T-OS-500" "クローン汚染解消"
} > "$SHARD"

md=$(bash "$JOURNAL" today --format md)
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: journal today exited $rc (expected 0)"; fail=1
fi

# --- 1. Bare session events are NOT rendered as many separate lines ----------
# The pre-redesign behaviour emitted one "session end" action line per event.
# After denoise there must be at most one literal "session end" action line.
plain_end_lines=$(printf '%s\n' "$md" | grep -c 'session end' || true)
if [ "$plain_end_lines" -gt 1 ]; then
  echo "FAIL: $plain_end_lines 'session end' lines survived (expected <=1; bare ones must collapse)"
  printf '%s\n' "$md"
  fail=1
fi
plain_start_lines=$(printf '%s\n' "$md" | grep -c 'session start' || true)
if [ "$plain_start_lines" -gt 1 ]; then
  echo "FAIL: $plain_start_lines 'session start' lines survived (expected <=1; bare ones must collapse)"
  fail=1
fi

# --- 2. A collapsed session COUNT is shown instead ---------------------------
# Accept either a Japanese "セッション N 回" summary line or an explicit
# collapsed marker; the contract is "a count, not N lines".
if ! printf '%s\n' "$md" | grep -Eq 'セッション.*[0-9]+.*回'; then
  echo "FAIL: digest does not show a collapsed 'セッション N 回' count line"
  printf '%s\n' "$md"
  fail=1
fi

# --- 3. The RICH session_end summary IS present ------------------------------
case "$md" in
  *"3 commits (publish v2.0.1, T-OS-500 close) / 2 tasks"*) : ;;
  *) echo "FAIL: rich session_end summary was dropped by denoise"; printf '%s\n' "$md"; fail=1 ;;
esac

# --- 4. The commit IS present ------------------------------------------------
case "$md" in
  *"publish v2.0.1 release"*) : ;;
  *) echo "FAIL: commit event was dropped by denoise"; fail=1 ;;
esac

# --- 5. The task_done IS present (with its task id) --------------------------
case "$md" in
  *"クローン汚染解消"*) : ;;
  *) echo "FAIL: task_done event was dropped by denoise"; fail=1 ;;
esac
case "$md" in
  *"T-OS-500"*) : ;;
  *) echo "FAIL: task_done lost its task id (T-OS-500)"; fail=1 ;;
esac

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "test-journal-denoise: all assertions passed"
