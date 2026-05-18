#!/usr/bin/env bash
# TASKS.yaml shadow SQLite importer tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
IMPORTER=${IMPORTER:-"$REPO_ROOT/scripts/org/import-tasks-yaml.py"}

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

write_tasks_fixture() {
  local path="$1"
  cat > "$path" <<'YAML'
tasks:
  - id: T-ONE
    title: "One"
    status: queued
    priority: P1
    allowed_paths:
      - "scripts/org/import-tasks-yaml.py"
    notes: "first note"
  - id: T-TWO
    title: "Two"
    status: running
    priority: P2
    allowed_paths:
      - "tests/kernel/"
  - id: T-DONE
    title: "Done"
    status: done
    priority: P3
YAML
}

test_dry_run_does_not_create_db() {
  local tmp_dir tasks_path db_path stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-import-tasks.XXXXXX")
  tasks_path="$tmp_dir/TASKS.yaml"
  db_path="$tmp_dir/tasks.sqlite3"
  stdout_path="$tmp_dir/stdout.log"
  write_tasks_fixture "$tasks_path"

  "$IMPORTER" --dry-run --tasks-file "$tasks_path" --db-file "$db_path" >"$stdout_path"

  assert_contains "$stdout_path" "dry-run: would import 3 task(s)" "dry run should report import count"
  assert_contains "$stdout_path" "active_count yaml=2 sqlite_after=2" "dry run should report hypothetical active count"
  [ ! -e "$db_path" ] || fail "dry run should not create SQLite DB"
  rm -rf "$tmp_dir"
}

test_import_populates_tasks_table() {
  local tmp_dir tasks_path db_path stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-import-tasks.XXXXXX")
  tasks_path="$tmp_dir/TASKS.yaml"
  db_path="$tmp_dir/tasks.sqlite3"
  stdout_path="$tmp_dir/stdout.log"
  write_tasks_fixture "$tasks_path"

  "$IMPORTER" --tasks-file "$tasks_path" --db-file "$db_path" >"$stdout_path"

  assert_contains "$stdout_path" "imported 3 task(s)" "import should report row count"
  assert_contains "$stdout_path" "active_count yaml=2 sqlite=2" "import should compare active counts"
  python3 - "$db_path" <<'PY'
import json
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
rows = conn.execute(
    "SELECT id, status, priority, allowed_paths, notes FROM tasks ORDER BY id"
).fetchall()
assert len(rows) == 3, rows
by_id = {row[0]: row for row in rows}
assert by_id["T-ONE"][1] == "queued"
assert by_id["T-ONE"][2] == "P1"
assert json.loads(by_id["T-ONE"][3]) == ["scripts/org/import-tasks-yaml.py"]
assert by_id["T-ONE"][4] == "first note"
assert json.loads(by_id["T-DONE"][3]) == []
PY
  rm -rf "$tmp_dir"
}

test_diff_with_existing_reports_added_removed_modified() {
  local tmp_dir tasks_path db_path stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-import-tasks.XXXXXX")
  tasks_path="$tmp_dir/TASKS.yaml"
  db_path="$tmp_dir/tasks.sqlite3"
  stdout_path="$tmp_dir/stdout.log"
  cat > "$tasks_path" <<'YAML'
tasks:
  - id: T-ONE
    title: "One"
    status: queued
    priority: P0
    allowed_paths:
      - "scripts/org/import-tasks-yaml.py"
  - id: T-TWO
    title: "Two"
    status: running
YAML
  python3 - "$db_path" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute(
    """
    CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        title TEXT,
        status TEXT NOT NULL,
        priority TEXT,
        allowed_paths TEXT NOT NULL,
        notes TEXT,
        source_json TEXT NOT NULL
    )
    """
)
conn.execute(
    "INSERT INTO tasks (id, title, status, priority, allowed_paths, notes, source_json) VALUES (?, ?, ?, ?, ?, ?, ?)",
    ("T-ONE", "One", "queued", "P1", '["scripts/org/import-tasks-yaml.py"]', None, "{}"),
)
conn.execute(
    "INSERT INTO tasks (id, title, status, priority, allowed_paths, notes, source_json) VALUES (?, ?, ?, ?, ?, ?, ?)",
    ("T-OLD", "Old", "done", "P3", "[]", None, "{}"),
)
conn.commit()
PY

  "$IMPORTER" \
    --dry-run \
    --diff-with-existing \
    --tasks-file "$tasks_path" \
    --db-file "$db_path" \
    >"$stdout_path"

  assert_contains "$stdout_path" "diff added=1 removed=1 modified=1" "diff should summarize changes"
  assert_contains "$stdout_path" "added: T-TWO" "diff should list added task"
  assert_contains "$stdout_path" "removed: T-OLD" "diff should list removed task"
  assert_contains "$stdout_path" "modified: T-ONE" "diff should list modified task"
  rm -rf "$tmp_dir"
}

test_warns_when_imported_active_count_differs() {
  local tmp_dir tasks_path db_path stderr_path stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-import-tasks.XXXXXX")
  tasks_path="$tmp_dir/TASKS.yaml"
  db_path="$tmp_dir/tasks.sqlite3"
  stderr_path="$tmp_dir/stderr.log"
  stdout_path="$tmp_dir/stdout.log"
  write_tasks_fixture "$tasks_path"
  python3 - "$db_path" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute(
    """
    CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        title TEXT,
        status TEXT NOT NULL,
        priority TEXT,
        allowed_paths TEXT NOT NULL,
        notes TEXT,
        source_json TEXT NOT NULL,
        imported_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
    """
)
conn.execute(
    """
    CREATE TRIGGER force_one_inactive
    AFTER INSERT ON tasks
    WHEN NEW.id = 'T-TWO'
    BEGIN
        UPDATE tasks SET status = 'done' WHERE id = NEW.id;
    END
    """
)
conn.commit()
PY

  "$IMPORTER" --tasks-file "$tasks_path" --db-file "$db_path" >"$stdout_path" 2>"$stderr_path"

  assert_contains "$stdout_path" "active_count yaml=2 sqlite=1" "import should show mismatched counts"
  assert_contains "$stderr_path" "WARNING: active count mismatch yaml=2 sqlite=1" "import should warn on mismatch"
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
      run_test test_dry_run_does_not_create_db
      run_test test_import_populates_tasks_table
      run_test test_diff_with_existing_reports_added_removed_modified
      run_test test_warns_when_imported_active_count_differs
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'import tasks tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
