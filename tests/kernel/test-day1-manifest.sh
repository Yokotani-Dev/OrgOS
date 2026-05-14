#!/usr/bin/env bash
# Day 1 artifact manifest collection and verification tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
COLLECTOR=${COLLECTOR:-"$REPO_ROOT/scripts/org/collect-artifacts.sh"}
VERIFIER=${VERIFIER:-"$REPO_ROOT/scripts/org/verify-artifact-manifest.py"}
WRAPPER=${WRAPPER:-"$REPO_ROOT/scripts/codex/run-in-worktree.sh"}

pass_count=0
fail_count=0
current_test_failed=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
  return 1
}

assert_exists() {
  local path="$1"
  local msg="$2"
  [ -e "$path" ] || fail "$msg: missing $path"
}

assert_not_exists() {
  local path="$1"
  local msg="$2"
  [ ! -e "$path" ] || fail "$msg: unexpected $path"
}

assert_contains() {
  local path="$1"
  local needle="$2"
  local msg="$3"
  grep -Fq "$needle" "$path" || fail "$msg: expected '$needle' in $path"
}

setup_collect_fixture() {
  local task_id="$1"
  local tmp_dir repo worktree artifact_dir stdout_path stderr_path last_msg_path

  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-day1-manifest.XXXXXX")
  repo="$tmp_dir/repo"
  worktree="$repo/.worktrees/$task_id"
  artifact_dir="$repo/.ai/artifacts/$task_id/20260514T000000Z-$task_id-1234abcd"
  stdout_path="$tmp_dir/stdout.log"
  stderr_path="$tmp_dir/stderr.log"
  last_msg_path="$tmp_dir/output-last-message.txt"

  git clone --quiet "$REPO_ROOT" "$repo"
  git -C "$repo" worktree add --quiet "$worktree" HEAD
  mkdir -p "$(dirname "$artifact_dir")"
  printf 'mock stdout\n' > "$stdout_path"
  printf 'mock stderr\n' > "$stderr_path"
  printf 'mock final message\n' > "$last_msg_path"

  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$tmp_dir" "$repo" "$worktree" "$artifact_dir" "$stdout_path" "$stderr_path" "$last_msg_path"
}

run_collect() {
  local task_id="$1"
  local worktree="$2"
  local artifact_dir="$3"
  local stdout_path="$4"
  local stderr_path="$5"
  local last_msg_path="$6"

  (
    cd "$(dirname "$(dirname "$(dirname "$artifact_dir")")")"
    "$COLLECTOR" \
      --task-id "$task_id" \
      --run-id "20260514T000000Z-$task_id-1234abcd" \
      --worktree-path "$worktree" \
      --artifact-dir "$artifact_dir" \
      --stdout-source "$stdout_path" \
      --stderr-source "$stderr_path" \
      --last-message-source "$last_msg_path" \
      --actor-role mock \
      --actor-id test
  )
}

manifest_has_kind() {
  local manifest_path="$1"
  local kind="$2"
  python3 - "$manifest_path" "$kind" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

if any(entry.get("kind") == sys.argv[2] for entry in data.get("artifacts", [])):
    sys.exit(0)
sys.exit(1)
PY
}

manifest_sha_matches() {
  local manifest_path="$1"
  local rel_path="$2"
  local source_path="$3"
  python3 - "$manifest_path" "$rel_path" "$source_path" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

manifest = Path(sys.argv[1])
rel_path = sys.argv[2]
source = Path(sys.argv[3])
with manifest.open("r", encoding="utf-8") as handle:
    data = json.load(handle)

expected = hashlib.sha256(source.read_bytes()).hexdigest()
for entry in data["artifacts"]:
    if entry["artifact_path"] == rel_path:
        sys.exit(0 if entry["sha256"] == expected else 1)
sys.exit(1)
PY
}

