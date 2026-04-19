#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/session/suggest-next.sh
  bash scripts/session/suggest-next.sh --context morning
  bash scripts/session/suggest-next.sh --top 3

Options:
  --context morning|midday|auto
  --top N
EOF
}

context_mode="auto"
top_n="3"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      [[ $# -ge 2 ]] || {
        echo "error: --context requires a value" >&2
        usage >&2
        exit 1
      }
      context_mode="$2"
      shift 2
      ;;
    --top)
      [[ $# -ge 2 ]] || {
        echo "error: --top requires a value" >&2
        usage >&2
        exit 1
      }
      top_n="$2"
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

cd "${REPO_ROOT}"

bootstrap_output="$(bash scripts/session/bootstrap.sh)"
bootstrap_status="$(printf '%s\n' "${bootstrap_output}" | sed -n 's/^- status: //p' | head -n1)"

if [[ "${bootstrap_status}" != "ok" ]]; then
  printf '%s\n' "${bootstrap_output}"
  exit 0
fi

goals_json="$(bash scripts/session/load-ledger.sh --ledger goals)"
tasks_json="$(bash scripts/session/load-ledger.sh --ledger tasks)"
user_profile_json="$(bash scripts/session/load-ledger.sh --ledger user_profile)"

suggestion_payload="$(GOALS_JSON="${goals_json}" TASKS_JSON="${tasks_json}" USER_PROFILE_JSON="${user_profile_json}" CONTEXT_MODE="${context_mode}" TOP_N="${top_n}" ruby_utf8 <<'RUBY'
# encoding: utf-8
require "date"
require "json"
require "time"
require "yaml"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

goals = JSON.parse(ENV.fetch("GOALS_JSON")).fetch("data")
tasks_data = JSON.parse(ENV.fetch("TASKS_JSON")).fetch("data")
user_profile = JSON.parse(ENV.fetch("USER_PROFILE_JSON")).fetch("data")
context_mode = ENV.fetch("CONTEXT_MODE")
top_n = ENV.fetch("TOP_N").to_i
top_n = 3 if top_n <= 0

control = YAML.safe_load(File.read(".ai/CONTROL.yaml", encoding: "UTF-8"), permitted_classes: [Date, Time, Symbol], aliases: true)
results_dir = ".ai/CODEX/RESULTS"

def task_priority(task)
  explicit = task["priority"].to_s.strip
  return explicit unless explicit.empty?

  match = task["title"].to_s.match(/\b(P[0-3])\b/i)
  match ? match[1].upcase : "P2"
end

def estimate_label(task)
  acceptance_count = Array(task["acceptance"]).size
  notes_size = task["notes"].to_s.length
  score = acceptance_count + (notes_size >= 120 ? 1 : 0) + Array(task["deps"]).size
  return "小" if score <= 2
  return "中" if score <= 5

  "大"
end

def extract_recent_task_ids(dir)
  return [] unless Dir.exist?(dir)

  Dir.glob(File.join(dir, "T-OS-*.*"))
    .sort_by { |path| File.mtime(path) }
    .reverse
    .map { |path| File.basename(path)[/(T-OS-\d+)/, 1] }
    .compact
    .uniq
    .first(5)
end

tasks = Array(tasks_data["tasks"])
task_index = tasks.each_with_object({}) { |task, acc| acc[task["id"]] = task }
queued_tasks = tasks.select { |task| task["status"] == "queued" }
blocked_tasks = tasks.select { |task| task["status"] == "blocked" }

if queued_tasks.empty?
  payload = {
    mode: "queue_empty",
    context: context_mode,
    bootstrap_status: "ok",
    response_preference: user_profile.dig("owner", "response_preference") || "terse_japanese"
  }
  puts JSON.generate(payload)
  exit
end

awaiting_owner = !!control["awaiting_owner"]
owner_preferences = Array(user_profile["preferences"]).map { |item| item.is_a?(Hash) ? item["statement"] : item.to_s }.compact
active_milestones = Array(goals["milestones"]).select { |item| item["status"] == "active" }
active_projects = Array(goals["projects"])
recent_task_ids = extract_recent_task_ids(results_dir)

dependents = Hash.new { |hash, key| hash[key] = [] }
tasks.each do |task|
  Array(task["deps"]).each do |dep|
    dependents[dep] << task
  end
end

done_like_statuses = %w[done archived achieved]

ready_tasks = queued_tasks.select do |task|
  Array(task["deps"]).all? do |dep_id|
    dep = task_index[dep_id]
    dep && done_like_statuses.include?(dep["status"].to_s)
  end
end

if ready_tasks.empty?
  unmet_dep_ids = queued_tasks.flat_map do |task|
    Array(task["deps"]).reject do |dep_id|
      dep = task_index[dep_id]
      dep && done_like_statuses.include?(dep["status"].to_s)
    end
  end.uniq

  unblock_candidates = unmet_dep_ids.filter_map do |dep_id|
    dep = task_index[dep_id]
    next unless dep

    {
      "id" => dep["id"],
      "title" => dep["title"],
      "priority" => task_priority(dep),
      "status" => dep["status"],
      "notes" => dep["notes"],
      "acceptance" => Array(dep["acceptance"]),
      "owner_role" => dep["owner_role"],
      "estimate" => estimate_label(dep),
      "milestone_ref" => active_projects.find { |project| Array(project["tasks_ref"]).include?(dep["id"]) }&.dig("milestone_ref"),
      "reason" => "deps 未解消タスクを unblock する入口",
      "blocked_dependents" => dependents[dep["id"]].map { |task| task["id"] }
    }
  end

  payload = {
    mode: "blocked_only",
    awaiting_owner: awaiting_owner,
    context: context_mode,
    response_preference: user_profile.dig("owner", "response_preference") || "terse_japanese",
    candidates: unblock_candidates.first([top_n, 5].max)
  }
  puts JSON.generate(payload)
  exit
end

candidates = ready_tasks.map do |task|
  project = active_projects.find { |item| Array(item["tasks_ref"]).include?(task["id"]) }
  milestone_ref = project&.dig("milestone_ref") || task["milestone_ref"]
  active_milestone = active_milestones.find { |item| item["id"] == milestone_ref }
  blocker_release = dependents[task["id"]].any? { |dependent| %w[queued blocked].include?(dependent["status"].to_s) }
  recent_related = recent_task_ids.any? do |recent_id|
    recent_id == task["id"] || Array(task["deps"]).include?(recent_id) || task["notes"].to_s.include?(recent_id)
  end

  {
    "id" => task["id"],
    "title" => task["title"],
    "priority" => task_priority(task),
    "status" => task["status"],
    "deps" => Array(task["deps"]),
    "owner_role" => task["owner_role"],
    "notes" => task["notes"],
    "acceptance" => Array(task["acceptance"]),
    "milestone_ref" => milestone_ref,
    "milestone_title" => active_milestone&.dig("title"),
    "estimate" => estimate_label(task),
    "blocker_release" => blocker_release,
    "recent_related" => recent_related,
    "blocked_dependents" => dependents[task["id"]].map { |item| item["id"] }
  }
end

payload = {
  mode: "rank_ready",
  awaiting_owner: awaiting_owner,
  context: context_mode,
  response_preference: user_profile.dig("owner", "response_preference") || "terse_japanese",
  recent_completed_task_ids: recent_task_ids,
  active_milestones: active_milestones.map { |item| { "id" => item["id"], "title" => item["title"] } },
  tasks: candidates,
  preferences: owner_preferences,
  top_n: [top_n, 5].min
}

puts JSON.generate(payload)
RUBY
)"

