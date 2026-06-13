#!/usr/bin/env bash
# Regression tests for scripts/org/migrate-layout.sh
# Covers .ai/DESIGN/LAYOUT_MIGRATION_COMPAT.md §5:
#   (1) fresh OLD-layout repo -> all under _machine/, old dirs gone
#   (2) idempotency: second run = already-current, no new git changes
#   (3) events hash chain intact after move
#   (4) partial state: only the still-old dir moves
#   (5) merge/collision: both survive, one suffixed _from_legacy, no data loss
#   (6) --dry-run changes nothing
#
# Every test operates on a fresh mktemp fake repo and NEVER touches the real
# repo's .ai/ or ~/.orgos. macOS bash 3.2 compatible; python3 stdlib only.
set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
MIGRATE=${MIGRATE_SCRIPT:-"$REPO_ROOT/scripts/org/migrate-layout.sh"}

pass_count=0
fail_count=0
current_test_failed=0

# Temp dirs are created under a single per-process root so the EXIT trap can
# clean them all regardless of subshell scoping (mk_tmp runs inside a command
# substitution, so any parent-shell variable it sets would be lost).
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/orgos-layout-mig.XXXXXX")
cleanup() {
  [ -n "${TMP_ROOT:-}" ] && rm -rf "$TMP_ROOT" 2>/dev/null
}
trap cleanup EXIT INT TERM

mk_tmp() {
  local d
  d=$(mktemp -d "$TMP_ROOT/case.XXXXXX")
  printf '%s' "$d"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
  return 1
}

assert_dir() {
  [ -d "$1" ] || fail "$2: expected directory $1"
}

assert_no_dir() {
  [ ! -e "$1" ] || fail "$2: expected $1 to NOT exist"
}

assert_file() {
  [ -f "$1" ] || fail "$2: expected file $1"
}

assert_file_content() {
  local path="$1" expect="$2" msg="$3"
  [ -f "$path" ] || { fail "$msg: missing file $path"; return; }
  local got
  got=$(cat "$path")
  [ "$got" = "$expect" ] || fail "$msg: $path content '$got' != '$expect'"
}

