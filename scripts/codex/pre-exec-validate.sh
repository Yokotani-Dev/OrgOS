#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: bash scripts/codex/pre-exec-validate.sh <TASK_ID>

Validates Codex delegation boundaries before a worker is launched.
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
  printf 'pre-exec-validate.sh: invalid TASK_ID: %s\n' "$task_id" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${ORGOS_REPO_ROOT:-$(cd "$script_dir/../.." && pwd)}"
tasks_file="${ORGOS_TASKS_FILE:-$repo_root/.ai/TASKS.yaml}"
kernel_files="${ORGOS_KERNEL_FILES:-$repo_root/.claude/evals/KERNEL_FILES}"

if [ ! -r "$tasks_file" ]; then
  log error validation_failed \
    "task_id=$(quote_value "$task_id")" \
    "reason=$(quote_value "TASKS file is not readable")" \
    "path=$(quote_value "$tasks_file")"
  exit 1
fi

if [ ! -r "$kernel_files" ]; then
  log error validation_failed \
    "task_id=$(quote_value "$task_id")" \
    "reason=$(quote_value "KERNEL_FILES is not readable")" \
    "path=$(quote_value "$kernel_files")"
  exit 1
fi

log info validation_start \
  "task_id=$(quote_value "$task_id")" \
  "tasks_file=$(quote_value "$tasks_file")" \
  "kernel_files=$(quote_value "$kernel_files")"

if ! validation_json=$(
  TASK_ID="$task_id" TASKS_FILE="$tasks_file" KERNEL_FILES="$kernel_files" ruby -r yaml -r json <<'RUBY'
task_id = ENV.fetch("TASK_ID")
tasks_file = ENV.fetch("TASKS_FILE")
kernel_files = ENV.fetch("KERNEL_FILES")

def normalize_path(path)
  path.to_s.strip.sub(%r{\A\./}, "").sub(%r{/+\z}, "/")
end

def broad_path?(path)
  %w[. ./ / * ** ./* ./**].include?(path)
end

def invalid_path?(path)
  return true if path.empty? || path.start_with?("/")

  parts = path.split("/")
  parts.include?("..")
end

def glob_path?(path)
  path.match?(/[*?\[]/)
end

def path_covers?(allowed_path, target)
  allowed_path = normalize_path(allowed_path)
  target = normalize_path(target)
  return true if allowed_path == target

  if glob_path?(allowed_path)
    flags = File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB
    return true if File.fnmatch?(allowed_path, target, flags)
  end

  prefix = allowed_path.end_with?("/") ? allowed_path : "#{allowed_path}/"
  target.start_with?(prefix)
end

data = YAML.load_file(tasks_file)
tasks = data.fetch("tasks")
task = tasks.find { |item| item.is_a?(Hash) && item["id"] == task_id }
unless task
  puts JSON.generate(status: "failed", errors: ["task not found in .ai/TASKS.yaml"])
  exit 0
end

allowed_paths = Array(task["allowed_paths"]).map { |path| normalize_path(path) }.reject(&:empty?)
kernel_paths = File.readlines(kernel_files, chomp: true).map do |line|
  stripped = line.sub(/#.*/, "").strip
  stripped.empty? ? nil : normalize_path(stripped)
end.compact

errors = []
warnings = []
autonomy_level = task["autonomy_level"].to_s
risk_level = task["risk_level"].to_s

if autonomy_level == "owner_only"
  errors << "autonomy_level=owner_only cannot be delegated to Codex"
end

if allowed_paths.empty?
  errors << "allowed_paths is empty"
end

allowed_paths.each do |path|
  if broad_path?(path)
    errors << "allowed_paths contains over-broad path: #{path}"
  elsif invalid_path?(path)
    errors << "allowed_paths contains invalid path: #{path}"
  end
end

allowed_paths.each do |allowed_path|
  kernel_paths.each do |kernel_path|
    next unless path_covers?(allowed_path, kernel_path) || path_covers?(kernel_path, allowed_path)

    errors << "allowed_paths overlaps KERNEL_FILES: #{allowed_path} -> #{kernel_path}"
  end
end

puts JSON.generate(
  status: errors.empty? ? "passed" : "failed",
  task_id: task_id,
  autonomy_level: autonomy_level,
  risk_level: risk_level,
  allowed_paths: allowed_paths,
  kernel_paths: kernel_paths,
  errors: errors,
  warnings: warnings
)
RUBY
); then
  log error validation_failed \
    "task_id=$(quote_value "$task_id")" \
    "reason=$(quote_value "failed to parse task metadata")"
  exit 1
fi

status=$(printf '%s\n' "$validation_json" | jq -r '.status')
autonomy_level=$(printf '%s\n' "$validation_json" | jq -r '.autonomy_level // ""')
risk_level=$(printf '%s\n' "$validation_json" | jq -r '.risk_level // ""')
allowed_count=$(printf '%s\n' "$validation_json" | jq -r '.allowed_paths | length')

if [ "$status" != "passed" ]; then
  printf '%s\n' "$validation_json" | jq -r '.errors[] | "pre-exec-validate.sh: error: " + .' >&2
  log error validation_failed \
    "task_id=$(quote_value "$task_id")" \
    "autonomy_level=$(quote_value "$autonomy_level")" \
    "risk_level=$(quote_value "$risk_level")" \
    "allowed_paths=$allowed_count"
  exit 1
fi

log info validation_passed \
  "task_id=$(quote_value "$task_id")" \
  "autonomy_level=$(quote_value "$autonomy_level")" \
  "risk_level=$(quote_value "$risk_level")" \
  "allowed_paths=$allowed_count"

exit 0
