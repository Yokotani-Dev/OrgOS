#!/usr/bin/env bash
# Week 2 TASKS.yaml validator and updater tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
VALIDATOR=${VALIDATOR:-"$REPO_ROOT/scripts/org/validate-tasks-yaml.py"}
UPDATER=${UPDATER:-"$REPO_ROOT/scripts/org/update-task.py"}

pass_count=0
fail_count=0
current_test_failed=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
  return 1
}

assert_contains() {
  local path="$1"
  local needle="$2"
  local msg="$3"
  grep -Fq "$needle" "$path" || fail "$msg: expected '$needle' in $path"
}

write_clean_tasks_yaml() {
  local path="$1"
  cat > "$path" <<'YAML'
tasks:
  - id: T-ONE
    title: "One"
    status: queued
    priority: P1
    allowed_paths:
      - "README.md"
  - id: T-TWO
    title: "Two"
    status: running
    priority: P2
YAML
}

assert_yaml_value() {
  local path="$1"
  local expr="$2"
  python3 - "$path" "$expr" <<'PY'
import sys
import yaml

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
tasks = {task["id"]: task for task in data["tasks"]}
if not eval(sys.argv[2], {"tasks": tasks}):
    raise SystemExit(1)
PY
}

test_validator_detects_duplicate_task_id() {
  local tmp_dir yaml_path stderr_path status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-week2-yaml.XXXXXX")
  yaml_path="$tmp_dir/TASKS.yaml"
  stderr_path="$tmp_dir/stderr.log"
  cat > "$yaml_path" <<'YAML'
tasks:
  - id: T-DUP
    title: "One"
    status: queued
  - id: T-DUP
    title: "Two"
    status: done
YAML

  set +e
  "$VALIDATOR" "$yaml_path" 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 1 ] || fail "duplicate task id should exit 1"
  assert_contains "$stderr_path" "DUPLICATE_TASK_ID" "duplicate id should be reported"
  rm -rf "$tmp_dir"
}

test_validator_detects_duplicate_key_in_task() {
  local tmp_dir yaml_path stderr_path status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-week2-yaml.XXXXXX")
  yaml_path="$tmp_dir/TASKS.yaml"
  stderr_path="$tmp_dir/stderr.log"
  cat > "$yaml_path" <<'YAML'
tasks:
  - id: T-KEY
    title: "One"
    status: queued
    priority: P1
    priority: P0
YAML

  set +e
  "$VALIDATOR" "$yaml_path" 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 1 ] || fail "duplicate key should exit 1"
  assert_contains "$stderr_path" "DUPLICATE_KEY" "duplicate key should be reported"
  rm -rf "$tmp_dir"
}

test_validator_accepts_clean_yaml() {
  local tmp_dir yaml_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-week2-yaml.XXXXXX")
  yaml_path="$tmp_dir/TASKS.yaml"
  write_clean_tasks_yaml "$yaml_path"
  "$VALIDATOR" "$yaml_path"
  rm -rf "$tmp_dir"
}

test_update_task_set_status() {
  local tmp_dir yaml_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-week2-yaml.XXXXXX")
  yaml_path="$tmp_dir/TASKS.yaml"
  write_clean_tasks_yaml "$yaml_path"

  "$UPDATER" --file "$yaml_path" T-ONE --set status=done
  assert_yaml_value "$yaml_path" 'tasks["T-ONE"]["status"] == "done"'
  "$VALIDATOR" "$yaml_path"
  rm -rf "$tmp_dir"
}

test_update_task_add_note() {
  local tmp_dir yaml_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-week2-yaml.XXXXXX")
  yaml_path="$tmp_dir/TASKS.yaml"
  write_clean_tasks_yaml "$yaml_path"

  "$UPDATER" --file "$yaml_path" T-TWO --add-note "implementation complete"
  assert_yaml_value "$yaml_path" '"implementation complete" in tasks["T-TWO"]["notes"]'
  "$VALIDATOR" "$yaml_path"
  rm -rf "$tmp_dir"
}

test_update_task_atomic_write() {
  local tmp_dir yaml_path before_inode after_inode
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-week2-yaml.XXXXXX")
  yaml_path="$tmp_dir/TASKS.yaml"
  write_clean_tasks_yaml "$yaml_path"
  before_inode=$(ls -i "$yaml_path" | awk '{print $1}')

  "$UPDATER" --file "$yaml_path" T-TWO --set 'allowed_paths=["scripts/org/update-task.py"]'
  after_inode=$(ls -i "$yaml_path" | awk '{print $1}')

  [ "$before_inode" != "$after_inode" ] || fail "atomic write should replace the original inode"
  assert_yaml_value "$yaml_path" 'tasks["T-TWO"]["allowed_paths"] == ["scripts/org/update-task.py"]'
  "$VALIDATOR" "$yaml_path"
  rm -rf "$tmp_dir"
}

test_update_task_rejects_invalid_yaml() {
  local tmp_dir yaml_path before_hash after_hash stderr_path status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-week2-yaml.XXXXXX")
  yaml_path="$tmp_dir/TASKS.yaml"
  stderr_path="$tmp_dir/stderr.log"
  cat > "$yaml_path" <<'YAML'
tasks:
  - id: T-BAD
    title: "Bad"
    status: queued
    status: done
YAML
  before_hash=$(shasum -a 256 "$yaml_path" | awk '{print $1}')

  set +e
  "$UPDATER" --file "$yaml_path" T-BAD --set priority=P0 2>"$stderr_path"
  status=$?
  set -e
  after_hash=$(shasum -a 256 "$yaml_path" | awk '{print $1}')

  [ "$status" -eq 1 ] || fail "invalid source should be rejected"
  [ "$before_hash" = "$after_hash" ] || fail "invalid source should not be modified"
  assert_contains "$stderr_path" "source TASKS yaml failed validation" "invalid source should explain validation failure"
  rm -rf "$tmp_dir"
}

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
  case "${1:-}" in
    --only)
      shift
      run_test "$1"
      ;;
    "")
      run_test test_validator_detects_duplicate_task_id
      run_test test_validator_detects_duplicate_key_in_task
      run_test test_validator_accepts_clean_yaml
      run_test test_update_task_set_status
      run_test test_update_task_add_note
      run_test test_update_task_atomic_write
      run_test test_update_task_rejects_invalid_yaml
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'Week 2 yaml tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