mode="$(printf '%s' "${suggestion_payload}" | jq -r '.mode')"
awaiting_owner="$(printf '%s' "${suggestion_payload}" | jq -r '.awaiting_owner // false')"

if [[ "${awaiting_owner}" == "true" ]]; then
  cat <<'EOF'
現在は Owner 返答待ちです。新規提案より先に pending decision を解消してください。
EOF
  exit 0
fi

if [[ "${mode}" == "queue_empty" ]]; then
  cat <<'EOF'
現在 queue は空です。新規プロジェクトをどうぞ。
EOF
  exit 0
fi

if [[ "${mode}" == "blocked_only" ]]; then
  cat <<EOF
# 次アクション候補

queued task はありますが、今すぐ着手できる候補はありません。unblock 候補を先に提案します。
EOF

  printf '%s' "${suggestion_payload}" | jq -r '
    .candidates[:5]
    | to_entries[]
    | "## \(.key + 1). [\(.value.priority)] \(.value.id): \(.value.title)\n- 理由: \(.value.reason)\n- 関連: \((.value.blocked_dependents | join(", ")) // "none")\n- 見積: \(.value.estimate)\n"
  '
  exit 0
fi

rank_input="$(printf '%s' "${suggestion_payload}" | jq '{tasks: .tasks, preferences: .preferences, top_n: .top_n}')"
ranked_json="$(printf '%s' "${rank_input}" | bash scripts/session/priority-ranker.sh)"

