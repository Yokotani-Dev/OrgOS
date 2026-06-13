#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: bash scripts/codex/post-exec-audit.sh <TASK_ID> <worktree_path>

Audits Codex worktree changes after execution and reverts files outside the
task allowed_paths or any protected KERNEL_FILES entry.
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

cleanup() {
  rm -f "$changed_file" "$audit_entries"
}

if [ "$#" -ne 2 ]; then
  usage
  exit 2
fi

task_id=$1
worktree_path=$2

if ! validate_task_id "$task_id"; then
  printf 'post-exec-audit.sh: invalid TASK_ID: %s\n' "$task_id" >&2
  exit 2
fi

if [ ! -d "$worktree_path/.git" ] && ! git -C "$worktree_path" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'post-exec-audit.sh: worktree_path is not a git worktree: %s\n' "$worktree_path" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${ORGOS_REPO_ROOT:-$(cd "$script_dir/../.." && pwd)}"
tasks_file="${ORGOS_TASKS_FILE:-$repo_root/.ai/TASKS.yaml}"
kernel_files="${ORGOS_KERNEL_FILES:-$repo_root/.claude/evals/KERNEL_FILES}"
audit_dir="${ORGOS_CODEX_AUDIT_DIR:-$repo_root/.ai/_machine/codex/AUDIT}"
audit_file="$audit_dir/$task_id.yaml"
changed_file=$(mktemp "${TMPDIR:-/tmp}/orgos-codex-changed.XXXXXX")
audit_entries=$(mktemp "${TMPDIR:-/tmp}/orgos-codex-audit.XXXXXX")
trap cleanup EXIT

if [ ! -r "$tasks_file" ]; then
  log error audit_failed \
    "task_id=$(quote_value "$task_id")" \
    "reason=$(quote_value "TASKS file is not readable")" \
    "path=$(quote_value "$tasks_file")"
  exit 1
fi

if [ ! -r "$kernel_files" ]; then
  log error audit_failed \
    "task_id=$(quote_value "$task_id")" \
    "reason=$(quote_value "KERNEL_FILES is not readable")" \
    "path=$(quote_value "$kernel_files")"
  exit 1
fi

log info audit_start \
  "task_id=$(quote_value "$task_id")" \
  "worktree_path=$(quote_value "$worktree_path")"

git -C "$worktree_path" diff --name-only HEAD > "$changed_file"
git -C "$worktree_path" ls-files --others --exclude-standard >> "$changed_file"
sort -u "$changed_file" -o "$changed_file"

violation_count=0
reverted_count=0
revert_failed_count=0
allowed_count=0

