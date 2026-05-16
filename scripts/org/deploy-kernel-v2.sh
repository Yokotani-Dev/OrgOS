#!/usr/bin/env bash
# Deploy the minimum OrgOS kernel v2 files into another project repository.
set -euo pipefail

KERNEL_VERSION="v0.2.0"
DEFAULT_MODE="enforce-protected-only"

COPY_FILES=(
  ".claude/hooks/pretool_policy.py"
  ".claude/hooks/policy_core.py"
  "scripts/codex/run-in-worktree.sh"
  "scripts/codex/post-exec-audit.sh"
  "scripts/codex/pre-exec-validate.sh"
  "scripts/codex/cleanup-worktrees.sh"
  "scripts/org/set-kernel-mode.sh"
  "scripts/org/integrator-commit.sh"
  "scripts/org/request-integration.sh"
  "scripts/org/acquire-lease.sh"
  "scripts/org/release-lease.sh"
  "scripts/org/list-leases.sh"
  "scripts/org/collect-artifacts.sh"
  "scripts/org/verify-artifact-manifest.py"
  "scripts/org/validate-tasks-yaml.py"
  "scripts/org/update-task.py"
  ".claude/schemas/artifact-manifest.v1.json"
  ".claude/schemas/integration-queue.v1.json"
  ".claude/schemas/lease.v1.json"
  ".claude/evals/KERNEL_FILES"
  ".ai/queue/integration/.gitkeep"
  ".ai/leases.gitkeep"
)

GENERATED_FILES=(
  ".orgos-kernel-version"
  ".claude/state/kernel-mode.json"
  ".ai/BOOTSTRAP-OVERRIDES.md"
)

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/org/deploy-kernel-v2.sh /path/to/target-repo [--mode warn|enforce-protected-only|enforce-all] [--dry-run] [--force]

Defaults:
  --mode enforce-protected-only
EOF
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit "${2:-1}"
}

is_valid_mode() {
  case "${1:-}" in
    warn|enforce-protected-only|enforce-all) return 0 ;;
    *) return 1 ;;
  esac
}

json_mode_value() {
  local deploy_mode="$1"
  case "$deploy_mode" in
    warn) printf 'warn' ;;
    enforce-protected-only) printf 'warn' ;;
    enforce-all) printf 'enforce' ;;
    *) return 1 ;;
  esac
}

protected_only_invariant_mode() {
  local invariant="$1"
  case "$invariant" in
    IntegratorOnlyCommit|ProtectedBranchNoTouch) printf 'enforce' ;;
    OwnerApprovalForIrreversibleOps) printf 'disabled' ;;
    *) printf 'warn' ;;
  esac
}

invariant_mode() {
  local deploy_mode="$1"
  local invariant="$2"
  case "$deploy_mode" in
    warn)
      printf 'warn'
      ;;
    enforce-protected-only)
      protected_only_invariant_mode "$invariant"
      ;;
    enforce-all)
      printf 'enforce'
      ;;
    *)
      return 1
      ;;
  esac
}

write_kernel_mode() {
  local mode_file="$1"
  local deploy_mode="$2"
  local default_mode
  default_mode=$(json_mode_value "$deploy_mode")

  cat >"$mode_file" <<EOF
{
  "schema_version": "orgos.kernel-mode.v2",
  "default": "$default_mode",
  "invariants": {
    "IntegratorOnlyCommit": "$(invariant_mode "$deploy_mode" "IntegratorOnlyCommit")",
    "PerTaskWorktree": "$(invariant_mode "$deploy_mode" "PerTaskWorktree")",
    "ProtectedBranchNoTouch": "$(invariant_mode "$deploy_mode" "ProtectedBranchNoTouch")",
    "LeaseBeforeWrite": "$(invariant_mode "$deploy_mode" "LeaseBeforeWrite")",
    "StateMutationViaOrgTool": "$(invariant_mode "$deploy_mode" "StateMutationViaOrgTool")",
    "DurableArtifactBeforeCleanup": "$(invariant_mode "$deploy_mode" "DurableArtifactBeforeCleanup")",
    "OwnerApprovalForIrreversibleOps": "$(invariant_mode "$deploy_mode" "OwnerApprovalForIrreversibleOps")",
    "DangerousShell": "$(invariant_mode "$deploy_mode" "DangerousShell")",
    "KernelSelfModification": "$(invariant_mode "$deploy_mode" "KernelSelfModification")",
    "IntegratorIsScriptNotAgent": "$(invariant_mode "$deploy_mode" "IntegratorIsScriptNotAgent")"
  }
}
EOF
}

write_bootstrap_template() {
  local bootstrap_file="$1"
  cat >"$bootstrap_file" <<'EOF'
# Bootstrap Overrides

## Purpose
Project-local record of explicitly approved bootstrap deviations while rolling out kernel v2.

## Overrides
EOF
}

