#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: bash scripts/codex/run-in-worktree.sh <TASK_ID> [--keep-worktree|--preserve-worktree] [--cleanup-after-manifest --artifact-manifest PATH]

Creates .worktrees/<TASK_ID>, runs Codex inside that worktree, and removes the
worktree after Codex exits only when --cleanup-after-manifest is set and the
artifact manifest passes validation. By default, worktrees are preserved.
USAGE
}

log() {
  level=$1
  event=$2
  shift 2

  printf 'ts=%s level=%s event=%s' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$level" "$event" >&2
  while [ "$#" -gt 0 ]; do
    printf ' %s' "$1" >&2
    shift
  done
  printf '\n' >&2
}

quote_value() {
  value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '"%s"' "$value"
}

run_logged_command() {
  phase=$1
  shift

  log info "${phase}_start" \
    "task_id=$(quote_value "$task_id")" \
    "command=$(quote_value "$*")"

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  if [ -n "$output" ]; then
    while IFS= read -r line; do
      log info "${phase}_output" \
        "task_id=$(quote_value "$task_id")" \
        "line=$(quote_value "$line")"
    done <<EOF
$output
EOF
  fi

  log info "${phase}_completed" \
    "task_id=$(quote_value "$task_id")" \
    "exit_status=$status"

  return "$status"
}

