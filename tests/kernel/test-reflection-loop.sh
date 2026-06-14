#!/usr/bin/env bash
# Reflection Loop tests (T-OS-505 / OBSERVABILITY_LEARNING_V2.md 課題 #4).
#
# Exercises scripts/org/append-reflection.py against a throwaway fake repo:
#   1. append (--text --trigger owner_correction) -> exactly 1 valid JSONL line,
#      id matches REF-[0-9]{8}-[0-9]+, status=open, category=unclassified.
#   2. append a 2nd -> id increments, 2 lines.
#   3. update --id <REF> --set-category behavioral --set-status integrated
#      --integrated-into memory -> that line updated in place (not appended),
#      still 2 lines, valid JSON.
#   4. invalid --trigger -> non-zero exit, no malformed line.
#   5. text containing a fake secret token -> no crash (redacted or stored);
#      assert exit 0 + valid JSON.
#
# IMPORTANT: every invocation passes --repo-root pointing at a mktemp fake repo.
# This test NEVER touches the real .ai/REFLECTIONS.jsonl.
#
# bash 3.2 compatible (macOS default); python3 stdlib only.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
APPEND_REFLECTION=${APPEND_REFLECTION:-"$REPO_ROOT/scripts/org/append-reflection.py"}

REAL_LEDGER="$REPO_ROOT/.ai/REFLECTIONS.jsonl"

pass_count=0
fail_count=0
current_test_failed=0

# Per-test fake repo dir, cleaned up by trap.
FAKE_ROOT=""

cleanup() {
  [ -n "${FAKE_ROOT:-}" ] && rm -rf "$FAKE_ROOT"
  FAKE_ROOT=""
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
  return 1
}

# Create a minimal throwaway repo with a .ai/ dir. NOT a git repo on purpose:
# append-reflection.py only shells out to git when --repo-root is omitted, and
# we always pass --repo-root, so it stays fully inside the fake tree.
make_fake_repo() {
  cleanup
  FAKE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/orgos-reflection-loop.XXXXXX")
  mkdir -p "$FAKE_ROOT/.ai"
  printf '%s\n' "$FAKE_ROOT"
}

ledger_path() {
  printf '%s\n' "$FAKE_ROOT/.ai/REFLECTIONS.jsonl"
}

# Count non-blank lines.
line_count() {
  local path="$1"
  if [ ! -f "$path" ]; then
    printf '0\n'
    return 0
  fi
  awk 'NF { n++ } END { print n + 0 }' "$path"
}

# Validate that every non-blank line in the file is a JSON object.
assert_all_lines_valid_json() {
  local path="$1"
  local msg="$2"
  python3 - "$path" <<'PY' || fail "$msg"
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    for lineno, raw in enumerate(handle, start=1):
        line = raw.strip()
        if not line:
            continue
        obj = json.loads(line)  # raises -> non-zero -> fail
        if not isinstance(obj, dict):
            raise SystemExit(f"line {lineno} is not a JSON object")
PY
}

# Extract a field from the Nth (1-based) non-blank JSONL record.
record_field() {
  local path="$1"
  local index="$2"
  local field="$3"
  python3 - "$path" "$index" "$field" <<'PY'
import json
import sys

path, index, field = sys.argv[1], int(sys.argv[2]), sys.argv[3]
records = []
with open(path, "r", encoding="utf-8") as handle:
    for raw in handle:
        line = raw.strip()
        if line:
            records.append(json.loads(line))
rec = records[index - 1]
value = rec.get(field, "")
sys.stdout.write("" if value is None else str(value))
PY
}

# ----------------------------------------------------------------------------

test_real_ledger_untouched() {
  # Guard: snapshot the real ledger (or its absence) at suite start and assert
  # it is unchanged at the end. Re-checked here per the spec's hard constraint.
  if [ -f "$REAL_LEDGER" ]; then
    [ -n "${REAL_LEDGER_SNAPSHOT:-}" ] || fail "expected snapshot of real ledger"
  fi
}

