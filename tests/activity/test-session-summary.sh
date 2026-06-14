#!/usr/bin/env bash
# tests/activity/test-session-summary.sh — Stop-hook session summary tests.
# Target: scripts/activity/summarize-session.sh (Observability v2 課題 #3, T-OS-504).
# Spec: .ai/DESIGN/OBSERVABILITY_LEARNING_V2.md §"課題 #3" 対策(1).
#
# Intent under test:
#   On session end, produce ONE rich `session_end` activity event whose title
#   summarizes "what happened this session":
#     - commit count for this repo (since session start)
#     - at least one representative commit subject
#     - touched task id(s) drawn from kernel events (.ai/_machine/events)
#   The script is a Stop-hook helper: it MUST exit 0 even when git / events are
#   absent (hook-safe), and MUST NOT touch the real ~/.orgos.
#
# bash 3.2 compatible. Never touches the real ~/.orgos.
# TZ=UTC so any local-date logic matches the UTC timestamps we seed.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
SUMMARIZE="$REPO_ROOT/scripts/activity/summarize-session.sh"

STORE=$(mktemp -d)
FAKE_REPO=$(mktemp -d)
trap 'rm -rf "$STORE" "$FAKE_REPO"' EXIT
export ORGOS_ACTIVITY_DIR="$STORE"
export TZ=UTC

fail=0

if [ ! -f "$SUMMARIZE" ]; then
  echo "FAIL: $SUMMARIZE does not exist (script written in parallel)"
  exit 1
fi

# Latest activity event written by the summarizer that is a session_end.
# Reads every central shard so we do not depend on the current month.
latest_session_end() {
  python3 - "$STORE" <<'PY'
import glob, json, os, sys
store = sys.argv[1]
best = None
for shard in glob.glob(os.path.join(store, "events-*.jsonl")):
    try:
        f = open(shard, encoding="utf-8")
    except Exception:
        continue
    with f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except Exception:
                continue
            if not isinstance(ev, dict):
                continue
            if ev.get("event_type") != "session_end":
                continue
            if best is None or str(ev.get("ts", "")) >= str(best.get("ts", "")):
                best = ev
if best is None:
    sys.exit(3)
print(json.dumps(best, ensure_ascii=False))
PY
}

# ---------------------------------------------------------------------------
# 1. Rich summary: 2 commits + TaskUpdated kernel events -> one session_end
#    whose title carries a commit count, >=1 commit subject, and a task id.
# ---------------------------------------------------------------------------
git -C "$FAKE_REPO" init -q
git -C "$FAKE_REPO" config user.email test@orgos.local
git -C "$FAKE_REPO" config user.name "OrgOS Test"

printf 'one\n' > "$FAKE_REPO/a.txt"
git -C "$FAKE_REPO" add a.txt
git -C "$FAKE_REPO" commit -q -m "publish v2.0.1 release"
printf 'two\n' > "$FAKE_REPO/b.txt"
git -C "$FAKE_REPO" add b.txt
git -C "$FAKE_REPO" commit -q -m "close T-OS-500 cleanup"

# Seed an anchoring session_start (so the summary window is deterministic and
# not at the mercy of wall-clock-vs-6h-fallback) plus two recent TaskUpdated
# kernel events. Timestamps are computed relative to "now" so this test is
# stable regardless of the hour it runs.
mkdir -p "$FAKE_REPO/.ai/_machine/events"
# Use the git-resolved toplevel so repo.path matches what the summarizer derives
# (macOS mktemp lives under a /var -> /private/var symlink).
FAKE_TOPLEVEL=$(git -C "$FAKE_REPO" rev-parse --show-toplevel)
python3 - "$FAKE_REPO" "$STORE" "$FAKE_TOPLEVEL" <<'PY'
import datetime, json, os, sys
fake_repo, store, toplevel = sys.argv[1], sys.argv[2], sys.argv[3]
now = datetime.datetime.now(datetime.timezone.utc)
def iso(dt): return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
start = now - datetime.timedelta(minutes=30)

# Anchoring session_start in the CENTRAL store (find_session_start reads there).
os.makedirs(store, mode=0o700, exist_ok=True)
shard = os.path.join(store, "events-%s.jsonl" % now.strftime("%Y%m"))
with open(shard, "a", encoding="utf-8") as f:
    f.write(json.dumps({
        "schema_version": "orgos-activity.v1",
        "event_id": "ACT-seed-start",
        "ts": iso(start),
        "repo": {"name": os.path.basename(toplevel), "path": toplevel, "remote": ""},
        "branch": "", "session_id": "", "actor": {"role": "manager", "id": "claude-manager"},
        "event_type": "session_start", "task_id": "", "title": "session start",
        "detail": "", "source": "hook", "origin_event_id": "",
    }, sort_keys=True, ensure_ascii=False) + "\n")