# Write a 2-line valid hash-chained events ledger to the given path.
write_events_ledger() {
  local out_path="$1"
  EVENTS_OUT="$out_path" python3 - <<'PY'
import json, hashlib, os
def canon(e):
    return json.dumps(e, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
def ehash(e):
    return hashlib.sha256(canon({k: v for k, v in e.items() if k != "hash"})).hexdigest()
ZERO = "0" * 64
e1 = {"event_id": "EVT-1", "ts": "2026-06-01T00:00:00Z", "event_type": "TaskCreated",
      "task_id": "T-OS-1", "actor": {"id": "a", "role": "manager"}, "payload": {},
      "prev_hash": ZERO, "schema_version": "orgos-event.v1"}
e1["hash"] = ehash(e1)
e2 = {"event_id": "EVT-2", "ts": "2026-06-01T00:01:00Z", "event_type": "TaskUpdated",
      "task_id": "T-OS-1", "actor": {"id": "a", "role": "manager"}, "payload": {"status": "done"},
      "prev_hash": e1["hash"], "schema_version": "orgos-event.v1"}
e2["hash"] = ehash(e2)
out = os.environ["EVENTS_OUT"]
with open(out, "w", encoding="utf-8") as fh:
    for e in (e1, e2):
        fh.write(json.dumps(e, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")
PY
}

# Write an events ledger from a space-separated list of event_ids (no chaining
# required for the collision/merge test; each line is a minimal valid event
# carrying a distinct event_id). Usage: write_events_by_ids PATH "EVT-1 EVT-2".
write_events_by_ids() {
  local out_path="$1"
  local ids="$2"
  EVENTS_OUT="$out_path" EVENTS_IDS="$ids" python3 - <<'PY'
import json, os
out = os.environ["EVENTS_OUT"]
ids = os.environ["EVENTS_IDS"].split()
with open(out, "w", encoding="utf-8") as fh:
    for eid in ids:
        ev = {"event_id": eid, "ts": "2026-06-01T00:00:00Z",
              "event_type": "TaskUpdated", "task_id": "T-OS-1",
              "actor": {"id": "a", "role": "manager"}, "payload": {},
              "schema_version": "orgos-event.v1"}
        fh.write(json.dumps(ev, ensure_ascii=False, sort_keys=True,
                            separators=(",", ":")) + "\n")
PY
}

# Echo the sorted set of event_ids present across every file matching the
# events-*.jsonl glob under the given directory. This is exactly the visibility
# the chain verifier / activity bridge have (they both glob events-*.jsonl), so
# it proves the legacy month's events are replay-visible. Usage:
#   event_ids_visible_via_glob DIR  ->  "EVT-1 EVT-2 EVT-3"
event_ids_visible_via_glob() {
  local dir="$1"
  EV_DIR="$dir" python3 - <<'PY'
import glob, json, os
d = os.environ["EV_DIR"]
ids = set()
for path in glob.glob(os.path.join(d, "events-*.jsonl")):
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            try:
                eid = json.loads(line).get("event_id")
            except Exception:
                continue
            if eid:
                ids.add(eid)
print(" ".join(sorted(ids)))
PY
}

# Verify prev_hash linkage of an events ledger. Echoes "OK" or "BROKEN ...".
verify_chain() {
  local path="$1"
  EVENTS_FILE="$path" python3 - <<'PY'
import json, os, sys
path = os.environ["EVENTS_FILE"]
prev = None
n = 0
with open(path, encoding="utf-8") as fh:
    for raw in fh:
        n += 1
        line = raw.strip()
        if not line:
            continue
        ev = json.loads(line)
        if prev is not None and ev.get("prev_hash") != prev:
            print(f"BROKEN at line {n}")
            sys.exit(0)
        prev = ev.get("hash")
print("OK")
PY
}

# Build a fresh OLD-layout fake git repo at $1.
setup_old_layout_repo() {
  local repo="$1"
  (
    cd "$repo" || exit 1
    git init -q .
    git config user.email "tester@example.test"
    git config user.name "OrgOS Test"
    mkdir -p .ai/events .ai/CODEX/ORDERS .ai/leases .ai/EVOLUTION .ai/ARTIFACTS/T-OS-1
    git config commit.gpgsign false
  )
  write_events_ledger "$repo/.ai/events/events-202606.jsonl"
  echo "order body" > "$repo/.ai/CODEX/ORDERS/x.md"
  echo "evo body" > "$repo/.ai/EVOLUTION/events.jsonl"
  echo "artifact foo" > "$repo/.ai/ARTIFACTS/T-OS-1/foo"
  : > "$repo/.ai/leases/.gitkeep"
  (
    cd "$repo" || exit 1
    git add -A
    git commit -qm "init old layout"
  )
}

run_migrate() {
  # run_migrate REPO [extra args...]
  local repo="$1"
  shift
  bash "$MIGRATE" --repo-root "$repo" "$@"
}

# ---------------------------------------------------------------------------
# (1) Fresh OLD-layout repo -> everything under _machine/, old dirs gone.
# ---------------------------------------------------------------------------
test_fresh_old_layout_migrates() {
  local repo
  repo=$(mk_tmp)/repo
  mkdir -p "$repo"
  setup_old_layout_repo "$repo"

  run_migrate "$repo" --quiet >/dev/null || fail "migrate should exit 0"

  assert_dir "$repo/.ai/_machine/events" "(1) events under _machine"
  assert_dir "$repo/.ai/_machine/codex" "(1) codex under _machine"
  assert_dir "$repo/.ai/_machine/leases" "(1) leases under _machine"
  assert_dir "$repo/.ai/_machine/evolution" "(1) evolution under _machine"
  assert_dir "$repo/.ai/_machine/artifacts" "(1) artifacts under _machine"

  assert_no_dir "$repo/.ai/events" "(1) old events gone"
  assert_no_dir "$repo/.ai/CODEX" "(1) old CODEX gone"
  assert_no_dir "$repo/.ai/leases" "(1) old leases gone"
  assert_no_dir "$repo/.ai/EVOLUTION" "(1) old EVOLUTION gone"
  assert_no_dir "$repo/.ai/ARTIFACTS" "(1) old ARTIFACTS gone"

  # Content preserved end-to-end.
  assert_file_content "$repo/.ai/_machine/codex/ORDERS/x.md" "order body" "(1) order content"
  assert_file_content "$repo/.ai/_machine/artifacts/T-OS-1/foo" "artifact foo" "(1) artifact content"
  assert_file_content "$repo/.ai/_machine/evolution/events.jsonl" "evo body" "(1) evolution content"
}

# ---------------------------------------------------------------------------
# (2) Idempotency: second run reports already-current, no new git changes.
# ---------------------------------------------------------------------------
test_idempotent_second_run() {
  local repo
  repo=$(mk_tmp)/repo
  mkdir -p "$repo"
  setup_old_layout_repo "$repo"

  run_migrate "$repo" --quiet >/dev/null || fail "(2) first run should exit 0"
  # Commit the migration so the tree is clean for the idempotency check.
  ( cd "$repo" && git add -A && git commit -qm "migrate" )

  local out
  out=$(run_migrate "$repo") || fail "(2) second run should exit 0"
  printf '%s\n' "$out" | grep -q "moved 0 dir(s)" \
    || fail "(2) second run should move 0 dirs: $out"

  # No new git changes introduced by the no-op run.
  local status
  status=$( cd "$repo" && git status --porcelain )
  [ -z "$status" ] || fail "(2) second run dirtied the tree: $status"
}

# ---------------------------------------------------------------------------
# (3) Events hash chain intact after move.
# ---------------------------------------------------------------------------
test_events_chain_intact() {
  local repo
  repo=$(mk_tmp)/repo
  mkdir -p "$repo"
  setup_old_layout_repo "$repo"

  # Sanity: chain valid before migration.
  [ "$(verify_chain "$repo/.ai/events/events-202606.jsonl")" = "OK" ] \
    || fail "(3) pre-migration chain should be OK"

  local out
  out=$(run_migrate "$repo") || fail "(3) migrate should exit 0"

  # Script's own verification line should report OK.
  printf '%s\n' "$out" | grep -q "events chain events-202606.jsonl OK" \
    || fail "(3) script should report events chain OK: $out"

  # Independent re-verification on the moved file.
  [ "$(verify_chain "$repo/.ai/_machine/events/events-202606.jsonl")" = "OK" ] \
    || fail "(3) post-migration chain should be OK"
}

# ---------------------------------------------------------------------------
# (4) Partial state: events already at _machine, CODEX still old -> only CODEX
#     moves.
# ---------------------------------------------------------------------------
test_partial_state_moves_remainder() {
  local repo
  repo=$(mk_tmp)/repo
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q .
    git config user.email "tester@example.test"
    git config user.name "OrgOS Test"
    git config commit.gpgsign false
    mkdir -p .ai/_machine/events .ai/CODEX/ORDERS
  )
  write_events_ledger "$repo/.ai/_machine/events/events-202606.jsonl"
  echo "order body" > "$repo/.ai/CODEX/ORDERS/x.md"
  ( cd "$repo" && git add -A && git commit -qm "partial" )

  local out
  out=$(run_migrate "$repo") || fail "(4) migrate should exit 0"

  # CODEX should move; events should stay put (already current, no double-move).
  assert_dir "$repo/.ai/_machine/codex/ORDERS" "(4) CODEX moved"
  assert_no_dir "$repo/.ai/CODEX" "(4) old CODEX gone"
  assert_dir "$repo/.ai/_machine/events" "(4) events still present"
  assert_file_content "$repo/.ai/_machine/codex/ORDERS/x.md" "order body" "(4) codex content"

  # events was NOT re-moved: exactly one moved dir (codex).
  printf '%s\n' "$out" | grep -q "moved 1 dir(s)" \
    || fail "(4) exactly 1 dir should move: $out"
}

# ---------------------------------------------------------------------------
# (5) Merge/collision: both .ai/ARTIFACTS/x and .ai/_machine/artifacts/x exist
#     with different content -> both survive, one suffixed _from_legacy.
# ---------------------------------------------------------------------------
test_merge_collision_keeps_both() {
  local repo
  repo=$(mk_tmp)/repo
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q .
    git config user.email "tester@example.test"
    git config user.name "OrgOS Test"
    git config commit.gpgsign false
    mkdir -p .ai/ARTIFACTS .ai/_machine/artifacts
  )
  # Same basename 'x', different content, in both old and new.
  echo "legacy content" > "$repo/.ai/ARTIFACTS/x"
  echo "new content" > "$repo/.ai/_machine/artifacts/x"
  # A non-colliding legacy entry to confirm normal merge still happens.
  echo "only in legacy" > "$repo/.ai/ARTIFACTS/unique_legacy"
  ( cd "$repo" && git add -A && git commit -qm "collision setup" )

  run_migrate "$repo" --quiet >/dev/null || fail "(5) migrate should exit 0"

  # Old ARTIFACTS dir consumed.
  assert_no_dir "$repo/.ai/ARTIFACTS" "(5) old ARTIFACTS gone after merge"

  # The new file is untouched.
  assert_file_content "$repo/.ai/_machine/artifacts/x" "new content" "(5) new 'x' preserved"
  # The legacy colliding file survives under a _from_legacy suffix.
  assert_file_content "$repo/.ai/_machine/artifacts/x_from_legacy" "legacy content" \
    "(5) legacy 'x' kept as x_from_legacy"
  # The non-colliding legacy file merged normally.
  assert_file_content "$repo/.ai/_machine/artifacts/unique_legacy" "only in legacy" \
    "(5) unique legacy file merged"
}

# ---------------------------------------------------------------------------
# (5b) Same-month events ledger collision (T-OS-498 Risk 1):
#   .ai/events/events-202606.jsonl and .ai/_machine/events/events-202606.jsonl
#   both exist. The legacy month's events must be MERGED into the new month file
#   (missing event_ids appended, order preserved) so they stay visible to the
#   events-*.jsonl glob used by the chain verifier and the activity bridge —
#   NOT salvaged to a _from_legacy name that escapes the glob.
# ---------------------------------------------------------------------------
test_merge_collision() {
  local repo
  repo=$(mk_tmp)/repo
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q .
    git config user.email "tester@example.test"
    git config user.name "OrgOS Test"
    git config commit.gpgsign false
    mkdir -p .ai/events .ai/_machine/events
  )
  # Legacy month has EVT-1, EVT-2; new month has EVT-1 (identical), EVT-3.
  # Expected after merge: EVT-2 appended -> {EVT-1, EVT-2, EVT-3} all visible.
  write_events_by_ids "$repo/.ai/events/events-202606.jsonl" "EVT-1 EVT-2"
  write_events_by_ids "$repo/.ai/_machine/events/events-202606.jsonl" "EVT-1 EVT-3"
  ( cd "$repo" && git add -A && git commit -qm "events collision setup" )

  run_migrate "$repo" --quiet >/dev/null || fail "(5b) migrate should exit 0"

  # Legacy events dir consumed.
  assert_no_dir "$repo/.ai/events" "(5b) old events dir gone after merge"

  # The new month file STILL matches events-*.jsonl (no _from_legacy escape).
  assert_file "$repo/.ai/_machine/events/events-202606.jsonl" \
    "(5b) new month file present under events-*.jsonl glob"

  # No _from_legacy salvage file (that name escapes the events-*.jsonl glob).
  assert_no_dir "$repo/.ai/_machine/events/events-202606.jsonl_from_legacy" \
    "(5b) no _from_legacy salvage (would be invisible to glob)"

  # All three event_ids are visible via the events-*.jsonl glob — i.e. the
  # legacy month's EVT-2 ended up replay-visible.
  local visible
  visible=$(event_ids_visible_via_glob "$repo/.ai/_machine/events")
  [ "$visible" = "EVT-1 EVT-2 EVT-3" ] \
    || fail "(5b) legacy events not all glob-visible: '$visible' != 'EVT-1 EVT-2 EVT-3'"
}

