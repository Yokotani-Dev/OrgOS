#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/session/bind-request.sh --request "text"
  echo "text" | bash scripts/session/bind-request.sh
EOF
}

request=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --request)
      [[ $# -ge 2 ]] || {
        echo "error: --request requires a value" >&2
        usage >&2
        exit 1
      }
      request="$2"
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

if [[ -z "${request}" ]] && [[ ! -t 0 ]]; then
  request="$(cat)"
fi

request="$(trim_whitespace "${request}")"

cd "${REPO_ROOT}"

REQUEST_TEXT="${request}" ruby_utf8 <<'RUBY'
# encoding: utf-8
require "date"
require "json"
require "psych"
require "set"
require "yaml"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

TASK_THRESHOLD = 0.70
SUBTASK_THRESHOLD = 0.30
DECISION_LIMIT = 20

def ensure_utf8(text)
  value = text.to_s.dup
  value.force_encoding(Encoding::UTF_8)
  value.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
end

def read_utf8(path)
  ensure_utf8(File.read(path, encoding: "UTF-8"))
end

def load_yaml(path, warnings:)
  content = read_utf8(path)
  YAML.safe_load(content, permitted_classes: [Date, Time, Symbol], aliases: true)
rescue Errno::ENOENT
  {}
rescue Psych::Exception => e
  warnings << "#{path}: #{e.class}: #{e.message.lines.first.to_s.strip}"
  {}
end

def normalize_text(text)
  ensure_utf8(text).downcase.gsub(/[`"'“”‘’]/, " ").gsub(/[[:space:]]+/, " ").strip
end

def token_set(text)
  normalized = normalize_text(text)
  tokens = normalized.scan(/[a-z0-9][a-z0-9\-_\.]+|[一-龠々ぁ-んァ-ヶー]{2,}/u)
  Set.new(tokens.reject { |token| token.length <= 1 })
end

def ids_in(text)
  ensure_utf8(text).scan(/\b(?:T|M|D|DECISION|SELFREVIEW)-[A-Z0-9\-]+\b/i).map(&:upcase).uniq
end

def includes_phrase?(request_text, candidate_text)
  req = normalize_text(request_text)
  cand = normalize_text(candidate_text)
  return false if req.empty? || cand.empty?

  req.include?(cand) || cand.include?(req)
end

def score_candidate(request_text:, request_tokens:, request_ids:, id:, fields:)
  field_text = fields.compact.join(" ")
  field_tokens = token_set(field_text)
  union = (request_tokens | field_tokens).size
  overlap = (request_tokens & field_tokens).size
  jaccard = union.zero? ? 0.0 : overlap.to_f / union

  phrase_bonus = includes_phrase?(request_text, fields.first.to_s) ? 0.20 : 0.0
  id_bonus = 0.0
  candidate_ids = ids_in("#{id} #{field_text}")
  exact_id_match = request_ids.include?(id.to_s.upcase) || request_text.include?(id.to_s)
  related_id_match = !(request_ids & candidate_ids).empty?

  if exact_id_match
    id_bonus = 1.0
  elsif related_id_match
    id_bonus = 0.60
  end

  raw = jaccard + phrase_bonus + id_bonus
  score = [[raw, 1.0].min, 0.0].max

  {
    score: score.round(4),
    overlap: overlap,
    union: union
  }
end

def parse_decisions(path)
  return [] unless File.exist?(path)

  lines = read_utf8(path).each_line(chomp: true).map { |line| ensure_utf8(line) }
  decisions = []
  current = nil

  flush = lambda do
    if current && current[:id]
      current[:body] = current[:body_lines].join("\n").strip
      current.delete(:body_lines)
      decisions << current
    end
  end

  lines.each do |line|
    if line =~ /^##\s+([A-Z0-9\-]+):\s*(.+?)\s*\((\d{4}-\d{2}-\d{2})/
      flush.call
      current = {
        id: Regexp.last_match(1),
        title: Regexp.last_match(2).strip,
        date: Regexp.last_match(3),
        body_lines: [line]
      }
      next
    end

    if line =~ /^- ID:\s+(.+)$/
      flush.call
      current = {
        id: Regexp.last_match(1).strip,
        title: "",
        date: "",
        body_lines: [line]
      }
      next
    end

    if current
      current[:title] = Regexp.last_match(1).strip if line =~ /^ {2}Title:\s+(.+)$/
      current[:date] = Regexp.last_match(1).strip if line =~ /^ {2}Date:\s+(.+)$/
      current[:body_lines] << line
    end
  end

  flush.call
  decisions.last(DECISION_LIMIT)
end

warnings = []
request = ensure_utf8(ENV.fetch("REQUEST_TEXT")).strip

if request.empty?
  puts JSON.pretty_generate(
    {
      classification: "empty_request",
      related_tasks: [],
      related_milestones: [],
      related_decisions: [],
      suggested_action: "prompt_for_request",
      response_prefix: "【文脈】依頼内容が空です。要件を入力してください",
      warnings: warnings
    }
  )
  exit 0
end

tasks_data = load_yaml(".ai/TASKS.yaml", warnings: warnings)
goals = load_yaml(".ai/GOALS.yaml", warnings: warnings)
decisions = parse_decisions(".ai/DECISIONS.md")

tasks = Array(tasks_data["tasks"])

request_tokens = token_set(request)
request_ids = ids_in(request)

task_candidates = tasks.map do |task|
  next unless %w[running review queued].include?(task["status"].to_s)

  score_data = score_candidate(
    request_text: request,
    request_tokens: request_tokens,
    request_ids: request_ids,
    id: task["id"],
    fields: [
      task["title"],
      task["notes"],
      Array(task["acceptance"]).join(" ")
    ]
  )

  next if score_data[:score] < SUBTASK_THRESHOLD

  {
    id: task["id"],
    title: task["title"],
    status: task["status"],
    similarity: score_data[:score]
  }
end.compact

task_candidates.sort_by! { |task| [-task[:similarity], task[:id]] }

milestones = Array(goals["milestones"]).select { |item| item["status"] == "active" }
projects = Array(goals["projects"]).select { |item| item["status"] == "active" }

milestone_candidates = milestones.map do |milestone|
  score_data = score_candidate(
    request_text: request,
    request_tokens: request_tokens,
    request_ids: request_ids,
    id: milestone["id"],
    fields: [
      milestone["title"],
      milestone["description"],
      Array(milestone["acceptance"]).join(" ")
    ]
  )
  next if score_data[:score] < SUBTASK_THRESHOLD

  {
    id: milestone["id"],
    title: milestone["title"],
    similarity: score_data[:score]
  }
end.compact

project_candidates = projects.map do |project|
  score_data = score_candidate(
    request_text: request,
    request_tokens: request_tokens,
    request_ids: request_ids,
    id: project["id"],
    fields: [
      project["title"],
      project["description"],
      project["milestone_ref"],
      Array(project["tasks_ref"]).join(" ")
    ]
  )
  next if score_data[:score] < SUBTASK_THRESHOLD

  {
    id: project["id"],
    title: project["title"],
    milestone_ref: project["milestone_ref"],
    similarity: score_data[:score]
  }
end.compact

decision_candidates = decisions.map do |decision|
  score_data = score_candidate(
    request_text: request,
    request_tokens: request_tokens,
    request_ids: request_ids,
    id: decision[:id],
    fields: [decision[:title], decision[:body]]
  )
  next if score_data[:score] < SUBTASK_THRESHOLD

  {
    id: decision[:id],
    date: decision[:date],
    title: decision[:title],
    similarity: score_data[:score]
  }
end.compact

decision_candidates.sort_by! { |decision| [-decision[:similarity], decision[:id]] }
milestone_candidates.sort_by! { |milestone| [-milestone[:similarity], milestone[:id]] }
project_candidates.sort_by! { |project| [-project[:similarity], project[:id]] }

best_task = task_candidates.first
best_milestone = milestone_candidates.first
best_project = project_candidates.first

classification =
  if best_task && %w[running review].include?(best_task[:status]) && best_task[:similarity] >= TASK_THRESHOLD
    "task_continuation"
  elsif best_task || best_milestone || best_project || decision_candidates.any?
    "sub_task_of_active_project"
  else
    "new_project"
  end

suggested_action =
  case classification
  when "task_continuation" then "bind"
  when "sub_task_of_active_project" then "propose_sub_task"
  else "confirm_new_project"
  end

response_prefix =
  case classification
  when "task_continuation"
    "【文脈】#{best_task[:id]} (#{best_task[:status]}) の延長として処理します"
  when "sub_task_of_active_project"
    if best_milestone
      "【文脈】#{best_milestone[:id]} milestone 配下の新規タスクとして提案します"
    elsif best_project && best_project[:milestone_ref]
      "【文脈】#{best_project[:milestone_ref]} milestone 配下の新規タスクとして提案します"
    elsif best_task
      "【文脈】#{best_task[:id]} と整合する派生作業として扱います"
    else
      "【文脈】既存の active project と整合する派生作業として提案します"
    end
  else
    "【文脈】既存タスクとは独立。新規プロジェクト化を推奨"
  end

related_milestones = []
seen_milestones = Set.new

milestone_candidates.each do |milestone|
  next if seen_milestones.include?(milestone[:id])
  related_milestones << { id: milestone[:id], title: milestone[:title] }
  seen_milestones << milestone[:id]
  break if related_milestones.size >= 3
end

project_candidates.each do |project|
  next unless project[:milestone_ref]
  next if seen_milestones.include?(project[:milestone_ref])

  milestone = milestones.find { |item| item["id"] == project[:milestone_ref] }
  next unless milestone

  related_milestones << { id: milestone["id"], title: milestone["title"] }
  seen_milestones << milestone["id"]
  break if related_milestones.size >= 3
end

payload = {
  classification: classification,
  related_tasks: task_candidates.first(3).map { |task|
    {
      id: task[:id],
      title: task[:title],
      similarity: task[:similarity]
    }
  },
  related_milestones: related_milestones,
  related_decisions: decision_candidates.first(3).map { |decision|
    {
      id: decision[:id],
      date: decision[:date],
      title: decision[:title]
    }
  },
  suggested_action: suggested_action,
  response_prefix: response_prefix,
  warnings: warnings
}

puts JSON.pretty_generate(payload)
RUBY