copy_one_file() {
  local source_root="$1"
  local target_root="$2"
  local rel="$3"
  local source_path="$source_root/$rel"
  local target_path="$target_root/$rel"

  mkdir -p "$(dirname "$target_path")"
  cp -p "$source_path" "$target_path"
}

main() {
  local script_dir source_root target_arg target_root git_root
  local mode="$DEFAULT_MODE"
  local dry_run=0
  local force=0
  local -a conflicts
  local -a missing_sources
  local rel

  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  source_root=$(cd "$script_dir/../.." && pwd)

  if [ "$#" -lt 1 ]; then
    usage
    exit 2
  fi

  target_arg="$1"
  shift

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode)
        [ "$#" -ge 2 ] || { usage; exit 2; }
        mode="$2"
        is_valid_mode "$mode" || fail "invalid --mode '$mode'. Must be warn, enforce-protected-only, or enforce-all." 2
        shift 2
        ;;
      --mode=*)
        mode="${1#--mode=}"
        is_valid_mode "$mode" || fail "invalid --mode '$mode'. Must be warn, enforce-protected-only, or enforce-all." 2
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --force)
        force=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        fail "unknown argument '$1'" 2
        ;;
    esac
  done

  [ -d "$target_arg" ] || fail "target repo directory does not exist: $target_arg" 2
  if ! git_root=$(git -C "$target_arg" rev-parse --show-toplevel 2>/dev/null); then
    fail "target is not inside a git repository: $target_arg" 2
  fi
  target_root=$(cd "$git_root" && pwd)

  missing_sources=()
  for rel in "${COPY_FILES[@]}"; do
    if [ ! -f "$source_root/$rel" ]; then
      missing_sources+=("$rel")
    fi
  done
  if [ "${#missing_sources[@]}" -gt 0 ]; then
    printf 'Error: missing source kernel files:\n' >&2
    for rel in "${missing_sources[@]}"; do
      printf '  %s\n' "$rel" >&2
    done
    exit 1
  fi

  conflicts=()
  if [ "$force" -eq 0 ]; then
    for rel in "${COPY_FILES[@]}"; do
      if [ -e "$target_root/$rel" ]; then
        conflicts+=("$rel")
      fi
    done
    for rel in "${GENERATED_FILES[@]}"; do
      if [ -e "$target_root/$rel" ]; then
        conflicts+=("$rel")
      fi
    done
  fi

  if [ "$dry_run" -eq 1 ]; then
    printf 'DRY RUN: OrgOS kernel %s deployment plan\n' "$KERNEL_VERSION"
    printf 'Source: %s\n' "$source_root"
    printf 'Target: %s\n' "$target_root"
    printf 'Target version: %s\n' "$KERNEL_VERSION"
    printf 'Mode: %s\n' "$mode"
    printf 'Force: %s\n' "$force"
    printf 'Files to copy:\n'
    for rel in "${COPY_FILES[@]}"; do
      printf '  copy %s\n' "$rel"
    done
    printf 'Files to generate:\n'
    for rel in "${GENERATED_FILES[@]}"; do
      printf '  generate %s\n' "$rel"
    done
    if [ "${#conflicts[@]}" -gt 0 ]; then
      printf 'Conflicts without --force:\n'
      for rel in "${conflicts[@]}"; do
        printf '  %s\n' "$rel"
      done
    fi
    exit 0
  fi

  if [ "${#conflicts[@]}" -gt 0 ]; then
    printf 'Error: target already has kernel files. Re-run with --force to overwrite:\n' >&2
    for rel in "${conflicts[@]}"; do
      printf '  %s\n' "$rel" >&2
    done
    exit 3
  fi

  for rel in "${COPY_FILES[@]}"; do
    copy_one_file "$source_root" "$target_root" "$rel"
  done

  for rel in "${GENERATED_FILES[@]}"; do
    mkdir -p "$(dirname "$target_root/$rel")"
  done

  printf '%s\n' "$KERNEL_VERSION" >"$target_root/.orgos-kernel-version"
  write_kernel_mode "$target_root/.claude/state/kernel-mode.json" "$mode"
  write_bootstrap_template "$target_root/.ai/BOOTSTRAP-OVERRIDES.md"

  printf 'OrgOS kernel %s deployed\n' "$KERNEL_VERSION"
  printf 'Target: %s\n' "$target_root"
  printf 'Target version: %s\n' "$KERNEL_VERSION"
  printf 'Mode: %s\n' "$mode"
  printf 'Copied files: %s\n' "${#COPY_FILES[@]}"
  printf 'Generated files: %s\n' "${#GENERATED_FILES[@]}"
  printf 'Skipped files: 0\n'
  printf 'Files:\n'
  for rel in "${COPY_FILES[@]}"; do
    printf '  deployed %s\n' "$rel"
  done
  for rel in "${GENERATED_FILES[@]}"; do
    printf '  generated %s\n' "$rel"
  done
}

main "$@"