test_collect_basic_artifacts() {
  local task_id="T-DAY1-BASIC"
  local fixture tmp_dir repo worktree artifact_dir stdout_path stderr_path last_msg_path manifest_path
  fixture=$(setup_collect_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  artifact_dir=$(printf '%s\n' "$fixture" | sed -n '4p')
  stdout_path=$(printf '%s\n' "$fixture" | sed -n '5p')
  stderr_path=$(printf '%s\n' "$fixture" | sed -n '6p')
  last_msg_path=$(printf '%s\n' "$fixture" | sed -n '7p')
  manifest_path="$artifact_dir/artifact_manifest.json"

  run_collect "$task_id" "$worktree" "$artifact_dir" "$stdout_path" "$stderr_path" "$last_msg_path"

  assert_exists "$manifest_path" "collector should write manifest"
  manifest_sha_matches "$manifest_path" "logs/stdout.log" "$stdout_path" || fail "stdout sha256 should match"
  manifest_sha_matches "$manifest_path" "logs/stderr.log" "$stderr_path" || fail "stderr sha256 should match"
  git -C "$repo" worktree remove --force "$worktree" >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}

test_collect_with_generated_files() {
  local task_id="T-DAY1-GENERATED"
  local fixture tmp_dir worktree artifact_dir stdout_path stderr_path last_msg_path manifest_path
  fixture=$(setup_collect_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  artifact_dir=$(printf '%s\n' "$fixture" | sed -n '4p')
  stdout_path=$(printf '%s\n' "$fixture" | sed -n '5p')
  stderr_path=$(printf '%s\n' "$fixture" | sed -n '6p')
  last_msg_path=$(printf '%s\n' "$fixture" | sed -n '7p')
  manifest_path="$artifact_dir/artifact_manifest.json"
  printf '# generated\n' > "$worktree/generated-report.md"

  run_collect "$task_id" "$worktree" "$artifact_dir" "$stdout_path" "$stderr_path" "$last_msg_path"

  manifest_has_kind "$manifest_path" "generated_file" || fail "manifest should include generated_file"
  rm -rf "$tmp_dir"
}

test_collect_with_untracked_files() {
  local task_id="T-DAY1-UNTRACKED"
  local fixture tmp_dir worktree artifact_dir stdout_path stderr_path last_msg_path manifest_path
  fixture=$(setup_collect_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  artifact_dir=$(printf '%s\n' "$fixture" | sed -n '4p')
  stdout_path=$(printf '%s\n' "$fixture" | sed -n '5p')
  stderr_path=$(printf '%s\n' "$fixture" | sed -n '6p')
  last_msg_path=$(printf '%s\n' "$fixture" | sed -n '7p')
  manifest_path="$artifact_dir/artifact_manifest.json"
  printf 'untracked payload\n' > "$worktree/untracked.bin"

  run_collect "$task_id" "$worktree" "$artifact_dir" "$stdout_path" "$stderr_path" "$last_msg_path"

  manifest_has_kind "$manifest_path" "untracked_file" || fail "manifest should include untracked_file"
  rm -rf "$tmp_dir"
}

test_verify_passes_for_valid_manifest() {
  local task_id="T-DAY1-VERIFY-PASS"
  local fixture tmp_dir worktree artifact_dir stdout_path stderr_path last_msg_path manifest_path
  fixture=$(setup_collect_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  artifact_dir=$(printf '%s\n' "$fixture" | sed -n '4p')
  stdout_path=$(printf '%s\n' "$fixture" | sed -n '5p')
  stderr_path=$(printf '%s\n' "$fixture" | sed -n '6p')
  last_msg_path=$(printf '%s\n' "$fixture" | sed -n '7p')
  manifest_path="$artifact_dir/artifact_manifest.json"

  run_collect "$task_id" "$worktree" "$artifact_dir" "$stdout_path" "$stderr_path" "$last_msg_path"
  "$VERIFIER" "$manifest_path"
  rm -rf "$tmp_dir"
}

test_verify_fails_for_missing_required_artifact() {
  local task_id="T-DAY1-VERIFY-FAIL"
  local fixture tmp_dir worktree artifact_dir stdout_path stderr_path last_msg_path manifest_path verify_stderr
  fixture=$(setup_collect_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  artifact_dir=$(printf '%s\n' "$fixture" | sed -n '4p')
  stdout_path=$(printf '%s\n' "$fixture" | sed -n '5p')
  stderr_path=$(printf '%s\n' "$fixture" | sed -n '6p')
  last_msg_path=$(printf '%s\n' "$fixture" | sed -n '7p')
  manifest_path="$artifact_dir/artifact_manifest.json"
  verify_stderr="$tmp_dir/verify.err"

  run_collect "$task_id" "$worktree" "$artifact_dir" "$stdout_path" "$stderr_path" "$last_msg_path"
  rm "$artifact_dir/logs/stdout.log"
  if "$VERIFIER" "$manifest_path" 2>"$verify_stderr"; then
    fail "verifier should fail when required artifact file is missing"
  fi
  assert_contains "$verify_stderr" "missing" "verifier should explain missing artifact"
  rm -rf "$tmp_dir"
}

test_wrapper_e2e_with_cleanup_after_manifest() {
  local task_id="T-DAY1-E2E"
  local tmp_dir repo codex_stub stdout_path stderr_path worktree_path artifact_root run_dir manifest_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-day1-e2e.XXXXXX")
  repo="$tmp_dir/repo"
  codex_stub="$tmp_dir/codex-stub"
  stdout_path="$tmp_dir/stdout.log"
  stderr_path="$tmp_dir/stderr.log"
  worktree_path="$repo/.worktrees/$task_id"
  artifact_root="$repo/.ai/artifacts/$task_id"

  git clone --quiet "$REPO_ROOT" "$repo"
  mkdir -p "$repo/scripts/codex" "$repo/scripts/org" "$repo/.ai/CODEX/ORDERS"
  cp "$WRAPPER" "$repo/scripts/codex/run-in-worktree.sh"
  cp "$COLLECTOR" "$repo/scripts/org/collect-artifacts.sh"
  cp "$VERIFIER" "$repo/scripts/org/verify-artifact-manifest.py"
  chmod +x "$repo/scripts/codex/run-in-worktree.sh" "$repo/scripts/org/collect-artifacts.sh" "$repo/scripts/org/verify-artifact-manifest.py"

  cat > "$repo/scripts/codex/pre-exec-validate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "$repo/scripts/codex/pre-exec-validate.sh"

  cat > "$repo/scripts/codex/post-exec-audit.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "$repo/scripts/codex/post-exec-audit.sh"

  cat > "$codex_stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output_last_message=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message)
      output_last_message=$2
      shift
      ;;
  esac
  shift
done
cat >/dev/null
printf 'codex stdout\n'
printf 'codex stderr\n' >&2
printf '# generated handoff\n' > e2e-generated.md
if [ -n "$output_last_message" ]; then
  mkdir -p "$(dirname "$output_last_message")"
  printf 'e2e final message\n' > "$output_last_message"
fi
exit 0
EOF
  chmod +x "$codex_stub"
  printf '# test order for %s\n' "$task_id" > "$repo/.ai/CODEX/ORDERS/$task_id.md"

  (
    cd "$repo"
    ORGOS_CODEX_BIN="$codex_stub" bash scripts/codex/run-in-worktree.sh "$task_id" --cleanup-after-manifest
  ) >"$stdout_path" 2>"$stderr_path"

  assert_not_exists "$worktree_path" "wrapper should remove worktree after verified manifest"
  assert_exists "$artifact_root" "wrapper should preserve artifact root"
  run_dir=$(find "$artifact_root" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  manifest_path="$run_dir/artifact_manifest.json"
  assert_exists "$manifest_path" "wrapper should write artifact manifest"
  "$VERIFIER" "$manifest_path"
  assert_exists "$repo/.ai/CODEX/RESULTS/$task_id.txt" "wrapper should write main repo handoff"
  assert_exists "$run_dir/output-last-message.txt" "collector should copy handoff into artifact store"
  rm -rf "$tmp_dir"
}

run_test() {
  local name="$1"
  current_test_failed=0
  "$name" || current_test_failed=1
  if [ "$current_test_failed" -eq 0 ]; then
    pass_count=$((pass_count + 1))
    printf 'ok - %s\n' "$name"
  else
    fail_count=$((fail_count + 1))
    printf 'not ok - %s\n' "$name" >&2
  fi
}

main() {
  run_test test_collect_basic_artifacts
  run_test test_collect_with_generated_files
  run_test test_collect_with_untracked_files
  run_test test_verify_passes_for_valid_manifest
  run_test test_verify_fails_for_missing_required_artifact
  run_test test_wrapper_e2e_with_cleanup_after_manifest

  printf 'day1 manifest tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
