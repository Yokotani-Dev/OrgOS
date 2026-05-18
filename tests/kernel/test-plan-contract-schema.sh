#!/usr/bin/env bash
# Plan Contract schema validation tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
SCHEMA=${SCHEMA:-"$REPO_ROOT/.claude/schemas/plan-contract.v1.json"}

pass_count=0
fail_count=0
current_test_failed=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
  return 1
}

write_valid_plan() {
  local path="$1"
  cat > "$path" <<'YAML'
schema_version: orgos.plan_contract.v1
task_id: T-OS-454
title: "Plan Contract Schema"
acceptance:
  - "Schema file created"
  - "Kernel tests pass"
allowed_paths:
  - .claude/schemas/plan-contract.v1.json
  - tests/kernel/test-plan-contract-schema.sh
verification:
  - command: "bash tests/kernel/test-plan-contract-schema.sh"
    expect: pass
created_at: "2026-05-17T00:00:00Z"
created_by: manager
YAML
}

validate_plan() {
  local plan_path="$1"
  python3 - "$SCHEMA" "$plan_path" <<'PY'
import json
import sys

import yaml
from jsonschema import Draft202012Validator, FormatChecker

schema_path, plan_path = sys.argv[1:3]
with open(schema_path, "r", encoding="utf-8") as handle:
    schema = json.load(handle)
with open(plan_path, "r", encoding="utf-8") as handle:
    plan = yaml.safe_load(handle)

validator = Draft202012Validator(schema, format_checker=FormatChecker())
errors = sorted(validator.iter_errors(plan), key=lambda error: list(error.path))
if errors:
    for error in errors:
        path = ".".join(str(part) for part in error.path) or "<root>"
        print(f"{path}: {error.message}", file=sys.stderr)
    raise SystemExit(1)
PY
}

assert_validation_fails() {
  local plan_path="$1"
  local msg="$2"
  local status

  set +e
  validate_plan "$plan_path" >/dev/null 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "$msg"
}

test_valid_plan_passes() {
  local tmp_dir plan_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-plan-contract.XXXXXX")
  plan_path="$tmp_dir/.plan.yaml"
  write_valid_plan "$plan_path"

  validate_plan "$plan_path"
  rm -rf "$tmp_dir"
}

test_missing_task_id_fails() {
  local tmp_dir plan_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-plan-contract.XXXXXX")
  plan_path="$tmp_dir/.plan.yaml"
  write_valid_plan "$plan_path"
  python3 - "$plan_path" <<'PY'
import sys

import yaml

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
data.pop("task_id")
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(data, handle, sort_keys=False)
PY

  assert_validation_fails "$plan_path" "missing task_id should fail"
  rm -rf "$tmp_dir"
}

test_missing_acceptance_fails() {
  local tmp_dir plan_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-plan-contract.XXXXXX")
  plan_path="$tmp_dir/.plan.yaml"
  write_valid_plan "$plan_path"
  python3 - "$plan_path" <<'PY'
import sys

import yaml

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
data.pop("acceptance")
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(data, handle, sort_keys=False)
PY

  assert_validation_fails "$plan_path" "missing acceptance should fail"
  rm -rf "$tmp_dir"
}

test_empty_allowed_paths_fails() {
  local tmp_dir plan_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-plan-contract.XXXXXX")
  plan_path="$tmp_dir/.plan.yaml"
  write_valid_plan "$plan_path"
  python3 - "$plan_path" <<'PY'
import sys

import yaml

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
data["allowed_paths"] = []
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(data, handle, sort_keys=False)
PY

  assert_validation_fails "$plan_path" "empty allowed_paths should fail"
  rm -rf "$tmp_dir"
}

test_invalid_schema_version_fails() {
  local tmp_dir plan_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-plan-contract.XXXXXX")
  plan_path="$tmp_dir/.plan.yaml"
  write_valid_plan "$plan_path"
  python3 - "$plan_path" <<'PY'
import sys

import yaml

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
data["schema_version"] = "orgos.plan_contract.v2"
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(data, handle, sort_keys=False)
PY

  assert_validation_fails "$plan_path" "invalid schema_version should fail"
  rm -rf "$tmp_dir"
}

test_invalid_created_by_fails() {
  local tmp_dir plan_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-plan-contract.XXXXXX")
  plan_path="$tmp_dir/.plan.yaml"
  write_valid_plan "$plan_path"
  python3 - "$plan_path" <<'PY'
import sys

import yaml

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
data["created_by"] = "planner"
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(data, handle, sort_keys=False)
PY

  assert_validation_fails "$plan_path" "invalid created_by should fail"
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
      run_test test_valid_plan_passes
      run_test test_missing_task_id_fails
      run_test test_missing_acceptance_fails
      run_test test_empty_allowed_paths_fails
      run_test test_invalid_schema_version_fails
      run_test test_invalid_created_by_fails
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'Plan contract schema tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
