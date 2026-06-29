#!/usr/bin/env bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
TASK_ID="T-OS-329"
SCHEDULER_DIR="${ORGOS_SCHEDULER_DIR:-$REPO_ROOT/.ai/_machine/scheduler}"
RUNS_DIR="$SCHEDULER_DIR/runs"
LOCK_DIR="$SCHEDULER_DIR/run.lock"
STAGE="${ORGOS_SCHEDULER_STAGE:-shadow}"
LAST_FILTER="${ORGOS_SCHEDULER_LAST:-7d}"
TRIGGER="${ORGOS_SCHEDULER_TRIGGER:-manual}"
RETRIES="${ORGOS_SCHEDULER_RETRIES:-1}"
CIRCUIT_BREAKER="${CIRCUIT_BREAKER:-$REPO_ROOT/scripts/evolution/circuit-breaker.sh}"
DEFAULT_TIMEOUT_SECONDS=1800
STEP_TIMEOUT_SECONDS=""
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash scripts/scheduler/run-detection.sh [--dry-run] [--stage shadow|canary|progressive] [--last 7d]

Runs the OrgOS always-on detection pipeline:
  detect.sh --json -> synthesize.sh -> apply.sh --stage <stage>

Defaults are shadow stage and production .ai/_machine/evolution paths. --dry-run isolates
events, proposals, and application records under .ai/_machine/scheduler/dry-run.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      TRIGGER="${ORGOS_SCHEDULER_TRIGGER:-dry-run}"
      shift
      ;;
    --stage)
      STAGE="${2:-}"
      if [[ -z "$STAGE" ]]; then
        echo "--stage requires shadow, canary, or progressive" >&2
        exit 64
      fi
      shift 2
      ;;
    --last)
      LAST_FILTER="${2:-}"
      if [[ -z "$LAST_FILTER" ]]; then
        echo "--last requires a duration such as 7d" >&2
        exit 64
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

case "$STAGE" in
  shadow|canary|progressive) ;;
  *)
    echo "Unsupported stage: $STAGE" >&2
    exit 64
    ;;
esac

mkdir -p "$RUNS_DIR"
TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_ID="scheduler-$TIMESTAMP-$$"
RUN_LOG="$RUNS_DIR/$TIMESTAMP.log"
RUN_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orgos-scheduler.XXXXXX")"

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

log_event() {
  local level="$1"
  local event="$2"
  local message="$3"
  local extra="${4:-}"
  local escaped_message line
  escaped_message="$(json_escape "$message")"
  if [[ -n "$extra" ]]; then
    line="$(printf '{"ts":"%s","level":"%s","task_id":"%s","run_id":"%s","trigger":"%s","stage":"%s","event":"%s","message":%s,%s}' \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$level" "$TASK_ID" "$RUN_ID" "$TRIGGER" "$STAGE" "$event" "$escaped_message" "$extra"
    )"
  else
    line="$(printf '{"ts":"%s","level":"%s","task_id":"%s","run_id":"%s","trigger":"%s","stage":"%s","event":"%s","message":%s}' \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$level" "$TASK_ID" "$RUN_ID" "$TRIGGER" "$STAGE" "$event" "$escaped_message"
    )"
  fi
  printf '%s\n' "$line"
  printf '%s\n' "$line" >> "$RUN_LOG"
}

classify_failure() {
  local exit_code="$1"
  local output_file="$2"
  local output=""
  if [[ -f "$output_file" ]]; then
    output="$(tr '[:upper:]' '[:lower:]' < "$output_file")"
  fi

  # circuit_breaker / iron_law を lock より先に判定する。lock パターンは実際のロック
  # 文言のみに限定し、"blocked"(=b+lock) への誤マッチを避ける（旧: bare 'lock'）。
  if grep -qiE 'circuit_breaker|circuit breaker' <<<"$output"; then
    printf 'circuit_breaker'
  elif [[ "$exit_code" -eq 3 ]] || grep -qiE 'iron_law|iron law|protected|proposal_rejected|owner_only|approval_required' <<<"$output"; then
    printf 'iron_law'
  elif [[ "$exit_code" -eq 73 ]] || grep -qiE 'another .* run is still active|scheduler lock|stale lock|file lock|flock|lock_active|lock_failed|already running|resource busy' <<<"$output"; then
    printf 'lock'
  elif [[ "$exit_code" -eq 124 ]] || grep -qiE 'timed? out|timeout after|timeout' <<<"$output"; then
    printf 'timeout'
  elif [[ "$exit_code" -eq 69 || "$exit_code" -eq 75 ]] || grep -qiE 'network|timed? out|timeout|temporary failure|could not resolve|connection refused|curl|http [45][0-9][0-9]' <<<"$output"; then
    printf 'network'
  else
    printf 'unknown'
  fi
}

