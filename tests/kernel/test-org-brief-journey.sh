#!/usr/bin/env bash
# Regression test for /org-brief Journey intake and BRIEF template fields.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
ORG_BRIEF="$REPO_ROOT/.claude/commands/org-brief.md"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local needle="$1"
  local msg="$2"
  grep -Fq "$needle" "$ORG_BRIEF" || fail "$msg: expected '$needle' in $ORG_BRIEF"
}

assert_contains "#### F. 業務フロー / Journey（必須）" "journey intake step"
assert_contains "## 業務フロー / Journey" "brief template journey section"
assert_contains "### current_flow（As-Is / 現在の業務手順）" "current_flow template field"
assert_contains "### target_flow（To-Be / 実現したい業務手順）" "target_flow template field"
assert_contains "### happy_path（通常成功する流れ）" "happy_path template field"

question_count=$(grep -Fc '```' "$ORG_BRIEF")
journey_question_count=$(sed -n '/#### F\. 業務フロー \/ Journey（必須）/,/#### G\. マスト要件/p' "$ORG_BRIEF" | grep -Fc '```')

[ "$journey_question_count" -ge 12 ] || fail "journey intake should contain at least 6 fenced question blocks"
[ "$question_count" -ge "$journey_question_count" ] || fail "question fence count sanity check"

printf 'ok - org-brief Journey intake and template fields present\n'
