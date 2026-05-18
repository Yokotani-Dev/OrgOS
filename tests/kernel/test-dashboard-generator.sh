#!/usr/bin/env bash
# SQLite dashboard generator regression tests.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
DASHBOARD_GENERATOR=${DASHBOARD_GENERATOR:-"$REPO_ROOT/scripts/org/generate-dashboard.py"}

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
    fail "$msg: did not expect '$needle' in $path"
  fi
}

assert_equal() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  [ "$actual" = "$expected" ] || fail "$msg: expected '$expected', got '$actual'"
}

make_basic_db() {
  local db_path="$1"
  python3 - "$db_path" <<'PY'
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
db.executescript(
    """
    CREATE TABLE events(seq INTEGER PRIMARY KEY, event_type TEXT, created_at TEXT);
    INSERT INTO events(seq, event_type, created_at) VALUES
      (40, 'milestone.updated', '2026-05-16T00:00:00Z'),
      (41, 'task.queued', '2026-05-16T00:01:00Z'),
      (42, 'kernel.mode.set', '2026-05-16T00:02:00Z');

    CREATE TABLE milestones(
      id TEXT PRIMARY KEY,
      title TEXT,
      status TEXT,
      target_date TEXT,
      source_event_seq INTEGER
    );
    INSERT INTO milestones VALUES
      ('M-ACTIVE', 'Active Work', 'active', '2026-06-01', 40),
      ('M-DONE', 'Completed Work', 'achieved', '2026-05-01', 39);

    CREATE TABLE tasks(
      id TEXT PRIMARY KEY,
      title TEXT,
      status TEXT,
      priority TEXT,
      owner_role TEXT,
      updated_at TEXT,
      source_event_seq INTEGER
    );
    INSERT INTO tasks VALUES
      ('T-ONE', 'Queued task', 'queued', 'P0', 'codex-implementer', '2026-05-16T00:01:00Z', 41),
      ('T-TWO', 'Running task', 'running', 'P1', 'manager', '2026-05-16T00:02:00Z', 42),
      ('T-DONE', 'Done task', 'done', 'P0', 'manager', '2026-05-15T00:00:00Z', 30);

    CREATE TABLE decisions(
      id TEXT PRIMARY KEY,
      title TEXT,
      status TEXT,
      decided_at TEXT,
      source_event_seq INTEGER
    );
    INSERT INTO decisions VALUES
      ('D-2', 'Second decision', 'accepted', '2026-05-16T03:00:00Z', 42),
      ('D-1', 'First decision', 'accepted', '2026-05-15T03:00:00Z', 41);

    CREATE TABLE kernel_mode(
      mode TEXT,
      updated_at TEXT,
      source_event_seq INTEGER,
      invariants TEXT
    );
    INSERT INTO kernel_mode VALUES
      ('warn', '2026-05-16T00:02:00Z', 42, '{"IntegratorOnlyCommit":"enforce","LeaseBeforeWrite":"warn"}');
    """
)
db.commit()
db.close()
PY
}

make_payload_db() {
  local db_path="$1"
  python3 - "$db_path" <<'PY'
import json
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
db.executescript(
    """
    CREATE TABLE events(seq INTEGER PRIMARY KEY);
    INSERT INTO events(seq) VALUES (7);
    CREATE TABLE milestones(payload TEXT);
    CREATE TABLE tasks(payload TEXT);
    CREATE TABLE decisions(payload TEXT);
    CREATE TABLE state(key TEXT, value TEXT, updated_at TEXT, source_event_seq INTEGER);
    """
)
db.execute(
    "INSERT INTO milestones(payload) VALUES (?)",
    (json.dumps({"id": "M-PAYLOAD", "title": "Payload Milestone", "status": "active"}),),
)
db.execute(
    "INSERT INTO tasks(payload) VALUES (?)",
    (json.dumps({"id": "T-PAYLOAD", "title": "Payload Task", "status": "queued", "priority": "P1"}),),
)
db.execute(
    "INSERT INTO decisions(payload) VALUES (?)",
    (json.dumps({"id": "D-PAYLOAD", "decision": "Payload Decision", "status": "accepted", "created_at": "2026-05-16T00:00:00Z"}),),
)
db.execute(
    "INSERT INTO state(key, value, updated_at, source_event_seq) VALUES (?, ?, ?, ?)",
    (
        "kernel_mode",
        json.dumps({"mode": "enforce", "invariants": {"StateMutationViaOrgTool": "enforce"}}),
        "2026-05-16T01:00:00Z",
        7,
    ),
)
db.commit()
db.close()
PY
}