validate_task_id() {
  task_id=$1

  case "$task_id" in
    ""|.*|*/*|*\\*|*-)
      return 1
      ;;
  esac

  case "$task_id" in
    *[!A-Za-z0-9._-]*)
      return 1
      ;;
  esac
}

cleanup_worktree() {
  if [ "$worktree_created" -ne 1 ]; then
    cleanup_status=not_created
    return 0
  fi

  if [ -z "${worktree_path:-}" ] || [ "$worktree_path" = "/" ] || [ ! -d "$worktree_path" ]; then
    cleanup_status=invalid_worktree_path
    log warn cleanup_skipped \
      "task_id=$(quote_value "$task_id")" \
      "worktree_path=$(quote_value "${worktree_path:-}")" \
      "cleanup_status=$cleanup_status"
    notify_owner "CLEANUP_WARN" \
      "cleanup skipped: task=${task_id:-unknown} path=${worktree_path:-unknown} reason=invalid_worktree_path"
    return 0
  fi

  if [ "$keep_worktree" -eq 1 ] && [ "$cleanup_after_manifest" -ne 1 ]; then
    cleanup_status=kept
    log info cleanup_skipped \
      "task_id=$(quote_value "$task_id")" \
      "worktree_path=$(quote_value "$worktree_path")" \
      "cleanup_status=$cleanup_status"
    return 0
  fi

  if [ "$cleanup_after_manifest" -ne 1 ]; then
    mark_worktree_quarantined "cleanup_requested_without_manifest_gate"
    return 0
  fi

  set +e
  verify_artifact_manifest
  manifest_status=$?
  set -e
  if [ "$manifest_status" -ne 0 ]; then
    mark_worktree_quarantined "artifact_manifest_invalid:${manifest_status}"
    return 0
  fi

  if git -C "$repo_root" worktree remove --force "$worktree_path"; then
    cleanup_status=removed_after_manifest
    log info cleanup_completed \
      "task_id=$(quote_value "$task_id")" \
      "worktree_path=$(quote_value "$worktree_path")" \
      "cleanup_status=$cleanup_status"
  else
    cleanup_status=remove_failed
    log error cleanup_failed \
      "task_id=$(quote_value "$task_id")" \
      "worktree_path=$(quote_value "$worktree_path")" \
      "cleanup_status=$cleanup_status"
    notify_owner "CLEANUP_FAILED" \
      "git worktree remove failed: task=${task_id:-unknown} path=${worktree_path:-unknown}"
  fi
}

notify_owner() {
  local level="$1"
  shift
  local msg="$*"
  echo "ORGOS_${level}: ${msg}" >&2
  if [ -n "${repo_root:-}" ]; then
    mkdir -p "$repo_root/.ai/alerts"
    printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$msg" \
      >> "$repo_root/.ai/alerts/worktree-cleanup.log" || true
  fi
}

verify_artifact_manifest() {
  if [ -z "${artifact_manifest_path:-}" ]; then
    return 10
  fi

  if [ ! -f "$artifact_manifest_path" ]; then
    return 11
  fi

  if [ ! -s "$artifact_manifest_path" ]; then
    return 12
  fi

  if [ ! -x "$artifact_manifest_verifier" ]; then
    return 13
  fi

  "$artifact_manifest_verifier" "$artifact_manifest_path"
}

mark_worktree_quarantined() {
  local reason="$1"
  cleanup_status=quarantined
  cleanup_error=1
  if [ -n "${worktree_path:-}" ] && [ -d "$worktree_path" ]; then
    cat > "$worktree_path/.orgos-quarantine" <<EOF
reason: ${reason}
timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
task_id: ${task_id:-unknown}
repo_root: ${repo_root:-unknown}
EOF
  fi
  notify_owner "CLEANUP_BLOCKED" \
    "worktree preserved/quarantined: task=${task_id:-unknown} path=${worktree_path:-unknown} reason=${reason} cleanup_error=${cleanup_error}"
}

keep_worktree=1
cleanup_after_manifest=0
artifact_manifest_path=""
artifact_manifest_override=0

if [ "$#" -lt 1 ]; then
  usage
  exit 2
fi

task_id=$1
shift

while [ "$#" -gt 0 ]; do
  case "$1" in
    --preserve-worktree)
      keep_worktree=1
      ;;
    --keep-worktree)
      keep_worktree=1
      ;;
    --cleanup-after-manifest)
      cleanup_after_manifest=1
      ;;
    --artifact-manifest)
      if [ "$#" -lt 2 ]; then
        printf 'run-in-worktree.sh: --artifact-manifest requires PATH\n' >&2
        usage
        exit 2
      fi
      artifact_manifest_path=$2
      artifact_manifest_override=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'run-in-worktree.sh: unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

if ! validate_task_id "$task_id"; then
  printf 'run-in-worktree.sh: invalid TASK_ID: %s\n' "$task_id" >&2
  exit 2
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ]; then
  printf 'run-in-worktree.sh: must be run inside a git repository\n' >&2
  exit 1
fi

worktree_dir="$repo_root/.worktrees"
worktree_path="$worktree_dir/$task_id"
order_path="$repo_root/.ai/CODEX/ORDERS/$task_id.md"
result_path="$repo_root/.ai/CODEX/RESULTS/$task_id.txt"
codex_bin=${ORGOS_CODEX_BIN:-/opt/homebrew/bin/codex}
pre_exec_validate="$repo_root/scripts/codex/pre-exec-validate.sh"
post_exec_audit="$repo_root/scripts/codex/post-exec-audit.sh"
collect_artifacts="$repo_root/scripts/org/collect-artifacts.sh"
artifact_manifest_verifier="$repo_root/scripts/org/verify-artifact-manifest.py"
worktree_created=0
cleanup_status=not_started

trap cleanup_worktree EXIT

if [ ! -f "$order_path" ]; then
  printf 'run-in-worktree.sh: Work Order not found: %s\n' "$order_path" >&2
  exit 1
fi

if [ ! -x "$codex_bin" ]; then
  printf 'run-in-worktree.sh: Codex executable not found or not executable: %s\n' "$codex_bin" >&2
  exit 1
fi

if [ ! -f "$pre_exec_validate" ]; then
  printf 'run-in-worktree.sh: pre-exec validator not found: %s\n' "$pre_exec_validate" >&2
  exit 1
fi

if [ ! -f "$post_exec_audit" ]; then
  printf 'run-in-worktree.sh: post-exec auditor not found: %s\n' "$post_exec_audit" >&2
  exit 1
fi

if [ ! -x "$collect_artifacts" ]; then
  printf 'run-in-worktree.sh: artifact collector not found or not executable: %s\n' "$collect_artifacts" >&2
  exit 1
fi

if [ ! -x "$artifact_manifest_verifier" ]; then
  printf 'run-in-worktree.sh: artifact manifest verifier not found or not executable: %s\n' "$artifact_manifest_verifier" >&2
  exit 1
fi

if ! run_logged_command pre_exec_validate bash "$pre_exec_validate" "$task_id"; then
  log error pre_exec_validate_failed \
    "task_id=$(quote_value "$task_id")" \
    "recovery=$(quote_value "fix Work Order boundaries before creating worktree")"
  exit 1
fi

mkdir -p "$worktree_dir" "$(dirname "$result_path")"

run_ts="$(date -u +%Y%m%dT%H%M%SZ)"
if command -v uuidgen >/dev/null 2>&1; then
  rand="$(uuidgen | tr 'A-F' 'a-f' | cut -c1-8)"
else
  rand="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
fi
run_id="${run_ts}-${task_id}-${rand}"
artifact_dir="$repo_root/.ai/artifacts/$task_id/$run_id"
stdout_file="$artifact_dir/logs/stdout.log"
stderr_file="$artifact_dir/logs/stderr.log"
mkdir -p "$artifact_dir/logs"
: > "$stdout_file"
: > "$stderr_file"

if [ "$artifact_manifest_override" -eq 0 ]; then
  artifact_manifest_path="$artifact_dir/artifact_manifest.json"
fi

log info worktree_create_start \
  "task_id=$(quote_value "$task_id")" \
  "worktree_path=$(quote_value "$worktree_path")"

path_preexisted=0
if [ -e "$worktree_path" ]; then
  path_preexisted=1
fi

start_epoch=$(date +%s)
if git -C "$repo_root" worktree add "$worktree_path" HEAD; then
  worktree_created=1
else
  log error worktree_create_failed \
    "task_id=$(quote_value "$task_id")" \
    "worktree_path=$(quote_value "$worktree_path")" \
    "recovery=prune"
  git -C "$repo_root" worktree prune >/dev/null 2>&1 || true
  if [ "$path_preexisted" -eq 0 ] && [ -e "$worktree_path" ]; then
    rm -rf -- "$worktree_path"
  fi
  exit 1
fi
end_epoch=$(date +%s)
head_before=$(git -C "$worktree_path" rev-parse HEAD)

log info worktree_create_completed \
  "task_id=$(quote_value "$task_id")" \
  "worktree_path=$(quote_value "$worktree_path")" \
  "duration_seconds=$((end_epoch - start_epoch))"

log info codex_exec_start \
  "task_id=$(quote_value "$task_id")" \
  "worktree_path=$(quote_value "$worktree_path")" \
  "output_path=$(quote_value "$result_path")"

codex_started_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
stdout_fifo="$artifact_dir/logs/stdout.fifo"
stderr_fifo="$artifact_dir/logs/stderr.fifo"
rm -f "$stdout_fifo" "$stderr_fifo"
mkfifo "$stdout_fifo" "$stderr_fifo"
tee -a "$stdout_file" < "$stdout_fifo" &
stdout_tee_pid=$!
tee -a "$stderr_file" < "$stderr_fifo" >&2 &
stderr_tee_pid=$!
set +e
(
  cd "$worktree_path"
  "$codex_bin" exec --full-auto --skip-git-repo-check \
    --output-last-message "../../.ai/CODEX/RESULTS/$task_id.txt" \
    - < "../../.ai/CODEX/ORDERS/$task_id.md"
) > "$stdout_fifo" 2> "$stderr_fifo"
codex_status=$?
wait "$stdout_tee_pid"
stdout_tee_status=$?
wait "$stderr_tee_pid"
stderr_tee_status=$?
set -e
rm -f "$stdout_fifo" "$stderr_fifo"
codex_ended_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
if [ "$stdout_tee_status" -ne 0 ] || [ "$stderr_tee_status" -ne 0 ]; then
  log warn codex_capture_tee_failed \
    "task_id=$(quote_value "$task_id")" \
    "stdout_tee_status=$stdout_tee_status" \
    "stderr_tee_status=$stderr_tee_status"
fi

log info codex_exec_completed \
  "task_id=$(quote_value "$task_id")" \
  "worktree_path=$(quote_value "$worktree_path")" \
  "exit_status=$codex_status"

post_status=0
run_logged_command post_exec_audit bash "$post_exec_audit" "$task_id" "$worktree_path" || post_status=$?
if [ "$post_status" -ne 0 ]; then
  log error post_exec_audit_failed \
    "task_id=$(quote_value "$task_id")" \
    "worktree_path=$(quote_value "$worktree_path")" \
    "exit_status=$post_status" \
    "recovery=$(quote_value "post-exec-audit reverted disallowed files when possible")"
fi

collect_status=0
log info artifact_collection_start \
  "task_id=$(quote_value "$task_id")" \
  "run_id=$(quote_value "$run_id")" \
  "artifact_dir=$(quote_value "$artifact_dir")"
set +e
ORGOS_HEAD_BEFORE="$head_before" \
ORGOS_EXEC_STARTED_AT="$codex_started_at" \
ORGOS_EXEC_ENDED_AT="$codex_ended_at" \
ORGOS_EXEC_EXIT_CODE="$codex_status" \
ORGOS_COMMAND_LABEL="codex exec" \
ORGOS_WRAPPER_VERSION="day1-artifact-manifest" \
ORGOS_REPO_ROOT="$repo_root" \
"$collect_artifacts" \
  --task-id "$task_id" \
  --run-id "$run_id" \
  --worktree-path "$worktree_path" \
  --artifact-dir "$artifact_dir" \
  --stdout-source "$stdout_file" \
  --stderr-source "$stderr_file" \
  --last-message-source "$result_path" \
  --actor-role codex \
  --actor-id "${ORGOS_ACTOR_ID:-codex}"
collect_status=$?
set -e
log info artifact_collection_completed \
  "task_id=$(quote_value "$task_id")" \
  "run_id=$(quote_value "$run_id")" \
  "artifact_manifest=$(quote_value "$artifact_manifest_path")" \
  "exit_status=$collect_status"

if [ "$post_status" -ne 0 ]; then
  exit "$post_status"
fi

if [ "$collect_status" -ne 0 ]; then
  exit "$collect_status"
fi

exit "$codex_status"
