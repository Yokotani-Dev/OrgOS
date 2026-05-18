#!/usr/bin/env bash
# SQLite schema initialization regression tests.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
INIT_SQLITE=${INIT_SQLITE:-"$REPO_ROOT/scripts/org/init-sqlite.py"}
SCHEMA_PATH=${SCHEMA_PATH:-"$REPO_ROOT/.claude/schemas/orgos.sqlite.schema.sql"}

pass_count=0
fail_count=0
current_test_failed=0

EXPECTED_TABLES=(
  projects
  tasks
  workers
  leases
  runs
  approvals
  artifacts
  integrations
  events
  view_checksums
)

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
  return 1
}

query_sqlite() {
  local db_path="$1"
  local sql="$2"
  python3 - "$db_path" "$sql" <<'PY'
import sqlite3
import sys

db_path, sql = sys.argv[1:3]
connection = sqlite3.connect(db_path)
try:
    row = connection.execute(sql).fetchone()
finally:
    connection.close()
if row is not None:
    print(row[0])
PY
}

make_db_path() {
  local tmp_dir="$1"
  printf '%s/orgos.sqlite' "$tmp_dir"
}

test_schema_file_applies_cleanly() {
  local tmp_dir db_path table_count
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-sqlite-schema.XXXXXX")
  db_path=$(make_db_path "$tmp_dir")

  "$INIT_SQLITE" --db-path "$db_path" --schema "$SCHEMA_PATH" >/dev/null
  table_count=$(query_sqlite "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")

  [ "$table_count" -eq "${#EXPECTED_TABLES[@]}" ] || fail "schema should create ${#EXPECTED_TABLES[@]} tables, got $table_count"
  rm -rf "$tmp_dir"
}

test_expected_tables_exist() {
  local tmp_dir db_path table_name exists
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-sqlite-tables.XXXXXX")
  db_path=$(make_db_path "$tmp_dir")

  "$INIT_SQLITE" --db-path "$db_path" --schema "$SCHEMA_PATH" >/dev/null
  for table_name in "${EXPECTED_TABLES[@]}"; do
    exists=$(query_sqlite "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table_name'")
    [ "$exists" -eq 1 ] || fail "missing table: $table_name"
  done

  rm -rf "$tmp_dir"
}

test_wal_mode_enabled() {
  local tmp_dir db_path journal_mode
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-sqlite-wal.XXXXXX")
  db_path=$(make_db_path "$tmp_dir")

  "$INIT_SQLITE" --db-path "$db_path" --schema "$SCHEMA_PATH" >/dev/null
  journal_mode=$(query_sqlite "$db_path" "PRAGMA journal_mode")

  [ "$journal_mode" = "wal" ] || fail "journal_mode should be wal, got $journal_mode"
  rm -rf "$tmp_dir"
}

test_force_recreates_database() {
  local tmp_dir db_path task_count
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-sqlite-force.XXXXXX")
  db_path=$(make_db_path "$tmp_dir")

  "$INIT_SQLITE" --db-path "$db_path" --schema "$SCHEMA_PATH" >/dev/null
  python3 - "$db_path" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
connection.execute("INSERT INTO tasks (id, title) VALUES ('T-test', 'temporary task')")
connection.commit()
connection.close()
PY
  "$INIT_SQLITE" --db-path "$db_path" --schema "$SCHEMA_PATH" --force >/dev/null
  task_count=$(query_sqlite "$db_path" "SELECT COUNT(*) FROM tasks")

  [ "$task_count" -eq 0 ] || fail "--force should recreate an empty database"
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
      run_test test_schema_file_applies_cleanly
      run_test test_expected_tables_exist
      run_test test_wal_mode_enabled
      run_test test_force_recreates_database
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf '# sqlite-schema tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