render_payload="$(SUGGESTION_PAYLOAD="${suggestion_payload}" RANKED_JSON="${ranked_json}" ruby_utf8 <<'RUBY'
# encoding: utf-8
require "json"
require "time"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

payload = JSON.parse(ENV.fetch("SUGGESTION_PAYLOAD"))
ranked = JSON.parse(ENV.fetch("RANKED_JSON"))

hour = Time.now.getlocal.strftime("%H").to_i
context =
  case payload["context"]
  when "morning" then "morning"
  when "midday" then "midday"
  else hour < 12 ? "morning" : "midday"
  end

recent_completed = Array(payload["recent_completed_task_ids"])
response_preference = payload["response_preference"].to_s

def reason_lines(task)
  reasons = []

  if task["blocker_release_bonus"].to_i.positive? && Array(task["blocked_dependents"]).any?
    reasons << "blocker 解消 (#{Array(task["blocked_dependents"]).join(", ")} を unblock)"
  end

  if task["recent_momentum_bonus"].to_i.positive?
    reasons << "直近完了タスクと連続性あり"
  end

  if Array(task["matched_preferences"]).any?
    reasons << "Owner preference一致 (#{Array(task["matched_preferences"]).join(", ")})"
  end

  reasons << "active milestone と整合" if task["milestone_ref"]
  reasons << "priority #{task["priority"]} 相当" if reasons.empty?
  reasons
end

header_lines = []
if context == "morning" && recent_completed.any?
  summary_ids = recent_completed.first(2).join(" / ")
  header_lines << "直近では #{summary_ids} が完了しています。今日は次を提案します。"
end

body = ranked.fetch("ranked_tasks").map.with_index(1) do |task, index|
  label = index == 1 ? "[#{task["priority"]} 推奨]" : "[#{task["priority"]}]"
  reason = response_preference == "terse_japanese" ? reason_lines(task).first : reason_lines(task).join(" / ")
  related = task["milestone_ref"] ? "#{task["milestone_ref"]}: #{task["milestone_title"]}" : "milestone 未割当"

  <<~MARKDOWN
  ## #{index}. #{label} #{task["id"]}: #{task["title"]}
  - 理由: #{reason}
  - 関連: #{related}
  - 見積: #{task["estimate"]}
  MARKDOWN
end.join("\n")

puts({
  "context" => context,
  "header" => header_lines.join("\n"),
  "body" => body
}.to_json)
RUBY
)"

context="$(printf '%s' "${render_payload}" | jq -r '.context')"
header="$(printf '%s' "${render_payload}" | jq -r '.header')"
body="$(printf '%s' "${render_payload}" | jq -r '.body')"

if [[ "${context}" == "morning" ]] && [[ -n "${header}" ]]; then
  printf '%s\n\n' "${header}"
fi

cat <<EOF
# 次アクション候補 (3-5 件)

${body}
EOF
