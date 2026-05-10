#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

if [[ -f "$ROOT_DIR/scripts/security/common.sh" ]]; then
  # shellcheck source=../security/common.sh
  source "$ROOT_DIR/scripts/security/common.sh"
fi

json_escape() {
  local value=${1-}
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

log_event() {
  local level=$1
  local event=$2
  local message=$3
  printf '{"level":"%s","event":"%s","message":"%s"}\n' \
    "$(json_escape "$level")" \
    "$(json_escape "$event")" \
    "$(json_escape "$message")" >&2
}

log_finding() {
  local path=$1
  local line=$2
  local label=$3
  local token=$4
  printf '{"level":"error","event":"secret_candidate","path":"%s","line":%s,"pattern":"%s","match":"%s"}\n' \
    "$(json_escape "$path")" \
    "$line" \
    "$(json_escape "$label")" \
    "$(json_escape "$(redact_token "$token")")" >&2
}

handle_error() {
  local status=$?
  local line=${BASH_LINENO[0]:-unknown}
  log_event "error" "script_error" "scanner failed at line $line with exit $status"
  exit 2
}

trap handle_error ERR

redact_token() {
  local token=$1
  local length=${#token}
  if (( length <= 12 )); then
    printf '[redacted]'
    return
  fi
  printf '%s...%s' "${token:0:4}" "${token:length-4:4}"
}

relative_path() {
  local path=$1
  case "$path" in
    "$ROOT_DIR"/*) printf '%s' "${path#"$ROOT_DIR"/}" ;;
    *) printf '%s' "$path" ;;
  esac
}

should_skip_path() {
  local path=$1
  local rel
  rel=$(relative_path "$path")

  case "$rel" in
    *.example.*|*.template.*|tests/fixtures/*|*/tests/fixtures/*)
      return 0
      ;;
  esac

  return 1
}

is_allowlisted_line() {
  local line=$1

  case "$line" in
    *"secret-scan: allow"*|*"gitleaks:allow"*|*"pragma: allowlist secret"*)
      return 0
      ;;
  esac

  return 1
}

collect_staged_files() {
  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_event "error" "script_error" "not inside a git work tree"
    exit 2
  fi

  git -C "$ROOT_DIR" diff --cached --name-only --diff-filter=ACMRT
}

scan_file_patterns() {
  local path=$1
  local rel=$2
  local line
  local line_no=0
  local found=0
  local patterns=(
    "OpenAI/Anthropic sk token|sk-[a-zA-Z0-9]{40,}"
    "Anthropic sk-ant token|sk-ant-[a-zA-Z0-9-]{50,}"
    "GitHub PAT|ghp_[a-zA-Z0-9]{36}"
    "GitHub OAuth token|gho_[a-zA-Z0-9]{36}"
    "Slack token|xox[baprs]-[a-zA-Z0-9-]{20,}"
    "AWS access key|AKIA[0-9A-Z]{16}"
    "PEM private key|-----BEGIN ([A-Z]+ )*PRIVATE KEY-----"
    "JWT|eyJ[a-zA-Z0-9_-]{20,}\\.[a-zA-Z0-9_-]{20,}\\.[a-zA-Z0-9_-]{20,}"
  )
  local spec
  local label
  local regex

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))

    if is_allowlisted_line "$line"; then
      continue
    fi

    for spec in "${patterns[@]}"; do
      label=${spec%%|*}
      regex=${spec#*|}
      if [[ $line =~ $regex ]]; then
        log_finding "$rel" "$line_no" "$label" "${BASH_REMATCH[0]}"
        found=1
        break
      fi
    done
  done < "$path"

  return "$found"
}

run_gitleaks_if_available() {
  local path=$1
  local rel=$2

  if [[ ${SECRET_SCAN_GITLEAKS:-1} == "0" ]]; then
    return 0
  fi

  if ! command -v gitleaks >/dev/null 2>&1; then
    return 0
  fi

  if gitleaks detect --no-git --redact --source "$path" >/dev/null 2>&1; then
    return 0
  fi

  log_event "error" "gitleaks_candidate" "gitleaks reported a secret candidate in $rel"
  return 1
}

main() {
  local input_files=()
  local path
  local rel
  local scan_count=0
  local secret_found=0

  if (( "$#" > 0 )); then
    input_files=("$@")
  else
    while IFS= read -r path; do
      [[ -n "$path" ]] && input_files+=("$path")
    done < <(collect_staged_files)
  fi

  if (( ${#input_files[@]} == 0 )); then
    log_event "info" "scan_passed" "no staged files to scan"
    exit 0
  fi

  for path in "${input_files[@]}"; do
    [[ -n "$path" ]] || continue

    if [[ "$path" != /* ]]; then
      path="$ROOT_DIR/$path"
    fi

    rel=$(relative_path "$path")

    if should_skip_path "$path"; then
      log_event "info" "file_skipped" "skipped allowlisted path $rel"
      continue
    fi

    if [[ ! -f "$path" ]]; then
      log_event "info" "file_skipped" "skipped missing or non-regular path $rel"
      continue
    fi

    if [[ -s "$path" ]] && ! LC_ALL=C grep -Iq . "$path"; then
      log_event "info" "file_skipped" "skipped binary path $rel"
      continue
    fi

    scan_count=$((scan_count + 1))

    if ! scan_file_patterns "$path" "$rel"; then
      secret_found=1
    fi

    if ! run_gitleaks_if_available "$path" "$rel"; then
      secret_found=1
    fi
  done

  if (( secret_found == 1 )); then
    log_event "error" "scan_failed" "plain secret candidate detected; commit blocked"
    exit 1
  fi

  log_event "info" "scan_passed" "no plain secret candidates detected in $scan_count file(s)"
  exit 0
}

main "$@"
