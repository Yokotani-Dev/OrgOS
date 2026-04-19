#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/authority/request-approval.sh --task-id TASK_ID --operation OPERATION --target TARGET --summary SUMMARY --impact IMPACT [--emergency]
USAGE
  exit 2
}

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

audit_approval() {
  local event="$1"
  local request_id="$2"
  local status="$3"
  local audit_dir="$REPO_ROOT/.ai/AUDIT"
  local audit_file="$audit_dir/approval-$(date +%F).log"

  mkdir -p "$audit_dir"
  jq -cn \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg event "$event" \
    --arg request_id "$request_id" \
    --arg task_id "$task_id" \
    --arg operation "$operation" \
    --arg target "$(repo_relpath "$target")" \
    --arg status "$status" \
    '{
      timestamp: $timestamp,
      event: $event,
      request_id: $request_id,
      task_id: $task_id,
      operation: $operation,
      target: $target,
      status: $status
    }' >> "$audit_file"
}

task_id=""
operation=""
target=""
summary=""
impact=""
emergency=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)
      [[ $# -ge 2 ]] || usage
      task_id="$2"
      shift 2
      ;;
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
    --emergency)
      emergency=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$task_id" ]] || usage
[[ -n "$operation" ]] || usage
[[ -n "$target" ]] || usage
[[ -n "$summary" ]] || usage
[[ -n "$impact" ]] || usage

command -v jq >/dev/null 2>&1 || die "jq is required"
command -v ruby >/dev/null 2>&1 || die "ruby is required"

request_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
requested_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
display_time="$(date '+%Y-%m-%d %H:%M')"
approvals_dir="$REPO_ROOT/.ai/APPROVALS"
approval_file="$approvals_dir/$request_id.yaml"
owner_inbox="$REPO_ROOT/.ai/OWNER_INBOX.md"

mkdir -p "$approvals_dir" "$REPO_ROOT/.ai/AUDIT"

REQUEST_ID="$request_id" \
TASK_ID="$task_id" \
OPERATION="$operation" \
TARGET="$(repo_relpath "$target")" \
SUMMARY="$summary" \
IMPACT="$impact" \
REQUESTED_AT="$requested_at" \
EMERGENCY="$emergency" \
ruby -ryaml -rfileutils -e '
  file = ARGV.fetch(0)
  data = {
    "request_id" => ENV.fetch("REQUEST_ID"),
    "task_id" => ENV.fetch("TASK_ID"),
    "operation" => ENV.fetch("OPERATION"),
    "target" => ENV.fetch("TARGET"),
    "summary" => ENV.fetch("SUMMARY"),
    "impact" => ENV.fetch("IMPACT"),
    "status" => "pending",
    "requested_at" => ENV.fetch("REQUESTED_AT"),
    "responded_at" => nil,
    "response" => nil,
    "applied_at" => nil,
    "failure_at" => nil,
    "failure_note" => nil,
    "emergency" => ENV.fetch("EMERGENCY") == "true",
    "emergency_recorded_at" => nil
  }
  File.write(file, YAML.dump(data))
' "$approval_file"

{
  printf '\n## [APPROVAL REQUEST] %s (%s)\n' "$task_id" "$display_time"
  printf -- '- Operation: %s\n' "$operation"
  printf -- '- Target: %s\n' "$(repo_relpath "$target")"
  printf -- '- Summary: %s\n' "$summary"
  printf -- '- Impact: %s\n' "$impact"
  printf -- '- Request ID: %s\n' "$request_id"
  printf -- '- Status: pending\n'
  printf -- '- Response: `echo "approve %s" >> .ai/OWNER_COMMENTS.md`\n' "$request_id"
} >> "$owner_inbox"

audit_approval "requested" "$request_id" "pending"
printf '%s\n' "$request_id"