# ---------------------------------------------------------------------------
# (6) --dry-run changes nothing.
# ---------------------------------------------------------------------------
test_dry_run_changes_nothing() {
  local repo
  repo=$(mk_tmp)/repo
  mkdir -p "$repo"
  setup_old_layout_repo "$repo"

  local before_status before_listing
  before_status=$( cd "$repo" && git status --porcelain )
  before_listing=$( find "$repo/.ai" -mindepth 1 | sort )

  run_migrate "$repo" --dry-run >/dev/null || fail "(6) dry-run should exit 0"

  assert_no_dir "$repo/.ai/_machine" "(6) dry-run must not create _machine"
  assert_dir "$repo/.ai/events" "(6) dry-run leaves old events"
  assert_dir "$repo/.ai/CODEX" "(6) dry-run leaves old CODEX"

  local after_status after_listing
  after_status=$( cd "$repo" && git status --porcelain )
  after_listing=$( find "$repo/.ai" -mindepth 1 | sort )

  [ "$before_status" = "$after_status" ] || fail "(6) dry-run changed git status"
  [ "$before_listing" = "$after_listing" ] || fail "(6) dry-run changed the filesystem listing"
}

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------
run_test() {
  local name="$1"
  current_test_failed=0
  set +e
  "$name"
  local status=$?
  set -e

  if [ "$status" -eq 0 ] && [ "$current_test_failed" -eq 0 ]; then
    pass_count=$((pass_count + 1))
    printf 'ok - %s\n' "$name"
  else
    fail_count=$((fail_count + 1))
    printf 'not ok - %s\n' "$name" >&2
  fi
}

main() {
  [ -x "$MIGRATE" ] || { echo "migrate-layout.sh is not executable: $MIGRATE" >&2; exit 2; }

  case "${1:-}" in
    --only)
      shift
      run_test "$1"
      ;;
    "")
      run_test test_fresh_old_layout_migrates
      run_test test_idempotent_second_run
      run_test test_events_chain_intact
      run_test test_partial_state_moves_remainder
      run_test test_merge_collision_keeps_both
      run_test test_merge_collision
      run_test test_dry_run_changes_nothing
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf '# layout-migration tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