exit_for_class() {
  case "$1" in
    lock) printf '73' ;;
    iron_law) printf '78' ;;
    timeout) printf '75' ;;
    circuit_breaker) printf '75' ;;
    network) printf '75' ;;
    *) printf '70' ;;
  esac
}

recovery_for_class() {
  case "$1" in
    lock) printf 'Stale locks are removed automatically; active locks should be retried after the current run finishes.' ;;
    iron_law) printf 'Automatic apply is stopped. Manager/Owner review is required before retrying.' ;;
    timeout) printf 'The step timed out and the Self-Evolution circuit breaker has been tripped for Owner review.' ;;
    circuit_breaker) printf 'Automatic apply is stopped until Owner review restores the circuit breaker.' ;;
    network) printf 'The scheduler retries transient network failures once, then the next launchd/cron/Actions trigger retries.' ;;
    *) printf 'Inspect the run log and rerun with --dry-run before enabling broader rollout.' ;;
  esac
}

scheduler_timeout_seconds() {
  python3 - "$REPO_ROOT/.ai/_machine/evolution/circuit-breaker.yaml" "$DEFAULT_TIMEOUT_SECONDS" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
default_seconds = int(sys.argv[2])
try:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) if path.exists() else {}
except yaml.YAMLError:
    data = {}
if not isinstance(data, dict):
    data = {}
limits = data.get("limits") if isinstance(data.get("limits"), dict) else {}
try:
    minutes = int(limits.get("scheduler_timeout_minutes") or default_seconds // 60)
except (TypeError, ValueError):
    minutes = default_seconds // 60
if minutes < 1:
    minutes = default_seconds // 60
print(minutes * 60)
PY
}

timeout_command() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
    return $?
  fi
  python3 - "$seconds" "$@" <<'PY'
from __future__ import annotations

import subprocess
import sys

timeout_seconds = float(sys.argv[1])
command = sys.argv[2:]
try:
    completed = subprocess.run(command, timeout=timeout_seconds)
except subprocess.TimeoutExpired:
    print(f"timeout after {int(timeout_seconds)} seconds: {' '.join(command)}", file=sys.stderr)
    raise SystemExit(124)
raise SystemExit(completed.returncode)
PY
}