while IFS= read -r file_path; do
  [ -n "$file_path" ] || continue

  if ! decision_json=$(
    TASK_ID="$task_id" TASKS_FILE="$tasks_file" KERNEL_FILES="$kernel_files" FILE_PATH="$file_path" ruby -r yaml -r json <<'RUBY'
task_id = ENV.fetch("TASK_ID")
tasks_file = ENV.fetch("TASKS_FILE")
kernel_files = ENV.fetch("KERNEL_FILES")
file_path = ENV.fetch("FILE_PATH")

def normalize_path(path)
  path.to_s.strip.sub(%r{\A\./}, "").sub(%r{/+\z}, "/")
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
task = data.fetch("tasks").find { |item| item.is_a?(Hash) && item["id"] == task_id }
raise "task not found in .ai/TASKS.yaml: #{task_id}" unless task

allowed_paths = Array(task["allowed_paths"]).map { |path| normalize_path(path) }.reject(&:empty?)
kernel_paths = File.readlines(kernel_files, chomp: true).map do |line|
  stripped = line.sub(/#.*/, "").strip
  stripped.empty? ? nil : normalize_path(stripped)
end.compact

target = normalize_path(file_path)
kernel_match = kernel_paths.find { |kernel_path| path_covers?(kernel_path, target) || path_covers?(target, kernel_path) }
allowed_match = allowed_paths.find { |allowed_path| path_covers?(allowed_path, target) }

if kernel_match
  puts JSON.generate(status: "kernel", reason: "matches KERNEL_FILES: #{kernel_match}")
elsif allowed_match
  puts JSON.generate(status: "allowed", reason: "matches allowed_paths: #{allowed_match}")
else
  puts JSON.generate(status: "outside_allowed_paths", reason: "does not match task allowed_paths")
end
RUBY
  ); then
    decision_json='{"status":"outside_allowed_paths","reason":"failed to classify file"}'
  fi

  decision=$(printf '%s\n' "$decision_json" | jq -r '.status')
  reason=$(printf '%s\n' "$decision_json" | jq -r '.reason')
  action="none"
  result="allowed"

  case "$decision" in
    allowed)
      allowed_count=$((allowed_count + 1))
      log info audit_file_allowed \
        "task_id=$(quote_value "$task_id")" \
        "file=$(quote_value "$file_path")" \
        "reason=$(quote_value "$reason")"
      ;;
    kernel|outside_allowed_paths)
      violation_count=$((violation_count + 1))
      action="revert"
      if [ "$decision" = "kernel" ]; then
        log critical audit_kernel_violation \
          "task_id=$(quote_value "$task_id")" \
          "file=$(quote_value "$file_path")" \
          "reason=$(quote_value "$reason")"
      else
        log error audit_path_violation \
          "task_id=$(quote_value "$task_id")" \
          "file=$(quote_value "$file_path")" \
          "reason=$(quote_value "$reason")"
      fi

      if git -C "$worktree_path" ls-files --error-unmatch -- "$file_path" >/dev/null 2>&1; then
        if git -C "$worktree_path" checkout HEAD -- "$file_path"; then
          result="reverted"
          reverted_count=$((reverted_count + 1))
        else
          result="revert_failed"
          revert_failed_count=$((revert_failed_count + 1))
        fi
      else
        if rm -f -- "$worktree_path/$file_path"; then
          result="reverted"
          reverted_count=$((reverted_count + 1))
        else
          result="revert_failed"
          revert_failed_count=$((revert_failed_count + 1))
        fi
      fi
      ;;
    *)
      violation_count=$((violation_count + 1))
      action="revert"
      result="revert_failed"
      revert_failed_count=$((revert_failed_count + 1))
      reason="unknown audit decision: $decision"
      ;;
  esac

  printf '%s\t%s\t%s\t%s\t%s\n' "$file_path" "$decision" "$action" "$result" "$reason" >> "$audit_entries"
done < "$changed_file"

mkdir -p "$audit_dir"

TASK_ID="$task_id" \
WORKTREE_PATH="$worktree_path" \
TASKS_FILE="$tasks_file" \
KERNEL_FILES="$kernel_files" \
CHANGED_FILE="$changed_file" \
AUDIT_ENTRIES="$audit_entries" \
AUDIT_FILE="$audit_file" \
ALLOWED_COUNT="$allowed_count" \
VIOLATION_COUNT="$violation_count" \
REVERTED_COUNT="$reverted_count" \
REVERT_FAILED_COUNT="$revert_failed_count" \
ruby -r yaml -r json -r time <<'RUBY'
task_id = ENV.fetch("TASK_ID")
entries_path = ENV.fetch("AUDIT_ENTRIES")
audit_file = ENV.fetch("AUDIT_FILE")

entries = File.readlines(entries_path, chomp: true).map do |line|
  file, decision, action, result, reason = line.split("\t", 5)
  {
    "file" => file,
    "decision" => decision,
    "action" => action,
    "result" => result,
    "reason" => reason
  }
end

status =
  if ENV.fetch("REVERT_FAILED_COUNT").to_i.positive?
    "failed"
  elsif ENV.fetch("VIOLATION_COUNT").to_i.positive?
    "violations_reverted"
  else
    "passed"
  end

document = {
  "task_id" => task_id,
  "timestamp" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
  "status" => status,
  "worktree_path" => ENV.fetch("WORKTREE_PATH"),
  "tasks_file" => ENV.fetch("TASKS_FILE"),
  "kernel_files" => ENV.fetch("KERNEL_FILES"),
  "summary" => {
    "allowed_count" => ENV.fetch("ALLOWED_COUNT").to_i,
    "violation_count" => ENV.fetch("VIOLATION_COUNT").to_i,
    "reverted_count" => ENV.fetch("REVERTED_COUNT").to_i,
    "revert_failed_count" => ENV.fetch("REVERT_FAILED_COUNT").to_i
  },
  "files" => entries
}

File.write(audit_file, document.to_yaml)
RUBY

log info audit_completed \
  "task_id=$(quote_value "$task_id")" \
  "audit_file=$(quote_value "$audit_file")" \
  "allowed_count=$allowed_count" \
  "violation_count=$violation_count" \
  "reverted_count=$reverted_count" \
  "revert_failed_count=$revert_failed_count"

if [ "$revert_failed_count" -gt 0 ] || [ "$violation_count" -gt 0 ]; then
  exit 1
fi

exit 0
