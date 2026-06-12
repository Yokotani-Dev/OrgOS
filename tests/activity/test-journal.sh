#!/usr/bin/env bash
# tests/activity/test-journal.sh — journal.sh query / digest tests.
# Spec: .ai/DESIGN/ACTIVITY_LEDGER.md §4.2 / §7 (5)
# bash 3.2 compatible. Never touches the real ~/.orgos.
# TZ=UTC is forced so local-date filtering equals the UTC timestamps we seed.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
JOURNAL="$REPO_ROOT/scripts/activity/journal.sh"

STORE=$(mktemp -d)
trap 'rm -rf "$STORE"' EXIT
export ORGOS_ACTIVITY_DIR="$STORE"
export TZ=UTC

fail=0

# Seed synthetic events (schema orgos-activity.v1) across two days / two repos.
mkevent() {
  # mkevent <ts> <repo> <type> <task_id> <title>
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json, sys
ts, repo, etype, task_id, title = sys.argv[1:6]
print(json.dumps({
    "schema_version": "orgos-activity.v1",
    "event_id": "ACT-%s-%s" % (ts.replace("-", "").replace(":", ""), "deadbeef"),
    "ts": ts,
    "repo": {"name": repo, "path": "/tmp/" + repo, "remote": ""},
    "branch": "main",
    "session_id": "",
    "actor": {"role": "manager", "id": "claude-manager"},
    "event_type": etype,
    "task_id": task_id,
    "title": title,
    "detail": "",
    "source": "cli",
    "origin_event_id": "",
}, sort_keys=True, ensure_ascii=False))
PY
}

{
  mkevent "2026-06-09T23:00:00Z" "repoA" "decision" ""         "yesterday decision"
  mkevent "2026-06-10T01:00:00Z" "repoA" "note"     ""         "morning note"
  mkevent "2026-06-10T02:00:00Z" "repoB" "task_done" "T-X-1"   "shipped feature"
  mkevent "2026-06-10T03:00:00Z" "repoB" "session_start" ""    "session start"
} > "$STORE/events-202606.jsonl"

# --- 1. --date filter (json) ---------------------------------------------------
out=$(bash "$JOURNAL" --date 2026-06-10 --format json)
count=$(printf '%s' "$out" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
if [ "$count" -ne 3 ]; then
  echo "FAIL: --date 2026-06-10 json expected 3 events, got $count"; fail=1
fi

# --- 2. --repo filter ----------------------------------------------------------
out=$(bash "$JOURNAL" --date 2026-06-10 --repo repoA --format json)
if ! printf '%s' "$out" | python3 -c '
import json, sys
evs = json.load(sys.stdin)
assert len(evs) == 1, len(evs)
assert evs[0]["repo"]["name"] == "repoA"
assert evs[0]["title"] == "morning note"
'; then
  echo "FAIL: --repo repoA filter wrong"; fail=1
fi

# --- 3. --type filter ----------------------------------------------------------
out=$(bash "$JOURNAL" --date 2026-06-10 --type task_done --format json)
if ! printf '%s' "$out" | python3 -c '
import json, sys
evs = json.load(sys.stdin)
assert len(evs) == 1, len(evs)
assert evs[0]["event_type"] == "task_done"
'; then
  echo "FAIL: --type task_done filter wrong"; fail=1
fi

# --- 4. --days range -----------------------------------------------------------
out=$(bash "$JOURNAL" --date 2026-06-10 --days 2 --format json)
count=$(printf '%s' "$out" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
if [ "$count" -ne 4 ]; then
  echo "FAIL: --days 2 expected 4 events, got $count"; fail=1
fi

# --- 5. Markdown digest structure ----------------------------------------------
md=$(bash "$JOURNAL" --date 2026-06-10)
case "$md" in
  *"# OrgOS Journal — 2026-06-10"*) : ;;
  *) echo "FAIL: md missing header"; fail=1 ;;
esac
case "$md" in
  *"## サマリ: 2 リポジトリ / 3 イベント / セッション 1 回"*) : ;;
  *) echo "FAIL: md summary line wrong"; echo "$md"; fail=1 ;;
esac
case "$md" in
  *"💭 考えたこと"*) : ;;
  *) echo "FAIL: md missing thoughts section"; fail=1 ;;
esac
case "$md" in
  *"⚙️ 実行したこと"*) : ;;
  *) echo "FAIL: md missing actions section"; fail=1 ;;
esac
case "$md" in
  *"morning note"*) : ;;
  *) echo "FAIL: md missing thought title"; fail=1 ;;
esac
case "$md" in
  *"### repoB"*) : ;;
  *) echo "FAIL: md missing repo group heading"; fail=1 ;;
esac
case "$md" in
  *"shipped feature (T-X-1)"*) : ;;
  *) echo "FAIL: md missing task-linked action line"; fail=1 ;;
esac

# --- 6. tsv format --------------------------------------------------------------
tsv=$(bash "$JOURNAL" --date 2026-06-10 --format tsv)
tsv_lines=$(printf '%s\n' "$tsv" | grep -c .)
if [ "$tsv_lines" -ne 3 ]; then
  echo "FAIL: tsv expected 3 rows, got $tsv_lines"; fail=1
fi

# --- 7. empty day --------------------------------------------------------------
md_empty=$(bash "$JOURNAL" --date 2026-01-01)
case "$md_empty" in
  *"(イベントなし)"*) : ;;
  *) echo "FAIL: empty day should print (イベントなし)"; fail=1 ;;
esac

# --- 8. invalid args fail loudly (CLI path = explicit errors) -------------------
if bash "$JOURNAL" --date not-a-date >/dev/null 2>&1; then
  echo "FAIL: invalid --date should exit non-zero"; fail=1
fi
if bash "$JOURNAL" --format xml >/dev/null 2>&1; then
  echo "FAIL: invalid --format should exit non-zero"; fail=1
fi

# --- 9. newline injection in title/task_id is neutralized at render time --------
{
  mkevent "2026-06-12T01:00:00Z" "repoA" "note" "" $'multi\nFAKE-INJECTED-LINE'
  mkevent "2026-06-12T02:00:00Z" "repoB" "task_done" $'T-1\nX' $'evil\ntitle'
} >> "$STORE/events-202606.jsonl"
md_inj=$(bash "$JOURNAL" --date 2026-06-12)
case "$md_inj" in
  *"multi FAKE-INJECTED-LINE"*) : ;;
  *) echo "FAIL: md should collapse newline in title to a space"; fail=1 ;;
esac
if printf '%s\n' "$md_inj" | grep -qx "FAKE-INJECTED-LINE"; then
  echo "FAIL: md digest allowed a title to inject its own line"; fail=1
fi
tsv_inj=$(bash "$JOURNAL" --date 2026-06-12 --format tsv)
tsv_inj_lines=$(printf '%s\n' "$tsv_inj" | grep -c .)
if [ "$tsv_inj_lines" -ne 2 ]; then
  echo "FAIL: tsv expected 2 rows for injected events, got $tsv_inj_lines"; fail=1
fi
case "$tsv_inj" in
  *"T-1 X"*) : ;;
  *) echo "FAIL: tsv should collapse newline in task_id"; fail=1 ;;
esac

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "test-journal: all assertions passed"
