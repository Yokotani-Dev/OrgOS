#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/authority/check-approval.sh --request-id REQUEST_ID [--mark-applied | --mark-applied-and-failed --note NOTE]
USAGE
  exit 2
}

die() {
  echo "error: $*" >&2
  exit 1
}

request_id=""
mark=""
note=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --request-id)
      [[ $# -ge 2 ]] || usage
      request_id="$2"
      shift 2
      ;;
    --mark-applied)
      mark="applied"
      shift
      ;;
    --mark-applied-and-failed)
      mark="applied_and_failed"
      shift
      ;;
    --note)
      [[ $# -ge 2 ]] || usage
      note="$2"
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

[[ -n "$request_id" ]] || usage
[[ "$request_id" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid request id"
command -v ruby >/dev/null 2>&1 || die "ruby is required"

REQUEST_ID="$request_id" MARK="$mark" NOTE="$note" REPO_ROOT="$REPO_ROOT" ruby -ryaml -rjson -rtime -rfileutils -e '
  repo_root = ENV.fetch("REPO_ROOT")
  request_id = ENV.fetch("REQUEST_ID")
  mark = ENV.fetch("MARK")
  note = ENV.fetch("NOTE")
  approval_file = File.join(repo_root, ".ai", "APPROVALS", "#{request_id}.yaml")
  comments_file = File.join(repo_root, ".ai", "OWNER_COMMENTS.md")
  audit_dir = File.join(repo_root, ".ai", "AUDIT")
  decisions_file = File.join(repo_root, ".ai", "DECISIONS.md")

  abort("error: approval request not found: #{request_id}") unless File.file?(approval_file)

  data = YAML.load_file(approval_file) || {}
  now = Time.now.utc

  def audit(audit_dir, event, data, status, now)
    FileUtils.mkdir_p(audit_dir)
    line = {
      timestamp: now.iso8601,
      event: event,
      request_id: data["request_id"],
      task_id: data["task_id"],
      operation: data["operation"],
      target: data["target"],
      status: status
    }
    File.open(File.join(audit_dir, "approval-#{now.strftime("%F")}.log"), "a") do |f|
      f.puts(JSON.generate(line))
    end
  end

  def write_data(path, data)
    File.write(path, YAML.dump(data))
  end

  current_status = data["status"] || "pending"

  if mark == "applied"
    data["status"] = "applied"
    data["applied_at"] = now.iso8601
    write_data(approval_file, data)
    audit(audit_dir, "applied", data, data["status"], now)
  elsif mark == "applied_and_failed"
    data["status"] = "applied_and_failed"
    data["failure_at"] = now.iso8601
    data["failure_note"] = note
    write_data(approval_file, data)
    audit(audit_dir, "applied_and_failed", data, data["status"], now)
  elsif current_status == "pending"
    comments = File.file?(comments_file) ? File.read(comments_file) : ""
    response = nil
    comments.each_line do |line|
      if line.match?(/(?:^|[[:space:]])approve[[:space:]]+#{Regexp.escape(request_id)}(?:[[:space:]]|$)/i)
        response = "approved"
        break
      elsif line.match?(/(?:^|[[:space:]])reject[[:space:]]+#{Regexp.escape(request_id)}(?:[[:space:]]|$)/i)
        response = "rejected"
        break
      end
    end

    if response
      data["status"] = response
      data["response"] = response == "approved" ? "approve" : "reject"
      data["responded_at"] = now.iso8601
      write_data(approval_file, data)
      audit(audit_dir, response, data, data["status"], now)
    else
      requested_at = Time.parse(data.fetch("requested_at"))
      if now - requested_at >= 86_400
        data["status"] = "expired"
        data["expired_at"] = now.iso8601
        data["timeout_behavior"] = data["emergency"] ? "emergency_decision_required" : "downgrade_to_silent_execute_or_lower"

        if data["emergency"] && !data["emergency_recorded_at"]
          emergency_id = "EMERGENCY-#{now.strftime("%Y%m%d%H%M%S")}"
          File.open(decisions_file, "a") do |f|
            f.puts
            f.puts("## #{emergency_id}: Approval timeout")
            f.puts
            f.puts("- Request ID: #{request_id}")
            f.puts("- Task ID: #{data["task_id"]}")
            f.puts("- Operation: #{data["operation"]}")
            f.puts("- Target: #{data["target"]}")
            f.puts("- Reason: P0 emergency approval timeout; minimal recovery path requires Owner follow-up.")
          end
          data["emergency_recorded_at"] = now.iso8601
          data["emergency_decision_id"] = emergency_id
        end

        write_data(approval_file, data)
        audit(audit_dir, "expired", data, data["status"], now)
      end
    end
  end

  output = {
    status: data["status"] || "pending",
    responded_at: data["responded_at"],
    request_id: request_id
  }
  output[:expired_at] = data["expired_at"] if data["expired_at"]
  output[:applied_at] = data["applied_at"] if data["applied_at"]
  output[:failure_at] = data["failure_at"] if data["failure_at"]
  puts(JSON.generate(output))
'
