#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/session/priority-ranker.sh < /tmp/tasks.json
  bash scripts/session/priority-ranker.sh --top 5 < /tmp/tasks.json

Input JSON:
  {
    "tasks": [...],
    "preferences": [...],
    "top_n": 5
  }
EOF
}

top_n=""

while [[ $# -gt 0 ]]; do
  case "$1" in
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

input_json="$(cat)"
[[ -n "${input_json}" ]] || {
  echo "error: JSON input is required via stdin" >&2
  exit 1
}

INPUT_JSON="${input_json}" TOP_N_OVERRIDE="${top_n}" ruby_utf8 <<'RUBY'
# encoding: utf-8
require "json"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

input = JSON.parse(ENV.fetch("INPUT_JSON"))
tasks = Array(input["tasks"])
preferences = Array(input["preferences"]).map { |item| item.to_s }
top_n = (ENV["TOP_N_OVERRIDE"].to_s.empty? ? input["top_n"] : ENV["TOP_N_OVERRIDE"]).to_i
top_n = 5 if top_n <= 0

def extract_priority(task)
  explicit = task["priority"].to_s.strip
  return explicit unless explicit.empty?

  title = task["title"].to_s
  match = title.match(/\b(P[0-3])\b/i)
  return match[1].upcase if match

  "P2"
end

def priority_weight(priority)
  case priority
  when "P0" then 10
  when "P1" then 5
  else 1
  end
end

def normalized_blob(task)
  [
    task["id"],
    task["title"],
    task["notes"],
    Array(task["acceptance"]).join(" "),
    Array(task["tags"]).join(" "),
    task["owner_role"],
    task["milestone_ref"]
  ].compact.join(" ").downcase
end

def preference_bonus(task, preferences)
  blob = normalized_blob(task)
  bonus = 0
  matched = []

  preferences.each do |pref|
    pref_norm = pref.downcase

    if pref_norm.include?("cli > gui")
      if blob.match?(/\b(cli|shell|script|tooling|command|terminal|codex|bash)\b/) || task["owner_role"].to_s == "codex-implementer"
        bonus += 1
        matched << "CLI > GUI"
      end
    elsif pref_norm.include?("自律実行") || pref_norm.include?("autonomous")
      if blob.match?(/silent|autonom|自律|自動|org-evolve|hook|protocol|automation|manager/) || task["owner_role"].to_s == "codex-implementer"
        bonus += 1
        matched << "自律実行 > 確認待ち"
      end
    else
      pref_tokens = pref_norm.scan(/[a-z0-9][a-z0-9\-_]+|[一-龠々ぁ-んァ-ヶー]{2,}/u)
      next if pref_tokens.empty?

      overlap = pref_tokens.count { |token| blob.include?(token) }
      if overlap.positive?
        bonus += 1
        matched << pref
      end
    end
  end

  {
    score: [bonus, 2].min,
    matched: matched.uniq.first(2)
  }
end

ranked = tasks.map do |task|
  priority = extract_priority(task)
  pref = preference_bonus(task, preferences)
  blocker_release_bonus = task["blocker_release"] ? 2 : 0
  recent_momentum = task["recent_related"] ? 1 : 0
  score = priority_weight(priority) + blocker_release_bonus + recent_momentum + pref[:score]

  task.merge(
    "priority" => priority,
    "priority_weight" => priority_weight(priority),
    "blocker_release_bonus" => blocker_release_bonus,
    "recent_momentum_bonus" => recent_momentum,
    "owner_preference_bonus" => pref[:score],
    "matched_preferences" => pref[:matched],
    "score" => score
  )
end

ranked.sort_by! do |task|
  [
    -task["score"].to_i,
    -task["priority_weight"].to_i,
    task["id"].to_s
  ]
end

payload = {
  top_n: top_n,
  ranked_tasks: ranked.first(top_n)
}

puts JSON.pretty_generate(payload)
RUBY
