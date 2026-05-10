#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JOURNEYS_FILE="${JOURNEYS_FILE:-${ROOT_DIR}/.ai/JOURNEYS.yaml}"
GOALS_FILE="${GOALS_FILE:-${ROOT_DIR}/.ai/GOALS.yaml}"
TASKS_FILE="${TASKS_FILE:-${ROOT_DIR}/.ai/TASKS.yaml}"
SCHEMA_FILE="${SCHEMA_FILE:-${ROOT_DIR}/.claude/schemas/journey.yaml}"

usage() {
  printf 'Usage: bash scripts/journeys/validate.sh\n' >&2
}

log_json() {
  local level="$1"
  local event="$2"
  local status="$3"
  local message="$4"
  printf '{"level":"%s","event":"%s","status":"%s","message":"%s"}\n' "$level" "$event" "$status" "$message" >&2
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    usage
    exit 2
    ;;
esac

if ! command -v ruby >/dev/null 2>&1; then
  log_json error journeys_validate failed "ruby is required"
  exit 1
fi

if [[ ! -f "$JOURNEYS_FILE" ]]; then
  log_json error journeys_validate failed ".ai/JOURNEYS.yaml not found"
  exit 1
fi

if [[ ! -f "$GOALS_FILE" ]]; then
  log_json error journeys_validate failed ".ai/GOALS.yaml not found"
  exit 1
fi

if [[ ! -f "$TASKS_FILE" ]]; then
  log_json error journeys_validate failed ".ai/TASKS.yaml not found"
  exit 1
fi

if [[ ! -f "$SCHEMA_FILE" ]]; then
  log_json error journeys_validate failed ".claude/schemas/journey.yaml not found"
  exit 1
fi

ruby - "$JOURNEYS_FILE" "$GOALS_FILE" "$TASKS_FILE" "$SCHEMA_FILE" <<'RUBY'
require "date"
require "json"
require "set"
require "time"
require "yaml"

journeys_path, goals_path, tasks_path, schema_path = ARGV
errors = []

def log(status, errors)
  payload = {
    event: "journeys_validate",
    status: status,
    error_count: errors.length,
    errors: errors
  }
  warn(JSON.generate(payload))
end

def load_yaml(path)
  YAML.safe_load(
    File.read(path),
    permitted_classes: [Date, Time],
    permitted_symbols: [],
    aliases: false
  )
rescue Psych::Exception, ArgumentError => error
  raise ArgumentError, "#{path}: #{error.message}"
end

def present?(value)
  !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
end

def date_like?(value)
  value.is_a?(Date) || value.is_a?(Time) || (value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/))
end

def validate_scalar(path, value, spec, errors)
  type = spec["type"]
  case type
  when "string"
    unless value.is_a?(String)
      errors << "#{path} must be a string"
      return
    end
    if spec["min_length"] && value.length < spec["min_length"].to_i
      errors << "#{path} must not be empty"
    end
    if spec["pattern"] && !value.match?(Regexp.new(spec["pattern"]))
      errors << "#{path} must match #{spec["pattern"]}"
    end
  when "string_or_null"
    unless value.nil? || value.is_a?(String)
      errors << "#{path} must be a string or null"
      return
    end
    if value && spec["pattern"] && !value.match?(Regexp.new(spec["pattern"]))
      errors << "#{path} must match #{spec["pattern"]}"
    end
  when "date"
    errors << "#{path} must be a date" unless date_like?(value)
  when "date_or_null"
    errors << "#{path} must be a date or null" unless value.nil? || date_like?(value)
  when "enum"
    values = Array(spec["values"])
    errors << "#{path} must be one of #{values.join(", ")}" unless values.include?(value)
  else
    errors << "#{path} uses unsupported schema type #{type.inspect}"
  end
end

def validate_object(path, value, spec, errors)
  unless value.is_a?(Hash)
    errors << "#{path} must be an object"
    return
  end

  fields = spec.fetch("fields", {})
  required = Array(spec["required"])
  required.each do |key|
    errors << "#{path}.#{key} is required" unless value.key?(key)
  end

  if spec["additional_properties"] == false
    extra = value.keys - fields.keys
    extra.each { |key| errors << "#{path}.#{key} is not allowed by schema" }
  end

  value.each do |key, child|
    child_spec = fields[key]
    validate_value("#{path}.#{key}", child, child_spec, errors) if child_spec
  end