test_script_is_executable() {
  [ -x "$DASHBOARD_GENERATOR" ] || fail "dashboard generator should be executable"
}

test_generates_header_and_sections_from_sqlite() {
  local tmp_dir db output checksum expected
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-dashboard.XXXXXX")
  db="$tmp_dir/orgos.sqlite"
  output="$tmp_dir/DASHBOARD.generated.md"
  make_basic_db "$db"

  "$DASHBOARD_GENERATOR" --db "$db" --output "$output" >/dev/null

  assert_contains "$output" "source_event_seq: 42" "source event seq header"
  assert_contains "$output" "checksum_sha256:" "checksum header"
  assert_contains "$output" "## Active Milestones" "active milestones section"
  assert_contains "$output" "| M-ACTIVE | Active Work | 2026-06-01 | active |" "active milestone row"
  assert_not_contains "$output" "M-DONE" "achieved milestone should be excluded"
  assert_contains "$output" "| T-ONE | queued | P0 | Queued task | codex-implementer |" "queued task row"
  assert_contains "$output" "| T-TWO | running | P1 | Running task | manager |" "running task row"
  assert_not_contains "$output" "T-DONE" "done task should be excluded"
  assert_contains "$output" "| D-2 | 2026-05-16T03:00:00Z | Second decision | accepted |" "recent decision row"
  assert_contains "$output" "| warn | 2026-05-16T00:02:00Z | 42 | IntegratorOnlyCommit |" "kernel mode row"

  checksum=$(awk '/^checksum_sha256:/ {print $2}' "$output")
  expected=$(python3 - "$output" <<'PY'
import hashlib
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
body = text.split("---\n", 2)[2]
print(hashlib.sha256(body.encode("utf-8")).hexdigest())
PY
)
  assert_equal "$checksum" "$expected" "checksum should cover generated body"
  rm -rf "$tmp_dir"
}

test_shadow_output_does_not_replace_legacy_dashboard_and_limits_tasks() {
  local tmp_dir repo db output legacy count
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-dashboard.XXXXXX")
  repo="$tmp_dir/repo"
  mkdir -p "$repo/.ai"
  db="$repo/.ai/orgos.sqlite"
  output="$repo/.ai/DASHBOARD.generated.md"
  legacy="$repo/.ai/DASHBOARD.md"
  printf 'legacy dashboard\n' > "$legacy"

  python3 - "$db" <<'PY'
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
db.execute("CREATE TABLE events(seq INTEGER PRIMARY KEY)")
db.execute("INSERT INTO events(seq) VALUES (100)")
db.execute("CREATE TABLE tasks(id TEXT, title TEXT, status TEXT, priority TEXT, updated_at TEXT)")
for i in range(12):
    db.execute(
        "INSERT INTO tasks VALUES (?, ?, 'queued', 'P0', ?)",
        (f"T-LIMIT-{i:02d}", f"Task {i:02d}", f"2026-05-16T00:{i:02d}:00Z"),
    )
db.commit()
db.close()
PY

  "$DASHBOARD_GENERATOR" --repo-root "$repo" >/dev/null

  assert_equal "$(cat "$legacy")" "legacy dashboard" "legacy DASHBOARD.md should remain unchanged"
  [ -s "$output" ] || fail "shadow dashboard should be generated"
  count=$(grep -c '^| T-LIMIT-' "$output")
  assert_equal "$count" "10" "queued/running task table should be capped at top 10"
  rm -rf "$tmp_dir"
}

test_payload_json_projection_rows_are_supported() {
  local tmp_dir db output
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-dashboard.XXXXXX")
  db="$tmp_dir/orgos.sqlite"
  output="$tmp_dir/DASHBOARD.generated.md"
  make_payload_db "$db"

  "$DASHBOARD_GENERATOR" --db "$db" --output "$output" >/dev/null

  assert_contains "$output" "source_event_seq: 7" "payload fixture source seq"
  assert_contains "$output" "M-PAYLOAD" "payload milestone"
  assert_contains "$output" "T-PAYLOAD" "payload task"
  assert_contains "$output" "Payload Decision" "payload decision"
  assert_contains "$output" "| enforce | 2026-05-16T01:00:00Z | 7 | StateMutationViaOrgTool |" "state table kernel mode"
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
      run_test test_script_is_executable
      run_test test_generates_header_and_sections_from_sqlite
      run_test test_shadow_output_does_not_replace_legacy_dashboard_and_limits_tasks
      run_test test_payload_json_projection_rows_are_supported
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf '# dashboard-generator tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
