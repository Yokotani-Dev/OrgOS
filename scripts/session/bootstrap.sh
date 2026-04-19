#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/common.sh"

required_files=(
  ".ai/USER_PROFILE.yaml"
  ".ai/CAPABILITIES.yaml"
  ".ai/GOALS.yaml"
  ".ai/CONTROL.yaml"
  ".ai/TASKS.yaml"
  ".ai/DASHBOARD.md"
  ".claude/rules/request-intake-loop.md"
)

ordered_ledgers=(
  "1|Control plane|.ai/CONTROL.yaml"
  "1|Control plane|.ai/DASHBOARD.md"
  "2|Memory|.ai/USER_PROFILE.yaml"
  "3|Capabilities|.ai/CAPABILITIES.yaml"
  "4|Goals|.ai/GOALS.yaml"
  "5|Tasks|.ai/TASKS.yaml"
  "6|Recent Decisions|.ai/DECISIONS.md"
  "7|Intake Iron Law|.claude/rules/request-intake-loop.md"
)

missing=()
loaded=()

for path in "${required_files[@]}"; do
  if [[ -f "${REPO_ROOT}/${path}" ]]; then
    loaded+=("${path}")
  else
    missing+=("${path}")
  fi
done

status="ok"
if [[ ${#missing[@]} -gt 0 ]]; then
  status="warning"
fi

cd "${REPO_ROOT}"

summary_json="$(ruby_utf8 <<'RUBY'
# encoding: utf-8
require "date"
require "json"
require "yaml"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

def load_yaml(path)
  return nil unless File.exist?(path)

  YAML.safe_load(File.read(path, encoding: "UTF-8"), permitted_classes: [Date, Time, Symbol], aliases: true)
end

control = load_yaml(".ai/CONTROL.yaml") || {}
user_profile = load_yaml(".ai/USER_PROFILE.yaml") || {}
goals = load_yaml(".ai/GOALS.yaml") || {}
tasks = load_yaml(".ai/TASKS.yaml") || {}
capabilities = load_yaml(".ai/CAPABILITIES.yaml") || {}

owner_literacy = user_profile.dig("owner", "literacy_level") ||
  control["owner_literacy_level"] ||
  "unknown"

running_tasks = Array(tasks["tasks"]).select { |task| task["status"] == "running" }
active_projects = Array(goals["projects"]).select { |project| project["status"] == "active" }
active_milestones = Array(goals["milestones"]).select { |milestone| milestone["status"] == "active" }
available_capabilities = Array(capabilities["capabilities"]).select { |cap| cap["status"] == "available" }

payload = {
  owner_literacy_level: owner_literacy,
  project_scope: control["project_scope"] || "unknown",
  stage: control["stage"] || "unknown",
  running_tasks: running_tasks.map { |task| { id: task["id"], title: task["title"] } },
  active_projects: active_projects.map { |project| { id: project["id"], title: project["title"], priority: project["priority"] } },
  active_milestones: active_milestones.map { |milestone| { id: milestone["id"], title: milestone["title"] } },
  capability_counts: {
    total: Array(capabilities["capabilities"]).size,
    available: available_capabilities.size
  },
  vision_id: goals.dig("vision", "id"),
  vision_statement: goals.dig("vision", "statement")
}

puts JSON.generate(payload)
RUBY
)"

owner_literacy="$(printf '%s' "${summary_json}" | jq -r '.owner_literacy_level')"
project_scope="$(printf '%s' "${summary_json}" | jq -r '.project_scope')"
stage="$(printf '%s' "${summary_json}" | jq -r '.stage')"
vision_id="$(printf '%s' "${summary_json}" | jq -r '.vision_id // "unknown"')"
vision_statement="$(printf '%s' "${summary_json}" | jq -r '.vision_statement // "unknown"')"
running_tasks_md="$(printf '%s' "${summary_json}" | jq -r '.running_tasks[]? | "- \(.id): \(.title)"')"
active_projects_md="$(printf '%s' "${summary_json}" | jq -r '.active_projects[]? | "- \(.id) [\(.priority)]: \(.title)"')"
active_milestones_md="$(printf '%s' "${summary_json}" | jq -r '.active_milestones[]? | "- \(.id): \(.title)"')"
cap_total="$(printf '%s' "${summary_json}" | jq -r '.capability_counts.total')"
cap_available="$(printf '%s' "${summary_json}" | jq -r '.capability_counts.available')"

if [[ -z "${running_tasks_md}" ]]; then
  running_tasks_md="- none"
fi

if [[ -z "${active_projects_md}" ]]; then
  active_projects_md="- none"
fi

if [[ -z "${active_milestones_md}" ]]; then
  active_milestones_md="- none"
fi

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat <<EOF
# Session Bootstrap Summary

- status: ${status}
- bootstrapped_at: ${timestamp}
- project_scope: ${project_scope}
- stage: ${stage}
- owner_literacy_level: ${owner_literacy}
- vision: ${vision_id}

## Key Facts

- Vision statement: ${vision_statement}
- Capabilities available: ${cap_available}/${cap_total}
- Required ledgers loaded: $((${#loaded[@]}))/${#required_files[@]}

## Bootstrap Order
EOF

for entry in "${ordered_ledgers[@]}"; do
  IFS="|" read -r order label path <<< "${entry}"
  state="missing"
  [[ -f "${REPO_ROOT}/${path}" ]] && state="loaded"
  printf -- '- %s. %s: `%s` (%s)\n' "${order}" "${label}" "${path}" "${state}"
done

cat <<EOF

## Active Tasks
${running_tasks_md}

## Active Projects
${active_projects_md}

## Active Milestones
${active_milestones_md}

## Warnings
EOF

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "- none"
else
  for path in "${missing[@]}"; do
    printf -- '- missing required ledger: `%s`\n' "${path}"
  done
fi

cat <<'EOF'

## Manager Use

1. Record this result in `handoff_packet.verification`.
2. Materialize a `session-state.yaml` snapshot for the current session.
3. Apply `request-intake-loop.md` Step 1-10 before responding to any request.
EOF