end

def validate_array(path, value, spec, errors)
  unless value.is_a?(Array)
    errors << "#{path} must be an array"
    return
  end

  if spec["min_items"] && value.length < spec["min_items"].to_i
    errors << "#{path} must contain at least #{spec["min_items"]} item(s)"
  end
  if spec["max_items"] && value.length > spec["max_items"].to_i
    errors << "#{path} must contain at most #{spec["max_items"]} item(s)"
  end

  item_spec = spec["item"]
  return unless item_spec

  value.each_with_index do |item, index|
    validate_value("#{path}[#{index}]", item, item_spec, errors)
  end
end

def validate_value(path, value, spec, errors)
  unless spec
    errors << "#{path} has no schema"
    return
  end

  case spec["type"]
  when "object"
    validate_object(path, value, spec, errors)
  when "array"
    validate_array(path, value, spec, errors)
  else
    validate_scalar(path, value, spec, errors)
  end
end

begin
  journeys_data = load_yaml(journeys_path)
  goals_data = load_yaml(goals_path)
  tasks_data = load_yaml(tasks_path)
  schema_data = load_yaml(schema_path)
rescue ArgumentError => error
  log("failed", [error.message])
  exit 1
end

unless journeys_data.is_a?(Hash)
  errors << ".ai/JOURNEYS.yaml must be a YAML object"
end

if journeys_data.is_a?(Hash)
  root_required = Array(schema_data.dig("schema", "required"))
  root_required.each do |key|
    errors << "root.#{key} is required" unless journeys_data.key?(key)
  end

  extra = journeys_data.keys - root_required
  extra.each { |key| errors << "root.#{key} is not allowed by schema" } if schema_data.dig("schema", "additional_properties") == false
end

journeys = journeys_data.is_a?(Hash) ? journeys_data["journeys"] : nil
unless journeys.is_a?(Array)
  errors << "journeys must be an array"
  journeys = []
end

journey_schema = schema_data["journey"]
journeys.each_with_index do |journey, index|
  validate_object("journeys[#{index}]", journey, journey_schema, errors)
end

milestone_ids = Set.new(Array(goals_data && goals_data["milestones"]).map { |item| item.is_a?(Hash) ? item["id"] : nil }.compact)
task_ids = Set.new(Array(tasks_data && tasks_data["tasks"]).map { |item| item.is_a?(Hash) ? item["id"] : nil }.compact)

seen_ids = Set.new
valid_statuses = Set.new(Array(journey_schema.dig("fields", "sync_status", "values")))

journeys.each_with_index do |journey, index|
  next unless journey.is_a?(Hash)

  id = journey["id"] || "journeys[#{index}]"
  if seen_ids.include?(id)
    errors << "#{id}: duplicate journey id"
  else
    seen_ids.add(id)
  end

  status = journey["sync_status"]
  errors << "#{id}: sync_status must be one of #{valid_statuses.to_a.join(", ")}" unless valid_statuses.include?(status)

  if status == "confirmed"
    errors << "#{id}: confirmed_at is required when sync_status is confirmed" unless present?(journey["confirmed_at"])
    errors << "#{id}: confirmed_by is required when sync_status is confirmed" unless present?(journey["confirmed_by"])
  end

  milestone = journey["related_milestone"]
  if present?(milestone) && !milestone_ids.include?(milestone)
    errors << "#{id}: related_milestone #{milestone} does not exist in GOALS.yaml"
  end

  Array(journey["related_tasks"]).each do |task_id|
    errors << "#{id}: related_tasks entry #{task_id} does not exist in TASKS.yaml" unless task_ids.include?(task_id)
  end

  Array(journey["happy_path"]).each_with_index do |step, step_index|
    errors << "#{id}: happy_path[#{step_index}] must be a non-empty string" unless step.is_a?(String) && present?(step)
  end

  Array(journey["error_paths"]).each_with_index do |path_item, path_index|
    unless path_item.is_a?(Hash)
      errors << "#{id}: error_paths[#{path_index}] must be an object"
      next
    end
    errors << "#{id}: error_paths[#{path_index}].condition must be present" unless present?(path_item["condition"])
    errors << "#{id}: error_paths[#{path_index}].handling must be present" unless present?(path_item["handling"])
  end
end

if errors.empty?
  log("ok", [])
  exit 0
end

log("failed", errors)
exit 1
RUBY
