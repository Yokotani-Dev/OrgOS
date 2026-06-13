#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TASKS_FILE="${ROOT_DIR}/.ai/TASKS.yaml"
ARCHIVE_FILE="${ROOT_DIR}/.ai/TASKS_ARCHIVE.yaml"
DRY_RUN=0

usage() {
  printf 'Usage: bash scripts/tasks/archive-done.sh [--dry-run]\n' >&2
}

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

log_json() {
  ruby -rjson -e 'puts JSON.generate(JSON.parse(ARGV[0]))' "$1" >&2
}

if [[ ! -f "$TASKS_FILE" ]]; then
  log_json '{"event":"archive_tasks","status":"failed","error_class":"missing_tasks_file","message":".ai/TASKS.yaml not found","moved_ids":[]}'
  exit 1
fi

if [[ -L "$TASKS_FILE" || -L "$ARCHIVE_FILE" ]]; then
  log_json '{"event":"archive_tasks","status":"failed","error_class":"unsafe_path","message":"refusing to write through symlink","moved_ids":[]}'
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orgos-archive-done.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

OUT_TASKS="${TMP_DIR}/TASKS.yaml"
OUT_ARCHIVE="${TMP_DIR}/TASKS_ARCHIVE.yaml"
PLAN_JSON="${TMP_DIR}/plan.json"

if ! DRY_RUN="$DRY_RUN" TASKS_FILE="$TASKS_FILE" ARCHIVE_FILE="$ARCHIVE_FILE" OUT_TASKS="$OUT_TASKS" OUT_ARCHIVE="$OUT_ARCHIVE" PLAN_JSON="$PLAN_JSON" ruby <<'RUBY'
require "json"
require "yaml"
require "date"
require "time"

DONE_STATUSES = %w[done archived superseded].freeze

def log(status:, error_class: nil, message: nil, moved_ids: [], archived_ids: [], backup: nil, dry_run: false)
  payload = {
    event: "archive_tasks",
    status: status,
    moved_ids: moved_ids,
    archived_ids: archived_ids,
    moved_count: moved_ids.length,
    archived_count: archived_ids.length,
    dry_run: dry_run
  }
  payload[:error_class] = error_class if error_class
  payload[:message] = message if message
  payload[:backup] = backup if backup
  warn(JSON.generate(payload))
end

def read_yaml(path, required_key)
  return { required_key => [] } unless File.exist?(path)

  data = YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)
  unless data.is_a?(Hash) && data.key?(required_key)
    raise ArgumentError, "#{path} must contain #{required_key}:"
  end
  data
end

def task_id_from(block)
  first = block.first.to_s
  match = first.match(/\A  - id:\s*(?:"([^"]+)"|'([^']+)'|([^#\s]+))/)
  match && (match[1] || match[2] || match[3])
end

def task_status_from(block)
  line = block.find { |candidate| candidate.match?(/\A    status:\s*/) }
  return nil unless line

  match = line.match(/\A    status:\s*(?:"([^"]+)"|'([^']+)'|([^#\s]+))/)
  match && (match[1] || match[2] || match[3])
end

