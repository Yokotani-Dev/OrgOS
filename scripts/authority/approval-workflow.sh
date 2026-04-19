#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/authority/approval-workflow.sh --task-id TASK_ID --operation OPERATION --target TARGET --summary SUMMARY --impact IMPACT [--wait] [--poll-interval SECONDS] [--timeout-seconds SECONDS] [--emergency]
USAGE
  exit 2
}

die() {
  echo "error: $*" >&2
  exit 1
}

task_id=""
operation=""
target=""
summary=""
impact=""
wait=false
poll_interval=30
timeout_seconds=86400
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
    --wait)
      wait=true
      shift
      ;;
    --poll-interval)
      [[ $# -ge 2 ]] || usage
      poll_interval="$2"
      shift 2
      ;;
    --timeout-seconds)
      [[ $# -ge 2 ]] || usage
      timeout_seconds="$2"
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
[[ "$poll_interval" =~ ^[0-9]+$ ]] || die "poll interval must be seconds"
[[ "$timeout_seconds" =~ ^[0-9]+$ ]] || die "timeout must be seconds"

request_args=(
  --task-id "$task_id"
  --operation "$operation"
  --target "$target"
  --summary "$summary"
  --impact "$impact"
)
if [[ "$emergency" == true ]]; then
  request_args+=(--emergency)
fi

request_id="$("$SCRIPT_DIR/request-approval.sh" "${request_args[@]}")"

if [[ "$wait" != true ]]; then
  printf '%s\n' "$request_id"
  exit 0
fi

deadline=$((SECONDS + timeout_seconds))
last_json=""

while :; do
  last_json="$("$SCRIPT_DIR/check-approval.sh" --request-id "$request_id")"
  status="$(jq -r '.status' <<<"$last_json")"
  case "$status" in
    approved|rejected|expired|applied|applied_and_failed)
      printf '%s\n' "$last_json"
      [[ "$status" == "approved" ]] && exit 0
      exit 1
      ;;
    pending)
      ;;
    *)
      printf '%s\n' "$last_json"
      exit 1
      ;;
  esac

  if [[ "$SECONDS" -ge "$deadline" ]]; then
    last_json="$("$SCRIPT_DIR/check-approval.sh" --request-id "$request_id")"
    printf '%s\n' "$last_json"
    exit 1
  fi

  sleep "$poll_interval"
done
