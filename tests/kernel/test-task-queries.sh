#!/usr/bin/env bash
# SQLite-backed task query CLI tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
LIST_TASKS=${LIST_TASKS:-"$REPO_ROOT/scripts/org/list-tasks-sqlite.py"}
SHOW_TASK=${SHOW_TASK:-"$REPO_ROOT/scripts/org/show-task.py"}

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

assert_not_contains() {
  local path="$1"
  local needle="$2"
  local msg="$3"
  if grep -Fq "$needle" "$path"; then
    fail "$msg: did not expect '$needle' in $path"
  fi
}

write_tasks_db() {
  local db_path="$1"
  python3 - "$db_path" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
connection = sqlite3.connect(db_path)
connection.execute(
    """
    CREATE TABLE tasks (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      status TEXT NOT NULL,
      priority TEXT,
      owner_role TEXT,
      notes TEXT,
      updated_at TEXT
    )
    """
)
connection.executemany(
    "INSERT INTO tasks (id, title, status, priority, owner_role, notes, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
    [
        ("T-ONE", "First task", "queued", "P1", "codex-implementer", "needs sqlite list", "2026-05-16T00:00:00Z"),
        ("T-THREE", "Third task", "queued", "P3", "manager", "later", "2026-05-16T02:00:00Z"),
        ("T-TWO", "Second task", "running", "P2", "codex-reviewer", "show details", "2026-05-16T01:00:00Z"),
    ],
)
connection.commit()
connection.close()
PY
}

assert_json_value() {
  local path="$1"
  local expr="$2"
  python3 - "$path" "$expr" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
if not eval(sys.argv[2], {"data": data}):
    raise SystemExit(1)
PY
}

test_list_markdown_filters_by_status() {
  local tmp_dir db_path stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-task-queries.XXXXXX")
  db_path="$tmp_dir/tasks.sqlite"
  stdout_path="$tmp_dir/stdout.md"
  write_tasks_db "$db_path"

  "$LIST_TASKS" --db "$db_path" --status queued >"$stdout_path"

  assert_contains "$stdout_path" "| ID | Status | Priority | Title |" "markdown list should include a header"
  assert_contains "$stdout_path" "T-ONE" "queued task should be listed"
  assert_contains "$stdout_path" "T-THREE" "second queued task should be listed"
  assert_not_contains "$stdout_path" "T-TWO" "non-matching status should be filtered out"
  rm -rf "$tmp_dir"
}

test_list_json_honors_limit() {
  local tmp_dir db_path stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-task-queries.XXXXXX")
  db_path="$tmp_dir/tasks.sqlite"
  stdout_path="$tmp_dir/stdout.json"
  write_tasks_db "$db_path"

  "$LIST_TASKS" --db "$db_path" --limit 2 --format json >"$stdout_path"

  assert_json_value "$stdout_path" 'data["count"] == 2'
  assert_json_value "$stdout_path" '[task["id"] for task in data["tasks"]] == ["T-ONE", "T-THREE"]'
  rm -rf "$tmp_dir"
}

test_show_task_markdown_includes_details() {
  local tmp_dir db_path stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-task-queries.XXXXXX")
  db_path="$tmp_dir/tasks.sqlite"
  stdout_path="$tmp_dir/stdout.md"
  write_tasks_db "$db_path"

  "$SHOW_TASK" --db "$db_path" T-TWO >"$stdout_path"

  assert_contains "$stdout_path" "# T-TWO: Second task" "task detail should include heading"
  assert_contains "$stdout_path" "| status | running |" "task detail should include status"
  assert_contains "$stdout_path" "| notes | show details |" "task detail should include notes"
  rm -rf "$tmp_dir"
}

test_show_task_json() {
  local tmp_dir db_path stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-task-queries.XXXXXX")
  db_path="$tmp_dir/tasks.sqlite"
  stdout_path="$tmp_dir/stdout.json"
  write_tasks_db "$db_path"

  "$SHOW_TASK" --db "$db_path" --format json T-ONE >"$stdout_path"

  assert_json_value "$stdout_path" 'data["task"]["id"] == "T-ONE"'
  assert_json_value "$stdout_path" 'data["task"]["owner_role"] == "codex-implementer"'
  rm -rf "$tmp_dir"
}

test_show_task_missing_exits_nonzero() {
  local tmp_dir db_path stderr_path status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-task-queries.XXXXXX")
  db_path="$tmp_dir/tasks.sqlite"
  stderr_path="$tmp_dir/stderr.log"
  write_tasks_db "$db_path"

  set +e
  "$SHOW_TASK" --db "$db_path" T-MISSING 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 1 ] || fail "missing task should exit 1"
  assert_contains "$stderr_path" "task not found: T-MISSING" "missing task should explain failure"
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
      run_test test_list_markdown_filters_by_status
      run_test test_list_json_honors_limit
      run_test test_show_task_markdown_includes_details
      run_test test_show_task_json
      run_test test_show_task_missing_exits_nonzero
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'task query tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
