#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage: bash scripts/session/load-ledger.sh --ledger user_profile|capabilities|goals|tasks
EOF
}

ledger=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ledger)
      [[ $# -ge 2 ]] || {
        echo "error: --ledger requires a value" >&2
        usage >&2
        exit 1
      }
      ledger="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "${ledger}" ]] || {
  echo "error: --ledger is required" >&2
  usage >&2
  exit 1
}

case "${ledger}" in
  user_profile) ledger_path=".ai/USER_PROFILE.yaml" ;;
  capabilities) ledger_path=".ai/CAPABILITIES.yaml" ;;
  goals) ledger_path=".ai/GOALS.yaml" ;;
  tasks) ledger_path=".ai/TASKS.yaml" ;;
  *)
    echo "error: unsupported ledger '${ledger}'" >&2
    usage >&2
    exit 1
    ;;
esac

full_path="${REPO_ROOT}/${ledger_path}"
[[ -f "${full_path}" ]] || {
  echo "error: ledger file not found: ${ledger_path}" >&2
  exit 1
}

cd "${REPO_ROOT}"

LEDGER_NAME="${ledger}" LEDGER_PATH="${ledger_path}" ruby_utf8 <<'RUBY'
# encoding: utf-8
require "date"
require "json"
require "time"
require "yaml"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

ledger = ENV.fetch("LEDGER_NAME")
path = ENV.fetch("LEDGER_PATH")
data = YAML.safe_load(File.read(path, encoding: "UTF-8"), permitted_classes: [Date, Time, Symbol], aliases: true)

payload = {
  ledger: ledger,
  path: path,
  loaded_at: Time.now.utc.iso8601,
  data: data
}

puts JSON.pretty_generate(payload)
RUBY
