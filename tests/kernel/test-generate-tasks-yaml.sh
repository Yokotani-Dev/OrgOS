#!/usr/bin/env bash
# TASKS.generated.yaml generator tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
GENERATOR=${GENERATOR:-"$REPO_ROOT/scripts/org/generate-tasks-yaml.py"}
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

create_tasks_db() {
  local db_path="$1"
  python3 - "$db_path" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.executescript(
    """
    CREATE TABLE tasks (
      id TEXT PRIMARY KEY,
      project_id TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT,
      status TEXT NOT NULL,
      priority INTEGER NOT NULL DEFAULT 50,
      risk_level TEXT NOT NULL DEFAULT 'normal',
      allowed_paths_json TEXT,
      deps_json TEXT,
      source TEXT NOT NULL DEFAULT 'yaml_import',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE events (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      event_id TEXT UNIQUE NOT NULL,
      ts TEXT NOT NULL,
      project_id TEXT,
      task_id TEXT,
      actor TEXT NOT NULL,
      type TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      prev_hash TEXT,
      hash TEXT
    );
    """
)
conn.execute(
    """
    INSERT INTO tasks (
      id, project_id, title, description, status, priority, risk_level,
      allowed_paths_json, deps_json, source, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """,
    (
        "T-ONE",
        "orgos",
        "First task",
        "Imported from SQLite",
        "queued",
        10,
        "low",
        '["scripts/org/generate-tasks-yaml.py", "tests/kernel/"]',
        '["T-ZERO"]',
        "test",
        "2026-05-16T00:00:00Z",
        "2026-05-16T01:00:00Z",
    ),
)
conn.execute(
    """
    INSERT INTO tasks (
      id, project_id, title, status, priority, risk_level,
      allowed_paths_json, deps_json, source, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """,
    (
        "T-TWO",
        "orgos",
        "Second task",
        "running",
        20,
        "normal",
        "[]",
        "[]",
        "test",
        "2026-05-16T02:00:00Z",
        "2026-05-16T03:00:00Z",
    ),
)
for seq in range(1, 4):
    conn.execute(
        """
        INSERT INTO events (
          event_id, ts, project_id, task_id, actor, type, payload_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (f"E-{seq}", "2026-05-16T00:00:00Z", "orgos", "T-ONE", "test", "TaskUpdated", "{}"),
    )
conn.commit()
PY
}

assert_yaml_expr() {
  local path="$1"
  local expr="$2"
  python3 - "$path" "$expr" <<'PY'
import sys
import yaml

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle)

if not eval(sys.argv[2], {"data": data}):
    raise SystemExit(1)
PY
}

assert_generated_sha_matches_payload() {
  local path="$1"
  python3 - "$path" <<'PY'
import hashlib
import json
import sys
import yaml

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle)

payload = {
    "source_event_seq": data["source_event_seq"],
    "tasks": data["tasks"],
}
digest = hashlib.sha256(
    json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
).hexdigest()
if data["sha256"] != digest:
    raise SystemExit(1)
PY
}

test_generator_writes_generated_yaml_without_touching_legacy_tasks() {
  local tmp_dir db_path output_path legacy_path before_hash after_hash
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-generate-tasks-yaml.XXXXXX")
  db_path="$tmp_dir/orgos.sqlite"
  output_path="$tmp_dir/TASKS.generated.yaml"
  legacy_path="$tmp_dir/TASKS.yaml"
  create_tasks_db "$db_path"
  cat > "$legacy_path" <<'YAML'
tasks:
  - id: T-LEGACY
    title: "Legacy"
    status: queued
YAML
  before_hash=$(shasum -a 256 "$legacy_path" | awk '{print $1}')

  "$GENERATOR" --db "$db_path" --output "$output_path" --generated-at "2026-05-16T00:00:00Z" >/dev/null
  after_hash=$(shasum -a 256 "$legacy_path" | awk '{print $1}')

  [ "$before_hash" = "$after_hash" ] || fail "legacy TASKS.yaml should not be modified"
  "$VALIDATOR" "$output_path"
  assert_yaml_expr "$output_path" 'data["ORGOS-GENERATED"] is True'
  assert_yaml_expr "$output_path" 'len(data["tasks"]) == 2'
  assert_yaml_expr "$output_path" 'data["tasks"][0]["id"] == "T-ONE"'
  assert_contains "$output_path" "generated_at: '2026-05-16T00:00:00Z'" "generated_at header"
  rm -rf "$tmp_dir"
}

test_generator_uses_latest_event_seq_and_payload_sha() {
  local tmp_dir db_path output_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-generate-tasks-yaml.XXXXXX")
  db_path="$tmp_dir/orgos.sqlite"
  output_path="$tmp_dir/TASKS.generated.yaml"
  create_tasks_db "$db_path"

  "$GENERATOR" --db "$db_path" --output "$output_path" --generated-at "2026-05-16T00:00:00Z" >/dev/null

  assert_yaml_expr "$output_path" 'data["source_event_seq"] == 3'
  assert_generated_sha_matches_payload "$output_path"
  rm -rf "$tmp_dir"
}

test_generator_projects_json_columns_to_yaml_fields() {
  local tmp_dir db_path output_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-generate-tasks-yaml.XXXXXX")
  db_path="$tmp_dir/orgos.sqlite"
  output_path="$tmp_dir/TASKS.generated.yaml"
  create_tasks_db "$db_path"

  "$GENERATOR" --db "$db_path" --output "$output_path" --generated-at "2026-05-16T00:00:00Z" >/dev/null

  assert_yaml_expr "$output_path" 'data["tasks"][0]["allowed_paths"] == ["scripts/org/generate-tasks-yaml.py", "tests/kernel/"]'
  assert_yaml_expr "$output_path" 'data["tasks"][0]["deps"] == ["T-ZERO"]'
  assert_yaml_expr "$output_path" 'data["tasks"][1]["allowed_paths"] == []'
  rm -rf "$tmp_dir"
}

test_generator_rejects_invalid_json_columns() {
  local tmp_dir db_path output_path stderr_path status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-generate-tasks-yaml.XXXXXX")
  db_path="$tmp_dir/orgos.sqlite"
  output_path="$tmp_dir/TASKS.generated.yaml"
  stderr_path="$tmp_dir/stderr.log"
  create_tasks_db "$db_path"
  python3 - "$db_path" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute("UPDATE tasks SET allowed_paths_json = ? WHERE id = ?", ("[broken", "T-ONE"))
conn.commit()
PY

  set +e
  "$GENERATOR" --db "$db_path" --output "$output_path" 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 1 ] || fail "invalid JSON should exit 1"
  [ ! -e "$output_path" ] || fail "invalid JSON should not write output"
  assert_contains "$stderr_path" "invalid JSON in tasks.allowed_paths_json for T-ONE" "invalid JSON should identify task and column"
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
      run_test test_generator_writes_generated_yaml_without_touching_legacy_tasks
      run_test test_generator_uses_latest_event_seq_and_payload_sha
      run_test test_generator_projects_json_columns_to_yaml_fields
      run_test test_generator_rejects_invalid_json_columns
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf '# generate-tasks-yaml tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
