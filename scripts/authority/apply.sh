#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/authority/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/authority/apply.sh --operation OPERATION --target TARGET --patch PATCH [--task-id TASK_ID] [--summary SUMMARY] [--impact IMPACT]
USAGE
  exit 2
}

operation=""
target=""
patch_file=""
task_id="T-UNKNOWN"
summary="OS mutation requires Owner approval"
impact="Mutation will be applied after Owner approval."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --operation)
      [[ $# -ge 2 ]] || usage
      operation="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || usage
      target="$2"
      shift 2
      ;;
    --patch|--diff-file)
      [[ $# -ge 2 ]] || usage
      patch_file="$2"
      shift 2
      ;;
    --task-id)
      [[ $# -ge 2 ]] || usage
      task_id="$2"
      shift 2
      ;;
    --summary)
      [[ $# -ge 2 ]] || usage
      summary="$2"
      shift 2
      ;;
    --impact)
      [[ $# -ge 2 ]] || usage
      impact="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$operation" ]] || usage
[[ -n "$target" ]] || usage
[[ -n "$patch_file" ]] || usage
[[ -r "$patch_file" ]] || die "patch file is not readable: $patch_file"

check_json="$("$SCRIPT_DIR/os-mutation-check.sh" --operation "$operation" --target "$target" --diff-file "$patch_file")"
allowed="$(jq -r '.allowed' <<<"$check_json")"
approval_required="$(jq -r '.approval_required' <<<"$check_json")"
next_step="$(jq -r '.next_step' <<<"$check_json")"
approval_json="{}"
approval_request_id=""

if [[ "$allowed" != "true" ]]; then
  if [[ "$approval_required" == "true" && "$next_step" == "request_approval" ]]; then
    set +e
    approval_json="$("$SCRIPT_DIR/approval-workflow.sh" \
      --task-id "$task_id" \
      --operation "$operation" \
      --target "$target" \
      --summary "$summary" \
      --impact "$impact" \
      --wait)"
    approval_status=$?
    set -e
    approval_decision="$(jq -r '.status' <<<"$approval_json")"
    approval_request_id="$(jq -r '.request_id // ""' <<<"$approval_json")"

    if [[ "$approval_status" -ne 0 || "$approval_decision" != "approved" ]]; then
      jq -n \
        --arg status "skipped" \
        --argjson decision "$check_json" \
        --argjson approval "$approval_json" \
        '{status: $status, decision: $decision, approval: $approval}'
      exit 3
    fi
  else
    jq -n \
      --arg status "rejected" \
      --argjson decision "$check_json" \
      '{status: $status, decision: $decision}'
    exit 4
  fi
fi

backup_json="{}"
if [[ -e "$REPO_ROOT/$(repo_relpath "$target")" ]]; then
  backup_json="$("$SCRIPT_DIR/backup.sh" --target "$target")"
fi

set +e
dry_run_json="$("$SCRIPT_DIR/dry-run.sh" --target "$target" --patch "$patch_file")"
dry_run_status=$?
set -e
dry_run_ok="$(jq -r '.ok' <<<"$dry_run_json")"
if [[ "$dry_run_status" -ne 0 || "$dry_run_ok" != "true" ]]; then
  if [[ -n "$approval_request_id" ]]; then
    "$SCRIPT_DIR/check-approval.sh" \
      --request-id "$approval_request_id" \
      --mark-applied-and-failed \
      --note "dry-run failed before apply" >/dev/null || true
  fi
  jq -n \
    --arg status "dry_run_failed" \
    --argjson decision "$check_json" \
    --argjson approval "$approval_json" \
    --argjson backup "$backup_json" \
    --argjson dry_run "$dry_run_json" \
    '{status: $status, decision: $decision, approval: $approval, backup: $backup, dry_run: $dry_run}'
  exit 5
fi

set +e
(cd "$REPO_ROOT" && git apply "$patch_file")
apply_status=$?
set -e

if [[ "$apply_status" -ne 0 ]]; then
  if [[ -n "$approval_request_id" ]]; then
    "$SCRIPT_DIR/check-approval.sh" \
      --request-id "$approval_request_id" \
      --mark-applied-and-failed \
      --note "git apply failed with status $apply_status" >/dev/null || true
  fi
  jq -n \
    --arg status "apply_failed" \
    --argjson decision "$check_json" \
    --argjson approval "$approval_json" \
    --argjson backup "$backup_json" \
    --argjson dry_run "$dry_run_json" \
    '{status: $status, decision: $decision, approval: $approval, backup: $backup, dry_run: $dry_run}'
  exit 6
fi

if [[ -n "$approval_request_id" ]]; then
  "$SCRIPT_DIR/check-approval.sh" --request-id "$approval_request_id" --mark-applied >/dev/null || true
fi

jq -n \
  --arg status "applied" \
  --argjson decision "$check_json" \
  --argjson approval "$approval_json" \
  --argjson backup "$backup_json" \
  --argjson dry_run "$dry_run_json" \
  '{status: $status, decision: $decision, approval: $approval, backup: $backup, dry_run: $dry_run}'
