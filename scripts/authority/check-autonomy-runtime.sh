#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: bash scripts/authority/check-autonomy-runtime.sh <TASK_ID>

Checks a task autonomy_level against the Authority Layer risk/reversibility
decision matrix before runtime delegation.
USAGE
}

log() {
  local level event
  level=$1
  event=$2
  shift 2

  printf 'ts=%s level=%s event=%s' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$level" "$event" >&2
  while [ "$#" -gt 0 ]; do
    printf ' %s' "$1" >&2
    shift
  done
  printf '\n' >&2
}

quote_value() {
  local value
  value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '"%s"' "$value"
}

validate_task_id() {
  local task_id
  task_id=$1

  case "$task_id" in
    ""|.*|*/*|*\\*|*-)
      return 1
      ;;
  esac

  case "$task_id" in
    *[!A-Za-z0-9._-]*)
      return 1
      ;;
  esac
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

task_id=$1
if ! validate_task_id "$task_id"; then
  printf 'check-autonomy-runtime.sh: invalid TASK_ID: %s\n' "$task_id" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${ORGOS_REPO_ROOT:-$(cd "$script_dir/../.." && pwd)}"
tasks_file="${ORGOS_TASKS_FILE:-$repo_root/.ai/TASKS.yaml}"
authority_file="${ORGOS_AUTHORITY_FILE:-$repo_root/.claude/rules/authority-layer.md}"

if [ ! -r "$tasks_file" ]; then
  log error autonomy_runtime_failed \
    "task_id=$(quote_value "$task_id")" \
    "reason=$(quote_value "TASKS file is not readable")" \
    "path=$(quote_value "$tasks_file")"
  exit 1
fi

if [ ! -r "$authority_file" ]; then
  log error autonomy_runtime_failed \
    "task_id=$(quote_value "$task_id")" \
    "reason=$(quote_value "authority-layer.md is not readable")" \
    "path=$(quote_value "$authority_file")"
  exit 1
fi

log info autonomy_runtime_start \
  "task_id=$(quote_value "$task_id")" \
  "tasks_file=$(quote_value "$tasks_file")" \
  "authority_file=$(quote_value "$authority_file")"

if ! result_json=$(
  TASK_ID="$task_id" TASKS_FILE="$tasks_file" ruby -r yaml -r json <<'RUBY'
task_id = ENV.fetch("TASK_ID")
tasks_file = ENV.fetch("TASKS_FILE")

rank = {
  "silent_execute" => 0,
  "execute_with_report" => 1,
  "ask_before_execute" => 2,
  "owner_only" => 3
}

def expected_autonomy(risk_level, reversibility, operation)
  return "owner_only" if risk_level == "critical"
  return "owner_only" if operation == "os_mutation_in_core" || risk_level == "os_mutation_in_core"
  return "execute_with_report" if (operation == "os_mutation_in_new" || risk_level == "os_mutation_in_new") && reversibility == "reversible"

  case [risk_level, reversibility]
  when ["high", "irreversible"]
    "owner_only"
  when ["high", "reversible"]
    "ask_before_execute"
  when ["medium", "irreversible"]
    "ask_before_execute"
  when ["medium", "reversible"]
    "execute_with_report"
  when ["low", "irreversible"]
    "execute_with_report"
  else
    "silent_execute"
  end
end

data = YAML.load_file(tasks_file)
task = data.fetch("tasks").find { |item| item.is_a?(Hash) && item["id"] == task_id }
unless task
  puts JSON.generate(status: "failed", errors: ["task not found in .ai/TASKS.yaml"])
  exit 0
end

autonomy_level = task["autonomy_level"].to_s
risk_level = task["risk_level"].to_s
reversibility = task["reversibility"].to_s
operation = task["operation"].to_s
expected = expected_autonomy(risk_level, reversibility, operation)
errors = []
warnings = []

if risk_level == "critical" && autonomy_level != "owner_only"
  errors << "risk_level=critical requires autonomy_level=owner_only"
end

if risk_level == "high" && reversibility == "irreversible" && autonomy_level != "owner_only"
  errors << "risk_level=high with reversibility=irreversible requires autonomy_level=owner_only"
end

if autonomy_level == "silent_execute" && risk_level == "high" && reversibility == "irreversible"
  errors << "silent_execute is forbidden for high irreversible work"
end

if rank.key?(autonomy_level)
  if rank.fetch(autonomy_level) < rank.fetch(expected)
    errors << "autonomy_level=#{autonomy_level} is less restrictive than matrix outcome #{expected}"
  elsif rank.fetch(autonomy_level) > rank.fetch(expected)
    warnings << "autonomy_level=#{autonomy_level} is more restrictive than matrix outcome #{expected}"
  end
else
  errors << "unknown autonomy_level: #{autonomy_level}"
end

puts JSON.generate(
  status: errors.empty? ? "passed" : "failed",
  task_id: task_id,
  autonomy_level: autonomy_level,
  risk_level: risk_level,
  reversibility: reversibility,
  operation: operation,
  expected_autonomy_level: expected,
  errors: errors,
  warnings: warnings
)
RUBY
); then
  log error autonomy_runtime_failed \
    "task_id=$(quote_value "$task_id")" \
    "reason=$(quote_value "failed to parse task metadata")"
  exit 1
fi

status=$(printf '%s\n' "$result_json" | jq -r '.status')
autonomy_level=$(printf '%s\n' "$result_json" | jq -r '.autonomy_level // ""')
risk_level=$(printf '%s\n' "$result_json" | jq -r '.risk_level // ""')
reversibility=$(printf '%s\n' "$result_json" | jq -r '.reversibility // ""')
expected=$(printf '%s\n' "$result_json" | jq -r '.expected_autonomy_level // ""')

if [ "$status" != "passed" ]; then
  printf '%s\n' "$result_json" | jq -r '.errors[] | "check-autonomy-runtime.sh: error: " + .' >&2
  log error autonomy_runtime_blocked \
    "task_id=$(quote_value "$task_id")" \
    "autonomy_level=$(quote_value "$autonomy_level")" \
    "risk_level=$(quote_value "$risk_level")" \
    "reversibility=$(quote_value "$reversibility")" \
    "expected=$(quote_value "$expected")"
  exit 1
fi

warning_count=$(printf '%s\n' "$result_json" | jq -r '.warnings | length')
if [ "$warning_count" -gt 0 ]; then
  printf '%s\n' "$result_json" | jq -r '.warnings[] | "check-autonomy-runtime.sh: warning: " + .' >&2
fi

log info autonomy_runtime_passed \
  "task_id=$(quote_value "$task_id")" \
  "autonomy_level=$(quote_value "$autonomy_level")" \
  "risk_level=$(quote_value "$risk_level")" \
  "reversibility=$(quote_value "$reversibility")" \
  "expected=$(quote_value "$expected")"

exit 0
