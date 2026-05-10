#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: bash scripts/codex/run-in-worktree.sh <TASK_ID> [--keep-worktree]

Creates .worktrees/<TASK_ID>, runs Codex inside that worktree, and removes the
worktree after Codex exits unless --keep-worktree is set.
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
    return 0
  fi

  if [ "$keep_worktree" -eq 1 ]; then
    cleanup_status=kept
    log info cleanup_skipped \
      "task_id=$(quote_value "$task_id")" \
      "worktree_path=$(quote_value "$worktree_path")" \
      "cleanup_status=$cleanup_status"
    return 0
  fi

  if git -C "$repo_root" worktree remove --force "$worktree_path"; then
    cleanup_status=removed
    log info cleanup_completed \
      "task_id=$(quote_value "$task_id")" \
      "worktree_path=$(quote_value "$worktree_path")" \
      "cleanup_status=$cleanup_status"
  else
    cleanup_status=failed
    log error cleanup_failed \
      "task_id=$(quote_value "$task_id")" \
      "worktree_path=$(quote_value "$worktree_path")" \
      "cleanup_status=$cleanup_status"
  fi
}

keep_worktree=0

if [ "$#" -lt 1 ]; then
  usage
  exit 2
fi

task_id=$1
shift

while [ "$#" -gt 0 ]; do
  case "$1" in
    --keep-worktree)
      keep_worktree=1
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

if ! run_logged_command pre_exec_validate bash "$pre_exec_validate" "$task_id"; then
  log error pre_exec_validate_failed \
    "task_id=$(quote_value "$task_id")" \
    "recovery=$(quote_value "fix Work Order boundaries before creating worktree")"
  exit 1
fi

mkdir -p "$worktree_dir" "$(dirname "$result_path")"

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

log info worktree_create_completed \
  "task_id=$(quote_value "$task_id")" \
  "worktree_path=$(quote_value "$worktree_path")" \
  "duration_seconds=$((end_epoch - start_epoch))"

log info codex_exec_start \
  "task_id=$(quote_value "$task_id")" \
  "worktree_path=$(quote_value "$worktree_path")" \
  "output_path=$(quote_value "$result_path")"

set +e
(
  cd "$worktree_path"
  "$codex_bin" exec --full-auto --skip-git-repo-check \
    --output-last-message "../../.ai/CODEX/RESULTS/$task_id.txt" \
    - < "../../.ai/CODEX/ORDERS/$task_id.md"
)
codex_status=$?
set -e

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

if [ "$post_status" -ne 0 ]; then
  exit "$post_status"
fi

exit "$codex_status"
