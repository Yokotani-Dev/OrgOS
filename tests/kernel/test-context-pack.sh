#!/usr/bin/env bash
# Context Pack Builder tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
CONTEXT_PACK=${CONTEXT_PACK:-"$REPO_ROOT/scripts/org/context-pack.sh"}
REDACTOR=${REDACTOR:-"$REPO_ROOT/scripts/org/redact-secrets.py"}

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
    fail "$msg: unexpected '$needle' in $path"
  fi
}

setup_fixture() {
  local tmp_dir="$1"
  local repo="$tmp_dir/repo"

  mkdir -p \
    "$repo/.claude/rules" \
    "$repo/.ai/CODEX/ORDERS" \
    "$repo/.ai/CODEX/RESULTS" \
    "$repo/.ai/REVIEW/PACKETS" \
    "$repo/.ai/artifacts/T-CTX/20260516T000000Z-T-CTX-1234"

  cat > "$repo/.claude/rules/alpha.md" <<'EOF_RULE'
# Alpha Rule
Rules are included in the context pack.
EOF_RULE

  cat > "$repo/.ai/TASKS.yaml" <<'EOF_TASKS'
tasks:
  - id: T-QUEUED
    title: Queued task
    status: queued
    priority: P1
    allowed_paths:
      - scripts/org/context-pack.sh
  - id: T-RUNNING
    title: Running task
    status: running
    priority: P0
  - id: T-DONE
    title: Done task
    status: done
EOF_TASKS

  cat > "$repo/.ai/CODEX/ORDERS/T-CTX.md" <<'EOF_ORDER'
# T-CTX Work Order
Use token github_token=ghp_abcdefghijklmnopqrstuvwxyz1234567890AB.
OpenAI key sk-proj-abcdefghijklmnopqrstuvwxyz1234567890 should be hidden.
EOF_ORDER

  cat > "$repo/.ai/HANDOFF.md" <<'EOF_HANDOFF'
# PROJECT HANDOFF
Handoff content.
EOF_HANDOFF

  cat > "$repo/.ai/CODEX/RESULTS/T-CTX.md" <<'EOF_RESULT'
# T-CTX Result
Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456
EOF_RESULT

  cat > "$repo/.ai/REVIEW/PACKETS/T-CTX.md" <<'EOF_PACKET'
# Review Packet
EOF_PACKET

  cat > "$repo/.ai/artifacts/T-CTX/20260516T000000Z-T-CTX-1234/artifact_manifest.json" <<'EOF_MANIFEST'
{"schema_version":"orgos.artifact_manifest.v1","task_id":"T-CTX"}
EOF_MANIFEST
}

test_include_rules_combines_rules() {
  local tmp_dir repo output_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-context-pack.XXXXXX")
  repo="$tmp_dir/repo"
  setup_fixture "$tmp_dir"
  output_path="$tmp_dir/rules.md"

  ORGOS_CONTEXT_PACK_REPO_ROOT="$repo" "$CONTEXT_PACK" --include-rules --output "$output_path" >/dev/null
  assert_contains "$output_path" "# Alpha Rule" "rules should be included"
  assert_contains "$output_path" ".claude/rules/alpha.md" "rule path should be labeled"
  rm -rf "$tmp_dir"
}

test_include_tasks_lists_active_tasks_only() {
  local tmp_dir repo output_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-context-pack.XXXXXX")
  repo="$tmp_dir/repo"
  setup_fixture "$tmp_dir"
  output_path="$tmp_dir/tasks.md"

  ORGOS_CONTEXT_PACK_REPO_ROOT="$repo" "$CONTEXT_PACK" --include-tasks --output "$output_path" >/dev/null
  assert_contains "$output_path" "T-QUEUED" "queued task should be listed"
  assert_contains "$output_path" "T-RUNNING" "running task should be listed"
  assert_not_contains "$output_path" "T-DONE" "done task should not be listed"
  rm -rf "$tmp_dir"
}

test_task_context_redacts_secrets() {
  local tmp_dir repo output_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-context-pack.XXXXXX")
  repo="$tmp_dir/repo"
  setup_fixture "$tmp_dir"
  output_path="$tmp_dir/task.md"

  ORGOS_CONTEXT_PACK_REPO_ROOT="$repo" "$CONTEXT_PACK" --task T-CTX --output "$output_path" >/dev/null
  assert_contains "$output_path" "[REDACTED]" "secrets should be redacted"
  assert_not_contains "$output_path" "ghp_abcdefghijklmnopqrstuvwxyz1234567890AB" "GitHub token should be hidden"
  assert_not_contains "$output_path" "sk-proj-abcdefghijklmnopqrstuvwxyz1234567890" "OpenAI key should be hidden"
  assert_not_contains "$output_path" "Bearer abcdefghijklmnopqrstuvwxyz123456" "Bearer token should be hidden"
  assert_contains "$output_path" "artifact_manifest.json" "artifact manifest should be included"
  rm -rf "$tmp_dir"
}

test_size_limit_truncates_output() {
  local tmp_dir repo output_path size
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-context-pack.XXXXXX")
  repo="$tmp_dir/repo"
  setup_fixture "$tmp_dir"
  output_path="$tmp_dir/limited.md"

  perl -0pi -e 'print "large-content\n" x 500' "$repo/.claude/rules/alpha.md"
  ORGOS_CONTEXT_PACK_REPO_ROOT="$repo" ORGOS_CONTEXT_PACK_MAX_BYTES=1024 \
    "$CONTEXT_PACK" --include-rules --output "$output_path" >/dev/null
  size=$(wc -c < "$output_path" | tr -d ' ')
  [ "$size" -le 1024 ] || fail "output should respect size limit"
  assert_contains "$output_path" "[TRUNCATED: context pack exceeded 1024 bytes]" "truncation marker should be present"
  rm -rf "$tmp_dir"
}

test_redactor_stdin_common_patterns() {
  local tmp_dir output_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-context-pack.XXXXXX")
  output_path="$tmp_dir/redacted.txt"

  printf 'aws_access_key_id=AKIA1234567890ABCDEF\npassword=hunter2secret\n' | "$REDACTOR" > "$output_path"
  assert_contains "$output_path" "[REDACTED]" "redactor should replace common secret patterns"
  assert_not_contains "$output_path" "AKIA1234567890ABCDEF" "AWS access key should be hidden"
  assert_not_contains "$output_path" "hunter2secret" "password value should be hidden"
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
      run_test test_include_rules_combines_rules
      run_test test_include_tasks_lists_active_tasks_only
      run_test test_task_context_redacts_secrets
      run_test test_size_limit_truncates_output
      run_test test_redactor_stdin_common_patterns
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf '# context-pack tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
