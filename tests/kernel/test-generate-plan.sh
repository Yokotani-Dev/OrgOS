#!/usr/bin/env bash
# Plan generator regression tests.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
GENERATOR=${GENERATOR:-"$REPO_ROOT/scripts/org/generate-plan.py"}

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

assert_not_exists() {
  local path="$1"
  local msg="$2"
  [ ! -e "$path" ] || fail "$msg: $path should not exist"
}

setup_fixture_repo() {
  local repo="$1"
  mkdir -p "$repo/.ai/CODEX/ORDERS" "$repo/.ai/plans" "$repo/.claude/schemas"
  cat > "$repo/.claude/schemas/plan-contract.v1.json" <<'EOF_SCHEMA'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "orgos.plan_contract.v1",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "task_id", "title", "acceptance", "allowed_paths", "verification"],
  "properties": {
    "schema_version": {"type": "string", "const": "orgos.plan_contract.v1"},
    "task_id": {"type": "string", "pattern": "^T-[A-Z0-9-]+$"},
    "title": {"type": "string", "minLength": 1},
    "acceptance": {"type": "array", "minItems": 1, "items": {"type": "string", "minLength": 1}},
    "allowed_paths": {"type": "array", "minItems": 1, "items": {"type": "string", "minLength": 1}},
    "verification": {"type": "array", "minItems": 1, "items": {"type": "string", "minLength": 1}}
  }
}
EOF_SCHEMA
}

write_valid_order() {
  local path="$1"
  cat > "$path" <<'EOF_ORDER'
# Codex Work Order — T-OS-999: Generate sample plan

## Background

Fixture content.

## Allowed Paths

- `scripts/org/generate-plan.py`
- tests/kernel/test-generate-plan.sh

## Acceptance

- Generator creates a plan
- Schema validation passes
EOF_ORDER
}

write_order_without_acceptance() {
  local path="$1"
  cat > "$path" <<'EOF_ORDER'
# Codex Work Order — T-OS-999: Missing acceptance

## Allowed Paths

- scripts/org/generate-plan.py
EOF_ORDER
}

write_order_without_allowed_paths() {
  local path="$1"
  cat > "$path" <<'EOF_ORDER'
# Codex Work Order — T-OS-999: Missing allowed paths

## Acceptance

- Generator fails
EOF_ORDER
}

test_generator_script_is_executable() {
  [ -x "$GENERATOR" ] || fail "generator should be executable"
}

test_generates_plan_and_passes_schema() {
  local tmp_dir repo output_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-generate-plan.XXXXXX")
  repo="$tmp_dir/repo"
  setup_fixture_repo "$repo"
  write_valid_order "$repo/.ai/CODEX/ORDERS/T-OS-999.md"

  "$GENERATOR" --repo-root "$repo" T-OS-999 >/dev/null
  output_path="$repo/.ai/plans/T-OS-999.plan.yaml"

  assert_contains "$output_path" "schema_version: orgos.plan_contract.v1" "plan schema version"
  assert_contains "$output_path" "task_id: T-OS-999" "plan task id"
  assert_contains "$output_path" "title: Generate sample plan" "plan title"
  assert_contains "$output_path" "bash tests/kernel/run-kernel-tests.sh" "default verification"

  python3 - "$repo" "$output_path" <<'PY'
import json
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

repo = Path(sys.argv[1])
output_path = Path(sys.argv[2])
schema = json.loads((repo / ".claude/schemas/plan-contract.v1.json").read_text())
data = yaml.safe_load(output_path.read_text())
errors = list(Draft202012Validator(schema).iter_errors(data))
assert not errors, errors
assert data["allowed_paths"] == ["scripts/org/generate-plan.py", "tests/kernel/test-generate-plan.sh"]
assert data["acceptance"] == ["Generator creates a plan", "Schema validation passes"]
PY
  rm -rf "$tmp_dir"
}

