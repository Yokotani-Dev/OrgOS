#!/usr/bin/env bash
# TASKS.yaml archive automation tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
ARCHIVER=${ARCHIVER:-"$REPO_ROOT/scripts/org/archive-tasks.py"}
VALIDATOR=${VALIDATOR:-"$REPO_ROOT/scripts/org/validate-tasks-yaml.py"}

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
  grep -Fq -- "$needle" "$path" || fail "$msg: expected '$needle' in $path"
}

assert_not_contains() {
  local path="$1"
  local needle="$2"
  local msg="$3"
  if grep -Fq -- "$needle" "$path"; then
    fail "$msg: unexpected '$needle' in $path"
  fi
}

write_tasks_fixture() {
  local path="$1"
  cat > "$path" <<'YAML'
tasks:
  - id: T-QUEUED
    title: "Queued"
    status: queued
  - id: T-DONE
    title: "Done"
    status: done
    completed_at: "2026-04-01T00:00:00Z"
  - id: T-CANCELLED
    title: "Cancelled"
    status: cancelled
    cancelled_at: "2026-03-01"
  - id: T-SUPERSEDED
    title: "Superseded"
    status: superseded
    superseded_at: "2026-02-01T00:00:00+00:00"
YAML
}

write_archive_fixture() {
  local path="$1"
  cat > "$path" <<'YAML'
tasks:
  - id: T-OLD
    title: "Old"
    status: done
    archived_at: "2026-01-01T00:00:00Z"
YAML
}

assert_task_present() {
  local path="$1"
  local task_id="$2"
  python3 - "$path" "$task_id" <<'PY'
import sys
import yaml

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle)

if any(task.get("id") == sys.argv[2] for task in data.get("tasks", [])):
    raise SystemExit(0)
raise SystemExit(1)
PY
}

assert_task_absent() {
  local path="$1"
  local task_id="$2"
  if assert_task_present "$path" "$task_id"; then
    fail "task should be absent: $task_id"
  fi
}

assert_task_has_archived_at() {
  local path="$1"
  local task_id="$2"
  python3 - "$path" "$task_id" <<'PY'
import sys
import yaml

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle)

for task in data.get("tasks", []):
    if task.get("id") == sys.argv[2] and task.get("archived_at"):
        raise SystemExit(0)
raise SystemExit(1)
PY
}

file_inode() {
  python3 - "$1" <<'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).stat().st_ino)
PY
}

test_dry_run_lists_terminal_tasks_only() {
  local tmp_dir tasks_path archive_path stdout_path before_hash after_hash
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-archive-tasks.XXXXXX")
  tasks_path="$tmp_dir/TASKS.yaml"
  archive_path="$tmp_dir/TASKS_ARCHIVE.yaml"
  stdout_path="$tmp_dir/stdout.log"
  write_tasks_fixture "$tasks_path"
  before_hash=$(shasum -a 256 "$tasks_path" | awk '{print $1}')

  "$ARCHIVER" --dry-run --tasks-file "$tasks_path" --archive-file "$archive_path" >"$stdout_path"
  after_hash=$(shasum -a 256 "$tasks_path" | awk '{print $1}')

  assert_contains "$stdout_path" "would archive 3 task(s)" "dry run should count terminal tasks"
  assert_contains "$stdout_path" "T-DONE" "dry run should list done task"
  assert_contains "$stdout_path" "T-CANCELLED" "dry run should list cancelled task"
  assert_contains "$stdout_path" "T-SUPERSEDED" "dry run should list superseded task"
  assert_not_contains "$stdout_path" "T-QUEUED" "dry run should not list active task"
  [ "$before_hash" = "$after_hash" ] || fail "dry run should not modify TASKS.yaml"
  [ ! -e "$archive_path" ] || fail "dry run should not create archive"
  rm -rf "$tmp_dir"
}

test_archive_moves_done_task_to_archive() {
  local tmp_dir tasks_path archive_path stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-archive-tasks.XXXXXX")
  tasks_path="$tmp_dir/TASKS.yaml"
  archive_path="$tmp_dir/TASKS_ARCHIVE.yaml"
  stdout_path="$tmp_dir/stdout.log"
  cat > "$tasks_path" <<'YAML'
tasks:
  - id: T-ACTIVE
    title: "Active"
    status: running
  - id: T-DONE
    title: "Done"
    status: done
YAML

  "$ARCHIVER" --tasks-file "$tasks_path" --archive-file "$archive_path" --now "2026-05-16T00:00:00Z" >"$stdout_path"

  assert_task_absent "$tasks_path" "T-DONE"
  assert_task_present "$tasks_path" "T-ACTIVE" || fail "active task should remain in TASKS.yaml"
  assert_task_present "$archive_path" "T-DONE" || fail "done task should move to archive"
  assert_task_has_archived_at "$archive_path" "T-DONE" || fail "archive task should have archived_at"
  assert_contains "$stdout_path" "archived 1 task(s)" "archive should report moved count"
  rm -rf "$tmp_dir"
}

