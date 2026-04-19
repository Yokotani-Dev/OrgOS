#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/authority/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/authority/role-matrix-check.sh --principal PRINCIPAL --operation OPERATION --target TARGET
USAGE
  exit 2
}

principal=""
operation=""
target=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --principal)
      [[ $# -ge 2 ]] || usage
      principal="$2"
      shift 2
      ;;
    --operation)
      [[ $# -ge 2 ]] || usage
      operation="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || usage
      target="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$principal" ]] || usage
[[ -n "$operation" ]] || usage
[[ -n "$target" ]] || usage

target="$(repo_relpath "$target")"

ROLE_MATRIX_SCHEMA="${RBAC_ROLE_MATRIX_SCHEMA:-$ROLE_MATRIX_SCHEMA}" \
REPO_ROOT="$REPO_ROOT" \
RBAC_PRINCIPAL="$principal" \
RBAC_OPERATION="$operation" \
RBAC_TARGET="$target" \
RBAC_ALLOWED_PATHS="${CODEX_ALLOWED_PATHS:-${ALLOWED_PATHS:-}}" \
ruby <<'RUBY'
require "json"
require "yaml"
require "time"
require "fileutils"

repo_root = ENV.fetch("REPO_ROOT")
schema_path = ENV.fetch("ROLE_MATRIX_SCHEMA")
principal = ENV.fetch("RBAC_PRINCIPAL")
operation = ENV.fetch("RBAC_OPERATION")
target = ENV.fetch("RBAC_TARGET").sub(%r{\A\./}, "")
allowed_paths_env = ENV.fetch("RBAC_ALLOWED_PATHS", "")

def audit(repo_root, principal, operation, target, reason, level: "reject")
  dir = File.join(repo_root, ".ai", "AUDIT")
  FileUtils.mkdir_p(dir)
  path = File.join(dir, "rbac-#{Time.now.strftime("%F")}.log")
  record = {
    timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    principal: principal,
    operation: operation,
    target: target,
    rejected_reason: reason,
    level: level
  }
  File.open(path, "a") { |f| f.puts(JSON.generate(record)) }
end

def emit(allowed:, principal:, target:, operation:, reason:, required_principal: [])
  puts JSON.pretty_generate(
    {
      allowed: allowed,
      principal: principal,
      target: target,
      operation: operation,
      reason: reason,
      required_principal: required_principal
    }
  )
end

def matrix_from_yaml(path)
  data = YAML.load_file(path)
  examples = data["examples"] if data.is_a?(Hash)
  example = examples&.find { |item| item.is_a?(Hash) && item["role_matrix"].is_a?(Hash) }
  return example["role_matrix"] if example

  data["role_matrix"] if data.is_a?(Hash) && data["role_matrix"].is_a?(Hash)
end

def glob_match?(pattern, target)
  pattern = pattern.to_s.sub(%r{\A\./}, "").sub(%r{/\z}, "/**")
  File.fnmatch?(pattern, target, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB)
end

def split_patterns(value)
  value.to_s.split(/[:\n,]/).map(&:strip).reject(&:empty?)
end

def os_core_target?(target)
  target == "CLAUDE.md" ||
    target == "AGENTS.md" ||
    target.start_with?(".claude/") ||
    target.start_with?("scripts/authority/")
end

def manager_allowed?(pattern, target)
  return true if glob_match?(pattern, target)
  return true if pattern == ".ai/*" && target.start_with?(".ai/")
  false
end

begin
  matrix = matrix_from_yaml(schema_path)
  raise "role_matrix not found" unless matrix.is_a?(Hash)
rescue StandardError => e
  reason = "warning: role-matrix.yaml could not be read; fail-open: #{e.message}"
  warn reason
  audit(repo_root, principal, operation, target, reason, level: "warning")
  emit(
    allowed: true,
    principal: principal,
    target: target,
    operation: operation,
    reason: reason,
    required_principal: []
  )
  exit 0
end

role = matrix[principal]
unless role.is_a?(Hash)
  reason = "principal is not defined in role matrix"
  audit(repo_root, principal, operation, target, reason)
  emit(
    allowed: false,
    principal: principal,
    target: target,
    operation: operation,
    reason: reason,
    required_principal: ["owner", "manager"]
  )
  exit 0
end

if ["read", "view", "inspect"].include?(operation)
  reason = "read-only operation is allowed by role matrix"
  emit(
    allowed: true,
    principal: principal,
    target: target,
    operation: operation,
    reason: reason,
    required_principal: []
  )
  exit 0
end

read_only = Array(role["read_only"])
if principal == "codex_reviewer" && read_only.include?("review_target_files")
  reason = "codex_reviewer is read-only for implementation files"
  audit(repo_root, principal, operation, target, reason)
  emit(
    allowed: false,
    principal: principal,
    target: target,
    operation: operation,
    reason: reason,
    required_principal: ["codex_implementer", "manager"]
  )
  exit 0
end

matched_read_only = read_only.find { |pattern| glob_match?(pattern, target) }
if matched_read_only
  reason = "#{principal} cannot edit read-only path #{matched_read_only}"
  audit(repo_root, principal, operation, target, reason)
  emit(
    allowed: false,
    principal: principal,
    target: target,
    operation: operation,
    reason: reason,
    required_principal: ["owner", "manager"]
  )
  exit 0
end

can_edit = Array(role["can_edit"])

if can_edit.include?("all")
  emit(
    allowed: true,
    principal: principal,
    target: target,
    operation: operation,
    reason: "#{principal} can edit all paths",
    required_principal: []
  )
  exit 0
end

if can_edit.include?("allowed_paths_only")
  allowed_paths = split_patterns(allowed_paths_env)
  if allowed_paths.any? { |pattern| glob_match?(pattern, target) || pattern == target }
    emit(
      allowed: true,
      principal: principal,
      target: target,
      operation: operation,
      reason: "#{principal} can edit target listed in allowed paths",
      required_principal: []
    )
    exit 0
  end

  reason =
    if os_core_target?(target)
      "#{principal} cannot edit OS core files"
    else
      "#{principal} can edit only task allowed_paths"
    end
  audit(repo_root, principal, operation, target, reason)
  emit(
    allowed: false,
    principal: principal,
    target: target,
    operation: operation,
    reason: reason,
    required_principal: os_core_target?(target) ? ["owner", "manager"] : ["manager"]
  )
  exit 0
end

matched_can_edit = can_edit.find do |pattern|
  if pattern.include?(" when ")
    next principal == "manager" && pattern.start_with?("os_mutation_protocol.allowed_when_os_mutation_true")
  end
  principal == "manager" ? manager_allowed?(pattern, target) : glob_match?(pattern, target)
end

if matched_can_edit
  emit(
    allowed: true,
    principal: principal,
    target: target,
    operation: operation,
    reason: "#{principal} can edit #{matched_can_edit}",
    required_principal: []
  )
  exit 0
end

reason = "#{principal} cannot edit target by role matrix"
audit(repo_root, principal, operation, target, reason)
emit(
  allowed: false,
  principal: principal,
  target: target,
  operation: operation,
  reason: reason,
  required_principal: ["owner", "manager"]
)
exit 0
RUBY