test_append_first_reflection() {
  make_fake_repo >/dev/null
  local ledger
  ledger=$(ledger_path)

  python3 "$APPEND_REFLECTION" \
    --repo-root "$FAKE_ROOT" \
    --text "選択肢で聞くな。自律実行して結果を報告しろ。" \
    --trigger owner_correction >/dev/null \
    || fail "first append should exit 0"

  [ -f "$ledger" ] || fail "append should create $ledger"
  [ "$(line_count "$ledger")" = "1" ] || fail "ledger should have exactly 1 line"
  assert_all_lines_valid_json "$ledger" "first append produced invalid JSON"

  local id status category
  id=$(record_field "$ledger" 1 id)
  status=$(record_field "$ledger" 1 status)
  category=$(record_field "$ledger" 1 category)

  printf '%s' "$id" | grep -Eq '^REF-[0-9]{8}-[0-9]+$' \
    || fail "id '$id' should match REF-[0-9]{8}-[0-9]+"
  [ "$status" = "open" ] || fail "default status should be open, got '$status'"
  [ "$category" = "unclassified" ] \
    || fail "default category should be unclassified, got '$category'"
}

test_append_second_increments_id() {
  make_fake_repo >/dev/null
  local ledger
  ledger=$(ledger_path)

  python3 "$APPEND_REFLECTION" --repo-root "$FAKE_ROOT" \
    --text "一つ目の反省" --trigger owner_correction >/dev/null \
    || fail "first append should exit 0"
  python3 "$APPEND_REFLECTION" --repo-root "$FAKE_ROOT" \
    --text "二つ目の反省" --trigger self_error >/dev/null \
    || fail "second append should exit 0"

  [ "$(line_count "$ledger")" = "2" ] || fail "ledger should have 2 lines"
  assert_all_lines_valid_json "$ledger" "second append produced invalid JSON"

  local id1 id2 n1 n2
  id1=$(record_field "$ledger" 1 id)
  id2=$(record_field "$ledger" 2 id)
  [ "$id1" != "$id2" ] || fail "second id should differ from first ($id1 == $id2)"

  # Sequence suffix should increment (NNN portion).
  n1=$(printf '%s' "$id1" | sed -E 's/^REF-[0-9]{8}-0*//')
  n2=$(printf '%s' "$id2" | sed -E 's/^REF-[0-9]{8}-0*//')
  [ -n "$n1" ] || n1=0
  [ -n "$n2" ] || n2=0
  [ "$n2" -gt "$n1" ] || fail "second seq ($n2) should be greater than first ($n1)"
}

test_update_in_place() {
  make_fake_repo >/dev/null
  local ledger
  ledger=$(ledger_path)

  python3 "$APPEND_REFLECTION" --repo-root "$FAKE_ROOT" \
    --text "癖: 過剰確認" --trigger owner_correction >/dev/null \
    || fail "first append should exit 0"
  python3 "$APPEND_REFLECTION" --repo-root "$FAKE_ROOT" \
    --text "保持すべき2件目" --trigger principle >/dev/null \
    || fail "second append should exit 0"

  [ "$(line_count "$ledger")" = "2" ] || fail "precondition: 2 lines before update"

  local target_id
  target_id=$(record_field "$ledger" 1 id)
  [ -n "$target_id" ] || fail "could not read target id"

  python3 "$APPEND_REFLECTION" --repo-root "$FAKE_ROOT" \
    --id "$target_id" \
    --set-category behavioral \
    --set-status integrated \
    --integrated-into memory >/dev/null \
    || fail "update should exit 0"

  # Update is in place: still exactly 2 lines, none appended.
  [ "$(line_count "$ledger")" = "2" ] || fail "update must not append (expected 2 lines)"
  assert_all_lines_valid_json "$ledger" "update produced invalid JSON"

  # The targeted record reflects the new fields.
  local id status category integrated
  id=$(record_field "$ledger" 1 id)
  status=$(record_field "$ledger" 1 status)
  category=$(record_field "$ledger" 1 category)
  integrated=$(record_field "$ledger" 1 integrated_into)

  [ "$id" = "$target_id" ] || fail "updated record id changed ($id != $target_id)"
  [ "$status" = "integrated" ] || fail "status should be integrated, got '$status'"
  [ "$category" = "behavioral" ] || fail "category should be behavioral, got '$category'"
  [ "$integrated" = "memory" ] \
    || fail "integrated_into should be memory, got '$integrated'"

  # The untouched 2nd record is still open/unclassified.
  local other_status
  other_status=$(record_field "$ledger" 2 status)
  [ "$other_status" = "open" ] || fail "non-target record should stay open, got '$other_status'"
}