test_archive_appends_to_existing_archive() {
  local tmp_dir tasks_path archive_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-archive-tasks.XXXXXX")
  tasks_path="$tmp_dir/TASKS.yaml"
  archive_path="$tmp_dir/TASKS_ARCHIVE.yaml"
  cat > "$tasks_path" <<'YAML'
tasks:
  - id: T-DONE
    title: "Done"
    status: done
YAML
  write_archive_fixture "$archive_path"

  "$ARCHIVER" --tasks-file "$tasks_path" --archive-file "$archive_path" --now "2026-05-16T00:00:00Z" >/dev/null

  assert_task_present "$archive_path" "T-OLD" || fail "existing archive task should remain"
  assert_task_present "$archive_path" "T-DONE" || fail "new task should append to archive"
  rm -rf "$tmp_dir"
}

test_threshold_days_moves_only_old_terminal_tasks() {
  local tmp_dir tasks_path archive_path stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-archive-tasks.XXXXXX")
  tasks_path="$tmp_dir/TASKS.yaml"
  archive_path="$tmp_dir/TASKS_ARCHIVE.yaml"
  stdout_path="$tmp_dir/stdout.log"
  cat > "$tasks_path" <<'YAML'
tasks:
  - id: T-OLD-DONE
    title: "Old Done"
    status: done
    completed_at: "2026-04-01T00:00:00Z"
  - id: T-RECENT-DONE
    title: "Recent Done"
    status: done
    completed_at: "2026-05-10T00:00:00Z"
  - id: T-NO-DATE
    title: "No Date"
    status: cancelled
YAML

  "$ARCHIVER" \
    --threshold-days 30 \
    --now "2026-05-16T00:00:00Z" \
    --tasks-file "$tasks_path" \
    --archive-file "$archive_path" \
    >"$stdout_path"

  assert_task_present "$archive_path" "T-OLD-DONE" || fail "old terminal task should be archived"
  assert_task_present "$tasks_path" "T-RECENT-DONE" || fail "recent terminal task should remain"
  assert_task_present "$tasks_path" "T-NO-DATE" || fail "undated task should remain when threshold is set"
  assert_contains "$stdout_path" "archived 1 task(s)" "threshold archive should report moved count"
  rm -rf "$tmp_dir"
}

test_archive_atomic_write_replaces_tasks_file() {
  local tmp_dir tasks_path archive_path before_inode after_inode
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-archive-tasks.XXXXXX")
  tasks_path="$tmp_dir/TASKS.yaml"
  archive_path="$tmp_dir/TASKS_ARCHIVE.yaml"
  cat > "$tasks_path" <<'YAML'
tasks:
  - id: T-DONE
    title: "Done"
    status: done
YAML
  before_inode=$(file_inode "$tasks_path")

  "$ARCHIVER" --tasks-file "$tasks_path" --archive-file "$archive_path" --now "2026-05-16T00:00:00Z" >/dev/null
  after_inode=$(file_inode "$tasks_path")

  [ "$before_inode" != "$after_inode" ] || fail "archive should atomically replace TASKS.yaml"
  rm -rf "$tmp_dir"
}

test_validate_passes_after_archive() {
  local tmp_dir tasks_path archive_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-archive-tasks.XXXXXX")
  tasks_path="$tmp_dir/TASKS.yaml"
  archive_path="$tmp_dir/TASKS_ARCHIVE.yaml"
  write_tasks_fixture "$tasks_path"

  "$ARCHIVER" --tasks-file "$tasks_path" --archive-file "$archive_path" --now "2026-05-16T00:00:00Z" >/dev/null

  "$VALIDATOR" "$tasks_path"
  "$VALIDATOR" "$archive_path"
  rm -rf "$tmp_dir"
}

test_rejects_invalid_source_without_writing_archive() {
  local tmp_dir tasks_path archive_path stderr_path status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-archive-tasks.XXXXXX")
  tasks_path="$tmp_dir/TASKS.yaml"
  archive_path="$tmp_dir/TASKS_ARCHIVE.yaml"
  stderr_path="$tmp_dir/stderr.log"
  cat > "$tasks_path" <<'YAML'
tasks:
  - id: T-BAD
    title: "Bad"
    status: done
    status: cancelled
YAML

  set +e
  "$ARCHIVER" --tasks-file "$tasks_path" --archive-file "$archive_path" 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 1 ] || fail "invalid source should fail"
  assert_contains "$stderr_path" "source TASKS yaml failed validation" "invalid source should explain validation error"
  [ ! -e "$archive_path" ] || fail "invalid source should not write archive"
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
      run_test test_dry_run_lists_terminal_tasks_only
      run_test test_archive_moves_done_task_to_archive
      run_test test_archive_appends_to_existing_archive
      run_test test_threshold_days_moves_only_old_terminal_tasks
      run_test test_archive_atomic_write_replaces_tasks_file
      run_test test_validate_passes_after_archive
      run_test test_rejects_invalid_source_without_writing_archive
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'archive tasks tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