test_missing_acceptance_fails() {
  local tmp_dir repo status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-generate-plan.XXXXXX")
  repo="$tmp_dir/repo"
  setup_fixture_repo "$repo"
  write_order_without_acceptance "$repo/.ai/CODEX/ORDERS/T-OS-999.md"

  set +e
  "$GENERATOR" --repo-root "$repo" T-OS-999 >/dev/null 2>"$tmp_dir/stderr"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "missing Acceptance section should fail"
  assert_contains "$tmp_dir/stderr" 'missing "## Acceptance" section' "missing acceptance error"
  assert_not_exists "$repo/.ai/plans/T-OS-999.plan.yaml" "missing acceptance output"
  rm -rf "$tmp_dir"
}

test_missing_allowed_paths_fails() {
  local tmp_dir repo status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-generate-plan.XXXXXX")
  repo="$tmp_dir/repo"
  setup_fixture_repo "$repo"
  write_order_without_allowed_paths "$repo/.ai/CODEX/ORDERS/T-OS-999.md"

  set +e
  "$GENERATOR" --repo-root "$repo" T-OS-999 >/dev/null 2>"$tmp_dir/stderr"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "missing Allowed Paths section should fail"
  assert_contains "$tmp_dir/stderr" 'missing "## Allowed Paths" section' "missing allowed paths error"
  assert_not_exists "$repo/.ai/plans/T-OS-999.plan.yaml" "missing allowed paths output"
  rm -rf "$tmp_dir"
}

test_atomic_write_preserves_existing_output_on_validation_failure() {
  local tmp_dir repo output_path before_hash after_hash status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-generate-plan.XXXXXX")
  repo="$tmp_dir/repo"
  setup_fixture_repo "$repo"
  write_valid_order "$repo/.ai/CODEX/ORDERS/T-OS-999.md"
  "$GENERATOR" --repo-root "$repo" T-OS-999 >/dev/null

  output_path="$repo/.ai/plans/T-OS-999.plan.yaml"
  before_hash=$(shasum -a 256 "$output_path" | awk '{print $1}')
  python3 - "$repo/.claude/schemas/plan-contract.v1.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
schema = json.loads(path.read_text())
schema["required"].append("unavailable_field")
schema["properties"]["unavailable_field"] = {"type": "string"}
path.write_text(json.dumps(schema), encoding="utf-8")
PY

  set +e
  "$GENERATOR" --repo-root "$repo" T-OS-999 >/dev/null 2>"$tmp_dir/stderr"
  status=$?
  set -e

  after_hash=$(shasum -a 256 "$output_path" | awk '{print $1}')
  [ "$status" -ne 0 ] || fail "schema validation failure should fail"
  [ "$before_hash" = "$after_hash" ] || fail "existing output should remain unchanged"
  [ -z "$(find "$repo/.ai/plans" -name '*.tmp' -print)" ] || fail "temporary files should be cleaned up"
  rm -rf "$tmp_dir"
}

test_idempotent_generation() {
  local tmp_dir repo output_path before_hash after_hash
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-generate-plan.XXXXXX")
  repo="$tmp_dir/repo"
  setup_fixture_repo "$repo"
  write_valid_order "$repo/.ai/CODEX/ORDERS/T-OS-999.md"
  output_path="$repo/.ai/plans/T-OS-999.plan.yaml"

  "$GENERATOR" --repo-root "$repo" T-OS-999 >/dev/null
  before_hash=$(shasum -a 256 "$output_path" | awk '{print $1}')
  "$GENERATOR" --repo-root "$repo" T-OS-999 >/dev/null
  after_hash=$(shasum -a 256 "$output_path" | awk '{print $1}')

  [ "$before_hash" = "$after_hash" ] || fail "plan generation should be idempotent"
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
      run_test test_generator_script_is_executable
      run_test test_generates_plan_and_passes_schema
      run_test test_missing_acceptance_fails
      run_test test_missing_allowed_paths_fails
      run_test test_atomic_write_preserves_existing_output_on_validation_failure
      run_test test_idempotent_generation
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf '# generate-plan tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
