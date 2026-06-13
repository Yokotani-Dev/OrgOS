#!/usr/bin/env bash

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_RED=$'\033[31m'
  C_YELLOW=$'\033[33m'
  C_GREEN=$'\033[32m'
  C_BLUE=$'\033[34m'
else
  C_RESET=''
  C_RED=''
  C_YELLOW=''
  C_GREEN=''
  C_BLUE=''
fi

log_info() {
  printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"
}

log_warn() {
  printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
}

log_error() {
  printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
}

log_success() {
  printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*"
}

require_python_yaml_or_skip() {
  if ! command -v python3 >/dev/null 2>&1; then
    log_warn "python3 が見つからないため lint をスキップします"
    return 1
  fi

  if ! python3 - <<'PY' >/dev/null 2>&1
import importlib.util
raise SystemExit(0 if importlib.util.find_spec("yaml") else 1)
PY
  then
    log_warn "PyYAML が見つからないため lint をスキップします"
    return 1
  fi

  return 0
}
