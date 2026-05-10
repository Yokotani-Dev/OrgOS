#!/usr/bin/env bash
set -euo pipefail

TASKS_FILE="${TASKS_FILE:-.ai/TASKS.yaml}"
OUTPUT_JSON=false

if [[ "${1:-}" == "--json" ]]; then
  OUTPUT_JSON=true
elif [[ "${1:-}" != "" ]]; then
  echo "usage: $0 [--json]" >&2
  exit 2
fi

TASKS_FILE="$TASKS_FILE" OUTPUT_JSON="$OUTPUT_JSON" ruby -r yaml -r json -e '
  tasks_file = ENV.fetch("TASKS_FILE")
  output_json = ENV.fetch("OUTPUT_JSON") == "true"
  active_statuses = %w[queued running blocked review]
  required_fields = %w[
    autonomy_level
    blast_radius
    owner_input_needed
    risk_level
    default_if_no_response
    reversibility
  ]

  data = YAML.load_file(tasks_file)
  missing = []
  data.fetch("tasks").each do |task|
    next unless active_statuses.include?(task["status"])

    missing_fields = required_fields.select do |field|
      !task.key?(field) || task[field].nil? || (task[field].respond_to?(:empty?) && task[field].empty?)
    end

    next if missing_fields.empty?

    missing << {
      id: task.fetch("id", nil),
      status: task.fetch("status", nil),
      missing_fields: missing_fields
    }
  end

  if output_json
    puts JSON.pretty_generate(
      tasks_file: tasks_file,
      active_statuses: active_statuses,
      missing_count: missing.length,
      missing: missing
    )
  elsif missing.empty?
    puts "autonomy coverage: 100% (0 missing active tasks)"
  else
    warn "autonomy coverage missing for #{missing.length} active task(s):"
    missing.each do |entry|
      warn "- #{entry[:id]} (#{entry[:status]}): #{entry[:missing_fields].join(", ")}"
    end
  end

  exit(missing.empty? ? 0 : 1)
'