# Kernel TaskUpdated events (repo-local) within the window.
edir = os.path.join(fake_repo, ".ai", "_machine", "events")
months = sorted({now.strftime("%Y%m"), start.strftime("%Y%m")})
def kev(ts, eid, tid, status):
    return json.dumps({
        "actor": {"id": "claude-manager", "role": "manager"},
        "event_id": eid, "event_type": "TaskUpdated", "hash": "h",
        "payload": {"status": status}, "prev_hash": "0",
        "schema_version": "orgos-event.v1", "task_id": tid, "ts": ts,
    }, sort_keys=True)
rows = [
    (iso(now - datetime.timedelta(minutes=20)), "EVT-seed-499", "T-OS-499", "in_progress"),
    (iso(now - datetime.timedelta(minutes=10)), "EVT-seed-500", "T-OS-500", "done"),
]
# Write to every month shard the summarizer may read (handles month rollover).
for m in months:
    with open(os.path.join(edir, "events-%s.jsonl" % m), "a", encoding="utf-8") as f:
        for ts, eid, tid, st in rows:
            if ts[:6] == m:
                f.write(kev(ts, eid, tid, st) + "\n")
PY

# Run from inside the fake repo so any cwd-derived repo stamp stays in the
# sandbox; --repo-root is what selects the commit/task window.
out=$( cd "$FAKE_REPO" && bash "$SUMMARIZE" --repo-root "$FAKE_REPO" 2>/dev/null )
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: summarize-session --repo-root exited $rc (expected 0)"; fail=1
fi

ev_json=$(latest_session_end)
if [ -z "$ev_json" ]; then
  echo "FAIL: no session_end activity event was produced"; fail=1
else
  # Pass the event JSON as argv (NOT stdin) so the heredoc stays the program.
  if ! python3 - "$ev_json" <<'PY'
import json, re, sys
ev = json.loads(sys.argv[1])
title = str(ev.get("title", ""))
assert ev.get("event_type") == "session_end", ev.get("event_type")
assert ev.get("schema_version") == "orgos-activity.v1", ev.get("schema_version")
# (a) a commit count appears (the digit 2, the count of seeded commits)
assert re.search(r"\b2\b", title), "no commit count in title: %r" % title
# (b) at least one representative commit subject is present (title or detail)
blob = title + " " + str(ev.get("detail", ""))
subjects = ("publish v2.0.1 release", "close T-OS-500 cleanup")
assert any(s in blob for s in subjects), "no commit subject in summary: %r" % blob
# (c) at least one touched task id from the kernel events
task_ids = ("T-OS-499", "T-OS-500")
assert any(t in blob for t in task_ids), "no task id in summary: %r" % blob
PY
  then
    echo "FAIL: session_end summary missing commit count / subject / task id"; fail=1
    echo "      event: $ev_json"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Hook-safety: git absent (non-repo dir) -> still exit 0, no crash.
# ---------------------------------------------------------------------------
NON_REPO=$(mktemp -d)
out=$(bash "$SUMMARIZE" --repo-root "$NON_REPO" 2>/dev/null)
rc=$?
rm -rf "$NON_REPO"
if [ "$rc" -ne 0 ]; then
  echo "FAIL: summarize-session on a non-git dir exited $rc (expected 0)"; fail=1
fi

# ---------------------------------------------------------------------------
# 3. Hook-safety: events absent (git repo, no kernel events) -> exit 0.
#    A summary may still be produced from commits alone; the contract under
#    test is only that the absence of events is not fatal.
# ---------------------------------------------------------------------------
GIT_ONLY=$(mktemp -d)
git -C "$GIT_ONLY" init -q
git -C "$GIT_ONLY" config user.email test@orgos.local
git -C "$GIT_ONLY" config user.name "OrgOS Test"
printf 'x\n' > "$GIT_ONLY/x.txt"
git -C "$GIT_ONLY" add x.txt
git -C "$GIT_ONLY" commit -q -m "only commit, no kernel events"
out=$(bash "$SUMMARIZE" --repo-root "$GIT_ONLY" 2>/dev/null)
rc=$?
rm -rf "$GIT_ONLY"
if [ "$rc" -ne 0 ]; then
  echo "FAIL: summarize-session with commits-but-no-events exited $rc (expected 0)"; fail=1
fi

# ---------------------------------------------------------------------------
# 4. Hook-safety: nonexistent --repo-root path -> exit 0 (never break Stop).
# ---------------------------------------------------------------------------
out=$(bash "$SUMMARIZE" --repo-root "$STORE/does-not-exist-$$" 2>/dev/null)
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: summarize-session on missing repo-root exited $rc (expected 0)"; fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "test-session-summary: all assertions passed"