test_invalid_trigger_rejected() {
  make_fake_repo >/dev/null
  local ledger status
  ledger=$(ledger_path)

  set +e
  python3 "$APPEND_REFLECTION" --repo-root "$FAKE_ROOT" \
    --text "不正な trigger" --trigger bogus_trigger >/dev/null 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "invalid --trigger should exit non-zero"

  # No malformed line written. Ledger is either absent or empty.
  if [ -f "$ledger" ]; then
    [ "$(line_count "$ledger")" = "0" ] \
      || fail "invalid append must not write a line (found $(line_count "$ledger"))"
    assert_all_lines_valid_json "$ledger" "ledger has malformed content after rejected append"
  fi
}

test_secret_in_text_no_crash() {
  make_fake_repo >/dev/null
  local ledger status
  ledger=$(ledger_path)

  # Fake (non-real) secret-shaped token. The tool may redact or store it; the
  # spec only requires exit 0 and valid JSON (no crash on secret-shaped input).
  set +e
  python3 "$APPEND_REFLECTION" --repo-root "$FAKE_ROOT" \
    --text "leaked api_key=sk-FAKE0000notarealsecret0000FAKE during debug" \
    --trigger self_error >/dev/null 2>&1
  status=$?
  set -e

  [ "$status" -eq 0 ] || fail "secret-shaped text should still exit 0"
  [ -f "$ledger" ] || fail "append should have created the ledger"
  [ "$(line_count "$ledger")" = "1" ] || fail "ledger should have 1 line"
  assert_all_lines_valid_json "$ledger" "secret-shaped append produced invalid JSON"
}

# ----------------------------------------------------------------------------

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
  # Snapshot the real ledger so we can prove the suite never touched it.
  REAL_LEDGER_SNAPSHOT=""
  if [ -f "$REAL_LEDGER" ]; then
    REAL_LEDGER_SNAPSHOT=$(cksum "$REAL_LEDGER")
  fi

  [ -f "$APPEND_REFLECTION" ] || {
    printf 'not ok - append-reflection.py not found at %s\n' "$APPEND_REFLECTION" >&2
    exit 1
  }

  case "${1:-}" in
    --only)
      shift
      run_test "$1"
      ;;
    "")
      run_test test_append_first_reflection
      run_test test_append_second_increments_id
      run_test test_update_in_place
      run_test test_invalid_trigger_rejected
      run_test test_secret_in_text_no_crash
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  # Hard constraint: the real .ai/REFLECTIONS.jsonl must be untouched.
  local after_snapshot=""
  if [ -f "$REAL_LEDGER" ]; then
    after_snapshot=$(cksum "$REAL_LEDGER")
  fi
  if [ "$REAL_LEDGER_SNAPSHOT" != "$after_snapshot" ]; then
    printf 'not ok - real ledger %s was modified by the suite\n' "$REAL_LEDGER" >&2
    fail_count=$((fail_count + 1))
  fi

  printf 'Reflection loop tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
