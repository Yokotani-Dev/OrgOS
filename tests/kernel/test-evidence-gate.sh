#!/usr/bin/env bash
# Evidence-gated task Done checks.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
CHECK_TASK_DONE=${CHECK_TASK_DONE:-"$REPO_ROOT/scripts/org/check-task-done.py"}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

make_fixture() {
  mktemp -d "${TMPDIR:-/tmp}/orgos-evidence-gate.XXXXXX"
}

write_event() {
  local path="$1"
  local payload="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$payload" >> "$path"
}

assert_passes() {
  local events_path="$1"
  local task_id="$2"
  local msg="$3"
  local output
  if ! output=$(EVENTS_PATH="$events_path" "$CHECK_TASK_DONE" "$task_id" 2>&1); then
    printf '%s\n' "$output" >&2
    fail "$msg"
  fi
  printf '%s\n' "$output" | grep -Fq "evidence sufficient" || fail "$msg: missing success message"
}

assert_fails_with() {
  local events_path="$1"
  local task_id="$2"
  local needle="$3"
  local msg="$4"
  local output
  if output=$(EVENTS_PATH="$events_path" "$CHECK_TASK_DONE" "$task_id" 2>&1); then
    printf '%s\n' "$output" >&2
    fail "$msg: command unexpectedly passed"
  fi
  printf '%s\n' "$output" | grep -Fq "$needle" || fail "$msg: expected '$needle', got '$output'"
}

test_verification_passed_is_sufficient() {
  local tmp_dir events_path
  tmp_dir=$(make_fixture)
  events_path="$tmp_dir/events.jsonl"
  write_event "$events_path" '{"task_id":"T-TEST-1","event_type":"VerificationPassed"}'

  assert_passes "$events_path" "T-TEST-1" "VerificationPassed should satisfy evidence gate"
  rm -rf "$tmp_dir"
}

test_commit_integrated_is_sufficient() {
  local tmp_dir events_path
  tmp_dir=$(make_fixture)
  events_path="$tmp_dir/events.jsonl"
  write_event "$events_path" '{"task":{"id":"T-TEST-2"},"type":"CommitIntegrated"}'

  assert_passes "$events_path" "T-TEST-2" "CommitIntegrated should satisfy evidence gate"
  rm -rf "$tmp_dir"
}

test_missing_required_evidence_fails() {
  local tmp_dir events_path
  tmp_dir=$(make_fixture)
  events_path="$tmp_dir/events.jsonl"
  write_event "$events_path" '{"task_id":"T-TEST-3","event_type":"ReviewRequested"}'

  assert_fails_with "$events_path" "T-TEST-3" "missing required evidence" "missing required event should fail"
  rm -rf "$tmp_dir"
}

test_wrong_task_evidence_fails() {
  local tmp_dir events_path
  tmp_dir=$(make_fixture)
  events_path="$tmp_dir/events.jsonl"
  write_event "$events_path" '{"task_id":"T-OTHER","event_type":"VerificationPassed"}'

  assert_fails_with "$events_path" "T-TEST-4" "no evidence events found" "evidence for another task should fail"
  rm -rf "$tmp_dir"
}

test_invalid_json_fails_closed() {
  local tmp_dir events_path
  tmp_dir=$(make_fixture)
  events_path="$tmp_dir/events.jsonl"
  write_event "$events_path" '{"task_id":"T-TEST-5","event_type":"VerificationPassed"'

  assert_fails_with "$events_path" "T-TEST-5" "not valid JSON" "invalid JSON should fail closed"
  rm -rf "$tmp_dir"
}

test_verification_passed_is_sufficient
test_commit_integrated_is_sufficient
test_missing_required_evidence_fails
test_wrong_task_evidence_fails
test_invalid_json_fails_closed

printf 'ok - evidence gate checks passed\n'
