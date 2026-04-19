#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CONTROL_FILE="$REPO_ROOT/.ai/CONTROL.yaml"
AUTHORITY_FILE="$REPO_ROOT/.claude/rules/authority-layer.md"
AUTONOMY_SCHEMA="$REPO_ROOT/.claude/schemas/autonomy.yaml"
ROLE_MATRIX_SCHEMA="$REPO_ROOT/.claude/schemas/role-matrix.yaml"
APPROVAL_SCHEMA="$REPO_ROOT/.claude/schemas/approval-workflow.yaml"
KERNEL_FILES="$REPO_ROOT/.claude/evals/KERNEL_FILES"

die() {
  echo "error: $*" >&2
  exit 1
}

repo_relpath() {
  local path="$1"
  path="${path#"$REPO_ROOT"/}"
  path="${path#./}"
  printf '%s\n' "$path"
}

json_string() {
  jq -Rn --arg value "$1" '$value'
}

read_required_authority_inputs() {
  local file
  for file in "$CONTROL_FILE" "$AUTHORITY_FILE" "$AUTONOMY_SCHEMA" "$ROLE_MATRIX_SCHEMA" "$APPROVAL_SCHEMA"; do
    [[ -r "$file" ]] || die "required authority input is not readable: $(repo_relpath "$file")"
    sed -n '1p' "$file" >/dev/null
  done
}

control_allow_os_mutation() {
  awk -F: '
    $1 ~ /^[[:space:]]*allow_os_mutation[[:space:]]*$/ {
      value=$2
      sub(/#.*/, "", value)
      gsub(/[[:space:]"\047]/, "", value)
      print value
      exit
    }
  ' "$CONTROL_FILE"
}

protocol_contains() {
  local section="$1"
  local operation="$2"

  awk -v section="$section" -v operation="$operation" '
    $0 ~ "^[[:space:]]*" section ":" {
      in_section=1
      next
    }
    in_section && $0 ~ "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:" {
      in_section=0
    }
    in_section {
      item=$0
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      sub(/[[:space:]]*$/, "", item)
      if (item == operation) {
        found=1
      }
    }
    END {
      exit(found ? 0 : 1)
    }
  ' "$AUTHORITY_FILE"
}

is_protected_secret_target() {
  local target
  target="$(repo_relpath "$1")"

  [[ "$target" == ".env" ]] && return 0
  [[ "$target" == .env.* ]] && return 0
  [[ "$target" == secrets/* ]] && return 0
  return 1
}

is_kernel_target() {
  local target kernel
  target="$(repo_relpath "$1")"
  [[ -r "$KERNEL_FILES" ]] || return 1

  while IFS= read -r kernel; do
    kernel="${kernel%%#*}"
    kernel="${kernel#"${kernel%%[![:space:]]*}"}"
    kernel="${kernel%"${kernel##*[![:space:]]}"}"
    [[ -z "$kernel" ]] && continue
    if [[ "$target" == "$kernel" || "$target" == "$kernel"/* ]]; then
      return 0
    fi
  done < "$KERNEL_FILES"

  return 1
}

audit_json_line() {
  local operation="$1"
  local target="$2"
  local allowed="$3"
  local reason="$4"
  local autonomy_level="$5"
  local approval_required="$6"
  local next_step="$7"
  local audit_dir audit_file timestamp

  audit_dir="$REPO_ROOT/.ai/AUDIT"
  audit_file="$audit_dir/os-mutation-$(date +%F).log"
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  mkdir -p "$audit_dir"
  jq -cn \
    --arg timestamp "$timestamp" \
    --arg operation "$operation" \
    --arg target "$(repo_relpath "$target")" \
    --argjson allowed "$allowed" \
    --arg reason "$reason" \
    --arg autonomy_level "$autonomy_level" \
    --argjson approval_required "$approval_required" \
    --arg next_step "$next_step" \
    '{
      timestamp: $timestamp,
      operation: $operation,
      target: $target,
      allowed: $allowed,
      reason: $reason,
      autonomy_level: $autonomy_level,
      approval_required: $approval_required,
      next_step: $next_step
    }' >> "$audit_file"
}

emit_decision_json() {
  local allowed="$1"
  local reason="$2"
  local autonomy_level="$3"
  local approval_required="$4"
  local next_step="$5"

  jq -n \
    --argjson allowed "$allowed" \
    --arg reason "$reason" \
    --arg autonomy_level "$autonomy_level" \
    --argjson approval_required "$approval_required" \
    --arg next_step "$next_step" \
    '{
      allowed: $allowed,
      reason: $reason,
      autonomy_level: $autonomy_level,
      approval_required: $approval_required,
      next_step: $next_step
    }'
}