def collect_task(lines, start_index)
  cursor = start_index + 1
  while cursor < lines.length
    line = lines[cursor]
    break if line.match?(/\A  - id:/)
    break if line.match?(/\A  #/)

    if line.strip.empty?
      lookahead = cursor + 1
      lookahead += 1 while lookahead < lines.length && lines[lookahead].strip.empty?
      break if lookahead >= lines.length
      break unless lines[lookahead].match?(/\A {4,}\S/)

      cursor += 1
      next
    end

    break unless line.match?(/\A {4,}/)

    cursor += 1
  end

  [lines[start_index...cursor], cursor]
end

def split_tasks_yaml(text)
  lines = text.lines
  tasks_index = lines.index { |line| line.match?(/\Atasks:\s*(?:#.*)?\n?\z/) }
  raise ArgumentError, "TASKS.yaml must contain a top-level tasks: key" unless tasks_index

  [lines[0..tasks_index], lines[(tasks_index + 1)..] || []]
end

def existing_archive_ids(archive_data)
  Array(archive_data["archived_tasks"]).map do |task|
    task.is_a?(Hash) ? task["id"] : nil
  end.compact.to_set
end

begin
  require "set"
  dry_run = ENV.fetch("DRY_RUN") == "1"
  tasks_path = ENV.fetch("TASKS_FILE")
  archive_path = ENV.fetch("ARCHIVE_FILE")
  out_tasks = ENV.fetch("OUT_TASKS")
  out_archive = ENV.fetch("OUT_ARCHIVE")
  plan_json = ENV.fetch("PLAN_JSON")

  read_yaml(tasks_path, "tasks")
  archive_data = read_yaml(archive_path, "archived_tasks")

  tasks_text = File.read(tasks_path)
  archive_text = if File.exist?(archive_path)
    File.read(archive_path)
  else
    "# Task Archive (SSOT)\n# done/archived/superseded tasks moved out of TASKS.yaml.\n\narchived_tasks:\n"
  end

  archive_ids = existing_archive_ids(archive_data)
  header, body = split_tasks_yaml(tasks_text)
  kept_body = []
  moved_ids = []
  archived_ids = []
  append_blocks = []

  index = 0
  while index < body.length
    line = body[index]
    unless line.match?(/\A  - id:/)
      kept_body << line
      index += 1
      next
    end

    block, next_index = collect_task(body, index)
    id = task_id_from(block)
    status = task_status_from(block)
    raise ArgumentError, "task block missing id near TASKS.yaml body line #{index + 1}" unless id
    raise ArgumentError, "task #{id} missing status" unless status

    if DONE_STATUSES.include?(status)
      moved_ids << id
      unless archive_ids.include?(id)
        append_blocks << block
        archived_ids << id
        archive_ids.add(id)
      end
    else
      kept_body.concat(block)
    end

    index = next_index
  end

  File.write(plan_json, JSON.pretty_generate({
    moved_ids: moved_ids,
    archived_ids: archived_ids
  }) + "\n")

  if dry_run
    puts moved_ids
    log(status: "dry_run", moved_ids: moved_ids, archived_ids: archived_ids, dry_run: true)
    exit 0
  end

  if moved_ids.empty?
    log(status: "noop", moved_ids: [], archived_ids: [], dry_run: false)
    exit 0
  end

  new_tasks_text = (header + kept_body).join
  new_archive_text = archive_text.dup

  unless append_blocks.empty?
    new_archive_text << "\n" unless new_archive_text.end_with?("\n")
    new_archive_text << "\n" unless new_archive_text.end_with?("\n\n")
    new_archive_text << "  # === Archived from TASKS.yaml by archive-done.sh (#{Time.now.strftime("%Y-%m-%d")}) ===\n\n"
    append_blocks.each do |block|
      new_archive_text << block.join
      new_archive_text << "\n"
    end
  end

  YAML.safe_load(new_tasks_text, permitted_classes: [Date, Time], aliases: true)
  YAML.safe_load(new_archive_text, permitted_classes: [Date, Time], aliases: true)

  File.write(out_tasks, new_tasks_text)
  File.write(out_archive, new_archive_text)
  log(status: "planned", moved_ids: moved_ids, archived_ids: archived_ids, dry_run: false)
rescue Psych::Exception, ArgumentError => error
  log(
    status: "blocked",
    error_class: error.class.name,
    message: error.message,
    moved_ids: [],
    archived_ids: [],
    dry_run: ENV.fetch("DRY_RUN") == "1"
  )
  exit 1
end
RUBY
then
  exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

if [[ ! -s "$PLAN_JSON" ]]; then
  log_json '{"event":"archive_tasks","status":"failed","error_class":"missing_plan","message":"archive plan was not created","moved_ids":[]}'
  exit 1
fi

MOVED_COUNT="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("moved_ids").length' "$PLAN_JSON")"
if [[ "$MOVED_COUNT" -eq 0 ]]; then
  exit 0
fi

TIMESTAMP="$(date +%Y%m%d%H%M%S)"
BACKUP_FILE="${TASKS_FILE}.bak.${TIMESTAMP}"
cp -p "$TASKS_FILE" "$BACKUP_FILE"
mv "$OUT_ARCHIVE" "$ARCHIVE_FILE"
mv "$OUT_TASKS" "$TASKS_FILE"

ruby -rjson -e '
plan = JSON.parse(File.read(ARGV[0]))
puts JSON.generate({
  event: "archive_tasks",
  status: "completed",
  moved_ids: plan.fetch("moved_ids"),
  archived_ids: plan.fetch("archived_ids"),
  moved_count: plan.fetch("moved_ids").length,
  archived_count: plan.fetch("archived_ids").length,
  backup: ARGV[1],
  dry_run: false
})
' "$PLAN_JSON" "${BACKUP_FILE#${ROOT_DIR}/}" >&2
