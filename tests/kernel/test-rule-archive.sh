#!/usr/bin/env bash
# Kernel rule archive invariants.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
RULES_DIR="$REPO_ROOT/.claude/rules"
ARCHIVE_DIR="$RULES_DIR/_archive"

ARCHIVED_RULES=(
  "pre-implementation-risk-profile.md"
  "acceptance-pre-write.md"
  "eval-loop.md"
)

ARCHIVED_NOTICE='> **ARCHIVED 2026-05-17**: This rule is superseded by the kernel.'
PRE_ARCHIVE_RULE_COUNT=32
EXPECTED_CURRENT_RULE_COUNT=$((PRE_ARCHIVE_RULE_COUNT - ${#ARCHIVED_RULES[@]}))

pass_count=0
fail_count=0
current_test_failed=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
}

run_test() {
  local name="$1"
  current_test_failed=0
  "$name"
  if [ "$current_test_failed" -eq 0 ]; then
    printf 'ok - %s\n' "$name"
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
  fi
}

test_archived_rules_exist() {
  local rule
  for rule in "${ARCHIVED_RULES[@]}"; do
    [ -f "$ARCHIVE_DIR/$rule" ] || fail "archived rule missing: $rule"
  done
}

test_archived_rules_removed_from_top_level() {
  local rule
  for rule in "${ARCHIVED_RULES[@]}"; do
    [ ! -e "$RULES_DIR/$rule" ] || fail "rule still exists at top level: $rule"
  done
}

test_archived_notice_is_first_line() {
  local rule first_line
  for rule in "${ARCHIVED_RULES[@]}"; do
    if [ ! -f "$ARCHIVE_DIR/$rule" ]; then
      fail "cannot check archive notice; missing rule: $rule"
      continue
    fi
    first_line=$(sed -n '1p' "$ARCHIVE_DIR/$rule")
    [ "$first_line" = "$ARCHIVED_NOTICE" ] || fail "archive notice is not first line for: $rule"
  done
}

test_top_level_rule_count_decreased_by_three() {
  local current_count
  current_count=$(find "$RULES_DIR" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
  [ "$current_count" -eq "$EXPECTED_CURRENT_RULE_COUNT" ] || fail "expected $EXPECTED_CURRENT_RULE_COUNT top-level rules, got $current_count"
}

test_parallel_session_policy_stays_top_level() {
  [ -f "$RULES_DIR/parallel-session-policy.md" ] || fail "parallel-session-policy.md should stay top-level"
}

run_test test_archived_rules_exist
run_test test_archived_rules_removed_from_top_level
run_test test_archived_notice_is_first_line
run_test test_top_level_rule_count_decreased_by_three
run_test test_parallel_session_policy_stays_top_level

printf 'rule archive tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
