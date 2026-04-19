#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/authority/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/authority/os-mutation-check.sh --operation OPERATION --target TARGET [--diff-file PATCH]
USAGE
  exit 2
}

operation=""
target=""
diff_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --diff-file|--patch)
      [[ $# -ge 2 ]] || usage
      diff_file="$2"
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

[[ -n "$operation" ]] || usage
[[ -n "$target" ]] || usage

read_required_authority_inputs

if [[ -n "$diff_file" && ! -r "$diff_file" ]]; then
  reason="diff file is not readable: $diff_file"
  audit_json_line "$operation" "$target" false "$reason" owner_only false reject
  emit_decision_json false "$reason" owner_only false reject
  exit 0
fi

allow_os_mutation="$(control_allow_os_mutation)"
if [[ "$allow_os_mutation" != "true" ]]; then
  reason="CONTROL.yaml allow_os_mutation is not true"
  audit_json_line "$operation" "$target" false "$reason" owner_only false reject
  emit_decision_json false "$reason" owner_only false reject
  exit 0
fi

if is_protected_secret_target "$target"; then
  reason="target is a protected secret path"
  audit_json_line "$operation" "$target" false "$reason" owner_only false reject
  emit_decision_json false "$reason" owner_only false reject
  exit 0
fi

if is_kernel_target "$target"; then
  reason="target matches KERNEL_FILES and is always forbidden"
  audit_json_line "$operation" "$target" false "$reason" owner_only false reject
  emit_decision_json false "$reason" owner_only false reject
  exit 0
fi

if protocol_contains always_forbidden "$operation"; then
  reason="operation is listed in os_mutation_protocol.always_forbidden"
  audit_json_line "$operation" "$target" false "$reason" owner_only false reject
  emit_decision_json false "$reason" owner_only false reject
  exit 0
fi

if protocol_contains requires_owner_approval "$operation"; then
  reason="operation requires Owner approval"
  audit_json_line "$operation" "$target" false "$reason" ask_before_execute true request_approval
  emit_decision_json false "$reason" ask_before_execute true request_approval
  exit 0
fi

if protocol_contains allowed_when_os_mutation_true "$operation"; then
  reason="operation is allowed when allow_os_mutation is true"
  audit_json_line "$operation" "$target" true "$reason" execute_with_report false proceed
  emit_decision_json true "$reason" execute_with_report false proceed
  exit 0
fi

reason="operation is not defined in the OS Mutation Protocol"
audit_json_line "$operation" "$target" false "$reason" owner_only false reject
emit_decision_json false "$reason" owner_only false reject