trip_circuit_breaker() {
  local reason="$1"
  if bash "$CIRCUIT_BREAKER" trip "$reason" >> "$RUN_LOG" 2>&1; then
    log_event "warn" "circuit_breaker_tripped" "Circuit breaker tripped after scheduler failure." "\"reason\":$(json_escape "$reason")"
  else
    log_event "error" "circuit_breaker_trip_failed" "Failed to trip circuit breaker after scheduler failure." "\"reason\":$(json_escape "$reason")"
  fi
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    {
      printf 'pid=%s\n' "$$"
      printf 'run_id=%s\n' "$RUN_ID"
      printf 'started_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } > "$LOCK_DIR/meta"
    return 0
  fi

  local old_pid=""
  if [[ -f "$LOCK_DIR/meta" ]]; then
    old_pid="$(awk -F= '$1 == "pid" {print $2}' "$LOCK_DIR/meta" 2>/dev/null || true)"
  fi
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    log_event "error" "lock_active" "Another scheduler run is still active." '"error_class":"lock","recovery":"retry_after_active_run"'
    exit 73
  fi

  rm -rf "$LOCK_DIR"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    {
      printf 'pid=%s\n' "$$"
      printf 'run_id=%s\n' "$RUN_ID"
      printf 'started_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      printf 'recovered_stale_lock=true\n'
    } > "$LOCK_DIR/meta"
    log_event "warn" "lock_recovered" "Removed stale scheduler lock before starting."
    return 0
  fi

  log_event "error" "lock_failed" "Unable to acquire scheduler lock." '"error_class":"lock","recovery":"manual_lock_inspection"'
  exit 73
}

release_lock() {
  rm -rf "$LOCK_DIR"
}

append_step_output() {
  local label="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  local content
  if [[ -s "$stdout_file" ]]; then
    content="$(cat "$stdout_file")"
    printf '{"ts":"%s","level":"debug","task_id":"%s","run_id":"%s","trigger":"%s","stage":"%s","event":"step_output","message":"captured step stdout","step":%s,"stream":"stdout","content":%s}\n' \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$TASK_ID" "$RUN_ID" "$TRIGGER" "$STAGE" "$(json_escape "$label")" "$(json_escape "$content")" >> "$RUN_LOG"
  fi
  if [[ -s "$stderr_file" ]]; then
    content="$(cat "$stderr_file")"
    printf '{"ts":"%s","level":"debug","task_id":"%s","run_id":"%s","trigger":"%s","stage":"%s","event":"step_output","message":"captured step stderr","step":%s,"stream":"stderr","content":%s}\n' \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$TASK_ID" "$RUN_ID" "$TRIGGER" "$STAGE" "$(json_escape "$label")" "$(json_escape "$content")" >> "$RUN_LOG"
  fi
}

run_step() {
  local label="$1"
  shift
  local attempt=1
  local stdout_file stderr_file combined_file rc error_class recovery exit_code

  while true; do
    stdout_file="$RUN_TMP_DIR/$label.$attempt.stdout"
    stderr_file="$RUN_TMP_DIR/$label.$attempt.stderr"
    combined_file="$RUN_TMP_DIR/$label.$attempt.combined"
    log_event "info" "${label}_started" "Starting $label step." "\"attempt\":$attempt"
    timeout_command "$STEP_TIMEOUT_SECONDS" "$@" >"$stdout_file" 2>"$stderr_file"
    rc=$?
    append_step_output "$label attempt $attempt" "$stdout_file" "$stderr_file"
    cat "$stdout_file" "$stderr_file" > "$combined_file"

    if [[ "$rc" -eq 0 ]]; then
      log_event "info" "${label}_completed" "$label step completed." "\"attempt\":$attempt"
      STEP_STDOUT="$stdout_file"
      STEP_STDERR="$stderr_file"
      return 0
    fi

    error_class="$(classify_failure "$rc" "$combined_file")"
    recovery="$(recovery_for_class "$error_class")"
    log_event "error" "${label}_failed" "$label step failed." "\"attempt\":$attempt,\"exit_code\":$rc,\"error_class\":\"$error_class\",\"recovery\":$(json_escape "$recovery")"

    if [[ "$error_class" == "timeout" ]]; then
      trip_circuit_breaker "scheduler step '$label' timed out after ${STEP_TIMEOUT_SECONDS}s"
    fi

    if [[ "$error_class" == "network" && "$attempt" -le "$RETRIES" ]]; then
      log_event "warn" "${label}_retrying" "Retrying after transient network failure." "\"next_attempt\":$((attempt + 1))"
      sleep 2
      attempt=$((attempt + 1))
      continue
    fi

    exit_code="$(exit_for_class "$error_class")"
    exit "$exit_code"
  done
}

main() {
  : > "$RUN_LOG"
  trap 'release_lock; rm -rf "$RUN_TMP_DIR"' EXIT
  cd "$REPO_ROOT"
  STEP_TIMEOUT_SECONDS="${ORGOS_SCHEDULER_TIMEOUT_SECONDS:-$(scheduler_timeout_seconds)}"

  acquire_lock
  log_event "info" "run_started" "Scheduler run started." "\"dry_run\":$DRY_RUN,\"log_path\":$(json_escape "${RUN_LOG#$REPO_ROOT/}"),\"step_timeout_seconds\":$STEP_TIMEOUT_SECONDS"

  local events_path="$REPO_ROOT/.ai/_machine/evolution/events.jsonl"
  local proposals_dir="$REPO_ROOT/.ai/_machine/evolution/proposals"
  local applied_dir="$REPO_ROOT/.ai/_machine/evolution/applied"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    local dry_root="$SCHEDULER_DIR/dry-run/$TIMESTAMP"
    mkdir -p "$dry_root/proposals" "$dry_root/applied"
    events_path="$dry_root/events.jsonl"
    proposals_dir="$dry_root/proposals"
    applied_dir="$dry_root/applied"
    log_event "info" "dry_run_paths_ready" "Dry-run state is isolated under .ai/_machine/scheduler/dry-run." "\"dry_run_root\":$(json_escape "${dry_root#$REPO_ROOT/}")"
  fi

  run_step "detect" env EVENTS_PATH="$events_path" bash scripts/evolution/detect.sh --json

  run_step "synthesize" env EVENTS_PATH="$events_path" OUTPUT_DIR="$proposals_dir" bash scripts/evolution/synthesize.sh --last "$LAST_FILTER"
  local proposal_ref
  proposal_ref="$(awk 'NF {line=$0} END {print line}' "$STEP_STDOUT")"
  if [[ -z "$proposal_ref" ]]; then
    log_event "error" "proposal_missing" "Synthesis completed without a proposal path." '"error_class":"unknown","recovery":"inspect_synthesize_stdout"'
    exit 70
  fi
  log_event "info" "proposal_selected" "Proposal selected for shadow apply." "\"proposal_ref\":$(json_escape "$proposal_ref")"

  run_step "apply" env PROPOSAL_DIR="$proposals_dir" APPLIED_DIR="$applied_dir" bash scripts/evolution/apply.sh "$proposal_ref" --stage "$STAGE"

  log_event "info" "run_completed" "Scheduler run completed." "\"proposal_ref\":$(json_escape "$proposal_ref")"
}

main "$@"
