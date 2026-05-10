#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: bash scripts/codex/cleanup-worktrees.sh [--all] [--dry-run]

Without arguments, removes .worktrees/T-OS-* worktrees older than 24 hours.
Options:
  --all      remove every worktree under .worktrees/ after confirmation
  --dry-run  print removal targets without deleting anything
USAGE
}

log() {
  level=$1
  event=$2
  shift 2

  printf 'ts=%s level=%s event=%s' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$level" "$event"
  while [ "$#" -gt 0 ]; do
    printf ' %s' "$1"
    shift
  done
  printf '\n'
}

quote_value() {
  value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '"%s"' "$value"
}

remove_target() {
  target=$1

  if [ "$dry_run" -eq 1 ]; then
    log info cleanup_dry_run "worktree_path=$(quote_value "$target")" cleanup_status=pending
    return 0
  fi

  if remove_output=$(git -C "$repo_root" worktree remove --force "$target" 2>&1); then
    log info cleanup_removed "worktree_path=$(quote_value "$target")" cleanup_status=removed
  elif [ -d "$target" ]; then
    rm -rf -- "$target"
    log info cleanup_removed \
      "worktree_path=$(quote_value "$target")" \
      cleanup_status=removed_non_worktree \
      "git_error=$(quote_value "$remove_output")"
  else
    log error cleanup_failed \
      "worktree_path=$(quote_value "$target")" \
      cleanup_status=failed \
      "git_error=$(quote_value "$remove_output")"
    return 1
  fi
}

all=0
dry_run=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      all=1
      ;;
    --dry-run)
      dry_run=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'cleanup-worktrees.sh: unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ]; then
  printf 'cleanup-worktrees.sh: must be run inside a git repository\n' >&2
  exit 1
fi

worktree_dir="$repo_root/.worktrees"
if [ ! -d "$worktree_dir" ]; then
  log info cleanup_noop "worktree_dir=$(quote_value "$worktree_dir")" cleanup_status=noop
  exit 0
fi

if [ "$all" -eq 1 ] && [ "$dry_run" -ne 1 ]; then
  printf 'Remove all worktrees under %s? Type "DELETE" to continue: ' "$worktree_dir" >&2
  read -r answer
  if [ "$answer" != "DELETE" ]; then
    log info cleanup_cancelled "worktree_dir=$(quote_value "$worktree_dir")" cleanup_status=cancelled
    exit 1
  fi
fi

targets=()
if [ "$all" -eq 1 ]; then
  while IFS= read -r path; do
    targets+=("$path")
  done < <(find "$worktree_dir" -mindepth 1 -maxdepth 1 -type d | sort)
else
  while IFS= read -r path; do
    targets+=("$path")
  done < <(find "$worktree_dir" -mindepth 1 -maxdepth 1 -type d -name 'T-OS-*' -mtime +0 | sort)
fi

if [ "${#targets[@]}" -eq 0 ]; then
  log info cleanup_noop "worktree_dir=$(quote_value "$worktree_dir")" cleanup_status=noop
  exit 0
fi

failed=0
for target in "${targets[@]}"; do
  if ! remove_target "$target"; then
    failed=1
  fi
done

git -C "$repo_root" worktree prune >/dev/null 2>&1 || true

if [ "$failed" -ne 0 ]; then
  exit 1
fi
