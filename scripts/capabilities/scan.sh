#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
OUTPUT_PATH="${OUTPUT_PATH:-$REPO_ROOT/.ai/CAPABILITIES.yaml}"
PROBE_DIR="$SCRIPT_DIR/probe"
TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

run_probe() {
  local script_path="$1"
  shift || true
  if [[ -x "$script_path" ]]; then
    "$script_path" "$@" 2>/dev/null || true
  fi
}

{
  printf '[\n'
  first=1

  append_json() {
    local payload="$1"
    [[ -z "$payload" ]] && return 0
    if [[ $first -eq 0 ]]; then
      printf ',\n'
    fi
    first=0
    printf '%s' "$payload"
  }

  append_json "$(run_probe "$PROBE_DIR/cli-codex.sh")"
  append_json "$(run_probe "$PROBE_DIR/cli-gh.sh")"
  append_json "$(run_probe "$PROBE_DIR/cli-git.sh")"
  append_json "$(run_probe "$PROBE_DIR/cli-supabase.sh")"
  append_json "$(run_probe "$PROBE_DIR/cli-vercel.sh")"
  append_json "$(run_probe "$PROBE_DIR/cli-stripe.sh")"
  append_json "$(run_probe "$PROBE_DIR/cli-aws.sh")"

  for tool in gcloud firebase npm docker brew psql redis-cli jq yq python3 node; do
    append_json "$(run_probe "$PROBE_DIR/cli-generic.sh" "$tool")"
  done

  printf '\n]\n'
} > "$TMP_JSON"

REPO_ROOT="$REPO_ROOT" OUTPUT_PATH="$OUTPUT_PATH" PROBE_RESULTS_PATH="$TMP_JSON" python3 - <<'PY'
from __future__ import annotations

import copy
import datetime as dt
import json
import os
from pathlib import Path
from typing import Any

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
output_path = Path(os.environ["OUTPUT_PATH"])
probe_results_path = Path(os.environ["PROBE_RESULTS_PATH"])
now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

DEFAULT_INPUT_RESOLUTION_ORDER = ["USER_PROFILE.facts", "ENV", "Owner"]
AUTO_OPERATION_FIELDS = {
    "name",
    "description",
    "command_template",
    "required_inputs",
    "input_resolution_order",
    "risk_level",
    "supports_dry_run",
    "owner_approval_required_for",
}


def load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    data = yaml.safe_load(path.read_text()) or {}
    return data if isinstance(data, dict) else {}


def rel_or_abs(path: Path) -> str:
    try:
        return str(path.relative_to(repo_root))
    except ValueError:
        return str(path)


RISK_DEFAULTS: dict[str, str] = {
    "cli_codex": "low",
    "cli_gh": "medium",
    "cli_git": "medium",
    "cli_supabase": "high",
    "cli_vercel": "high",
    "cli_stripe": "critical",
    "cli_aws": "critical",
    "cli_gcloud": "critical",
    "cli_firebase": "high",
    "cli_npm": "medium",
    "cli_docker": "high",
    "cli_brew": "medium",
    "cli_psql": "high",
    "cli_redis_cli": "high",
    "cli_jq": "low",
    "cli_yq": "low",
    "cli_python3": "medium",
    "cli_node": "medium",
}

DRY_RUN_DEFAULTS: dict[str, bool] = {
    "cli_codex": True,
    "cli_gh": False,
    "cli_git": True,
    "cli_supabase": False,
    "cli_vercel": True,
    "cli_stripe": False,
    "cli_aws": True,
    "cli_gcloud": True,
    "cli_firebase": True,
    "cli_npm": True,
    "cli_docker": True,
    "cli_brew": True,
    "cli_psql": False,
    "cli_redis_cli": False,
    "cli_jq": True,
    "cli_yq": True,
    "cli_python3": True,
    "cli_node": True,
}

APPROVAL_DEFAULTS: dict[str, list[dict[str, str]]] = {
    "cli_gh": [
        {"operation": "repo_delete", "reason": "repository deletion is destructive"},
        {"operation": "prod_secret_write", "reason": "production secret changes affect shared environments"},
    ],
    "cli_git": [
        {"operation": "history_rewrite", "reason": "rewriting history can disrupt collaborators"},
    ],
    "cli_supabase": [
        {"operation": "db_reset", "reason": "database reset is destructive"},
        {"operation": "billing", "reason": "billing changes require owner approval"},
        {"operation": "production_schema_change", "reason": "schema changes can affect live data"},
    ],
    "cli_vercel": [
        {"operation": "production_deploy", "reason": "production deploys affect live traffic"},
        {"operation": "billing", "reason": "plan or spend changes require owner approval"},
    ],
    "cli_stripe": [
        {"operation": "refund", "reason": "refunds affect money movement"},
        {"operation": "billing", "reason": "billing-affecting changes require owner approval"},
        {"operation": "production_webhook_change", "reason": "production payment flows are high risk"},
    ],
    "cli_aws": [
        {"operation": "delete", "reason": "cloud resource deletion can be destructive"},
        {"operation": "billing", "reason": "cloud changes may increase spend"},
        {"operation": "production_deploy", "reason": "production deploys require explicit approval"},
    ],
    "cli_gcloud": [
        {"operation": "delete", "reason": "cloud resource deletion can be destructive"},
        {"operation": "billing", "reason": "cloud changes may increase spend"},
    ],
    "cli_firebase": [
        {"operation": "production_deploy", "reason": "production changes affect live users"},
    ],
    "cli_npm": [
        {"operation": "publish", "reason": "package publication is externally visible"},
    ],
    "cli_docker": [
        {"operation": "push", "reason": "registry pushes affect downstream deployments"},
    ],
    "cli_brew": [
        {"operation": "upgrade", "reason": "toolchain upgrades can affect the local environment"},
    ],
    "cli_psql": [
        {"operation": "delete", "reason": "database mutations can cause data loss"},
    ],
    "cli_redis_cli": [
        {"operation": "flushall", "reason": "cache/database flush is destructive"},
    ],
}

COMMON_OPS: dict[str, list[dict[str, Any]]] = {
    "cli_codex": [
        {
            "name": "run_noninteractive_task",
            "description": "Execute a bounded Codex task from the terminal.",
            "command_template": 'codex exec --skip-git-repo-check "${prompt}"',
            "required_inputs": [{"name": "prompt", "type": "string"}],
            "input_resolution_order": list(DEFAULT_INPUT_RESOLUTION_ORDER),
            "risk_level": "low",
            "supports_dry_run": True,
            "owner_approval_required_for": [],
        }
    ],
    "cli_gh": [
        {
            "name": "view_pr",
            "description": "Inspect a pull request with structured output.",
            "command_template": "gh pr view ${pr_number} --json number,title,state,url",
            "required_inputs": [{"name": "pr_number", "type": "integer"}],
            "input_resolution_order": list(DEFAULT_INPUT_RESOLUTION_ORDER),
            "risk_level": "low",
            "supports_dry_run": False,
            "owner_approval_required_for": [],
        }
    ],
    "cli_supabase": [
        {
            "name": "get_project_api_keys",
            "description": "Fetch API keys for a known project.",
            "command_template": "supabase projects api-keys --project-ref ${project_ref}",
            "required_inputs": [{"name": "project_ref", "type": "string"}],
            "input_resolution_order": list(DEFAULT_INPUT_RESOLUTION_ORDER),
            "risk_level": "low",
            "supports_dry_run": False,
            "owner_approval_required_for": [],
        },
        {
            "name": "db_reset",
            "description": "Reset a linked database environment.",
            "command_template": "supabase db reset",
            "required_inputs": [],
            "input_resolution_order": list(DEFAULT_INPUT_RESOLUTION_ORDER),
            "risk_level": "critical",
            "supports_dry_run": False,
            "owner_approval_required_for": ["destructive", "owner"],
        },
    ],
    "cli_vercel": [
        {
            "name": "whoami",
            "description": "Verify the current Vercel account context.",
            "command_template": "vercel whoami",
            "required_inputs": [],
            "input_resolution_order": list(DEFAULT_INPUT_RESOLUTION_ORDER),
            "risk_level": "low",
            "supports_dry_run": True,
            "owner_approval_required_for": [],
        }
    ],
    "cli_stripe": [
        {
            "name": "list_config",
            "description": "Inspect local Stripe CLI configuration.",
            "command_template": "stripe config --list",
            "required_inputs": [],
            "input_resolution_order": list(DEFAULT_INPUT_RESOLUTION_ORDER),
            "risk_level": "low",
            "supports_dry_run": True,
            "owner_approval_required_for": [],
        }
    ],
    "cli_aws": [
        {
            "name": "get_caller_identity",
            "description": "Check the active AWS account identity.",
            "command_template": "aws sts get-caller-identity",
            "required_inputs": [],
            "input_resolution_order": list(DEFAULT_INPUT_RESOLUTION_ORDER),
            "risk_level": "low",
            "supports_dry_run": True,
            "owner_approval_required_for": [],
        }
    ],
}

MCP_COMPAT_DEFAULTS: dict[str, dict[str, Any]] = {
    "cli_codex": {
        "resource_type": "cli/codex",
        "tool_schema": {"type": "object", "properties": {"prompt": {"type": "string"}}, "required": ["prompt"]},
    },
    "cli_gh": {
        "resource_type": "cli/github",
        "tool_schema": {"type": "object", "properties": {"pr_number": {"type": "integer"}}},
    },
    "cli_supabase": {
        "resource_type": "cli/supabase",
        "tool_schema": {"type": "object", "properties": {"project_ref": {"type": "string"}}},
    },
    "cli_vercel": {"resource_type": "cli/vercel", "tool_schema": {"type": "object", "properties": {}}},
    "cli_stripe": {"resource_type": "cli/stripe", "tool_schema": {"type": "object", "properties": {}}},
    "cli_aws": {"resource_type": "cli/aws", "tool_schema": {"type": "object", "properties": {}}},
}


def generic_name(capability_id: str) -> str:
    parts = capability_id.split("_", 1)
    tail = parts[1] if len(parts) == 2 else capability_id
    return tail.replace("_", "-")


def normalize_operation(operation: dict[str, Any], capability: dict[str, Any]) -> dict[str, Any]:
    normalized = copy.deepcopy(operation)
    normalized.setdefault("description", "")
    normalized.setdefault("command_template", "")
    normalized["required_inputs"] = normalized.get("required_inputs") or []
    normalized["input_resolution_order"] = normalized.get("input_resolution_order") or list(DEFAULT_INPUT_RESOLUTION_ORDER)
    normalized.setdefault("risk_level", capability.get("risk_level", "medium"))
    normalized.setdefault("supports_dry_run", capability.get("supports_dry_run", False))
    normalized["owner_approval_required_for"] = normalized.get("owner_approval_required_for") or []
    return normalized


def merge_operations(existing_ops: list[Any], generated_ops: list[Any], capability: dict[str, Any]) -> list[dict[str, Any]]:
    existing_by_name = {
        item.get("name"): copy.deepcopy(item)
        for item in existing_ops
        if isinstance(item, dict) and item.get("name")
    }
    merged_ops: list[dict[str, Any]] = []
    generated_names: set[str] = set()

    for generated in generated_ops:
        if not isinstance(generated, dict) or not generated.get("name"):
            continue
        name = generated["name"]
        generated_names.add(name)
        existing = existing_by_name.get(name, {})
        merged = copy.deepcopy(existing)
        merged.update(copy.deepcopy(generated))
        for key, value in existing.items():
            if key not in AUTO_OPERATION_FIELDS and key not in generated:
                merged[key] = copy.deepcopy(value)
        merged_ops.append(normalize_operation(merged, capability))

    for name, existing in existing_by_name.items():
        if name in generated_names:
            continue
        merged_ops.append(normalize_operation(existing, capability))

    return merged_ops


def base_cli_entry(probe: dict[str, Any]) -> dict[str, Any]:
    capability_id = probe["id"]
    tool_name = generic_name(capability_id)
    verified_at = now if probe.get("status") == "available" else None
    entry = {
        "id": capability_id,
        "kind": "cli",
        "name": tool_name,
        "command": tool_name,
        "path": probe.get("path"),
        "version": probe.get("version"),
        "status": probe.get("status", "unknown"),
        "auth_status": probe.get("auth_status", "unknown"),
        "verified_at": verified_at,
        "risk_level": RISK_DEFAULTS.get(capability_id, "medium"),
        "supports_dry_run": DRY_RUN_DEFAULTS.get(capability_id, False),
        "owner_approval_required_for": APPROVAL_DEFAULTS.get(capability_id, []),
        "common_operations": COMMON_OPS.get(capability_id, []),
        "mcp_compat": MCP_COMPAT_DEFAULTS.get(
            capability_id,
            {"resource_type": "cli/generic", "tool_schema": {"type": "object", "properties": {}}},
        ),
    }
    if probe.get("error_detail"):
        entry["error_detail"] = probe["error_detail"]
    return entry


def infer_auth_status(kind: str) -> str:
    if kind in {"internal_skill", "internal_agent", "script"}:
        return "not_required"
    if kind == "mcp":
        return "not_required"
    return "unknown"


def scan_mcp() -> list[dict[str, Any]]:
    configs: list[tuple[Path, str]] = [
        (Path.home() / ".config/claude-code/mcp.json", "claude-code"),
        (Path.home() / ".claude.json", "home"),
        (repo_root / ".claude.json", "repo"),
        (repo_root / ".mcp.json", "repo"),
    ]
    seen: set[str] = set()
    entries: list[dict[str, Any]] = []
    for path, source_name in configs:
        if not path.exists():
            continue
        try:
            payload = json.loads(path.read_text())
        except Exception:
            continue
        servers = payload.get("mcpServers") or payload.get("mcp_servers") or {}
        if not isinstance(servers, dict):
            continue
        for server_name, server_config in servers.items():
            if server_name in seen:
                continue
            seen.add(server_name)
            server_config = server_config or {}
            command = None
            version = None
            if isinstance(server_config, dict):
                command = server_config.get("command")
                version = server_config.get("version")
            risk_level = "medium"
            supports_dry_run = True
            approvals = ["destructive"]
            entry = {
                "id": f"mcp_{server_name.replace('-', '_')}",
                "kind": "mcp",
                "name": server_name,
                "command": command,
                "path": None,
                "version": version,
                "status": "available",
                "auth_status": "not_required",
                "verified_at": now,
                "risk_level": risk_level,
                "supports_dry_run": supports_dry_run,
                "owner_approval_required_for": [
                    {"operation": "delete", "reason": "MCP tools may expose destructive operations depending on the server"}
                ],
                "common_operations": [
                    {
                        "name": "connect",
                        "description": f"Use the registered MCP server from {source_name} configuration.",
                        "command_template": f"mcp://{server_name}",
                        "required_inputs": [],
                        "input_resolution_order": list(DEFAULT_INPUT_RESOLUTION_ORDER),
                        "risk_level": risk_level,
                        "supports_dry_run": supports_dry_run,
                        "owner_approval_required_for": approvals,
                    }
                ],
                "mcp_compat": {
                    "resource_type": "mcp/server",
                    "tool_schema": {"type": "object", "properties": {}},
                },
            }
            entries.append(entry)
    return entries


def scan_internal_markdown(base_dir: Path, kind: str, prefix: str) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    if not base_dir.exists():
        return entries
    for path in sorted(base_dir.glob("*.md")):
        slug = path.stem.replace("-", "_")
        risk_level = "low"
        supports_dry_run = True
        entries.append(
            {
                "id": f"{prefix}_{slug}",
                "kind": kind,
                "name": path.stem,
                "command": None,
                "path": rel_or_abs(path),
                "version": None,
                "status": "available",
                "auth_status": "not_required",
                "verified_at": now,
                "risk_level": risk_level,
                "supports_dry_run": supports_dry_run,
                "owner_approval_required_for": [],
                "common_operations": [
                    {
                        "name": "load_definition",
                        "description": f"Load {kind.replace('_', ' ')} instructions from the repository.",
                        "command_template": rel_or_abs(path),
                        "required_inputs": [],
                        "input_resolution_order": list(DEFAULT_INPUT_RESOLUTION_ORDER),
                        "risk_level": risk_level,
                        "supports_dry_run": supports_dry_run,
                        "owner_approval_required_for": [],
                    }
                ],
                "mcp_compat": {"resource_type": f"internal/{kind}", "tool_schema": None},
            }
        )
    return entries


def scan_scripts() -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    scripts_root = repo_root / "scripts"
    if not scripts_root.exists():
        return entries
    for path in sorted(scripts_root.rglob("*.sh")):
        if ".git" in path.parts or path.name.startswith("."):
            continue
        slug = "_".join(path.relative_to(scripts_root).with_suffix("").parts).replace("-", "_")
        supports_dry_run = True if "dry-run" in path.name or "eval" in path.parts else False
        risk_level = "medium"
        approvals = ["destructive"] if risk_level in {"high", "critical"} else []
        entries.append(
            {
                "id": f"script_{slug}",
                "kind": "script",
                "name": str(path.relative_to(scripts_root)),
                "command": None,
                "path": rel_or_abs(path),
                "version": None,
                "status": "available",
                "auth_status": "not_required",
                "verified_at": now,
                "risk_level": risk_level,
                "supports_dry_run": supports_dry_run,
                "owner_approval_required_for": [],
                "common_operations": [
                    {
                        "name": "run_script",
                        "description": "Execute the repository script directly.",
                        "command_template": rel_or_abs(path),
                        "required_inputs": [],
                        "input_resolution_order": list(DEFAULT_INPUT_RESOLUTION_ORDER),
                        "risk_level": risk_level,
                        "supports_dry_run": supports_dry_run,
                        "owner_approval_required_for": approvals,
                    }
                ],
                "mcp_compat": {"resource_type": "internal/script", "tool_schema": None},
            }
        )
    return entries


existing = load_yaml(output_path)
existing_capabilities = existing.get("capabilities") or []
existing_by_id = {item.get("id"): item for item in existing_capabilities if isinstance(item, dict) and item.get("id")}

probe_entries = []
if probe_results_path.exists():
    try:
        probe_entries = json.loads(probe_results_path.read_text())
    except Exception:
        probe_entries = []

generated: list[dict[str, Any]] = []
for probe in probe_entries:
    if isinstance(probe, dict) and probe.get("id"):
        generated.append(base_cli_entry(probe))

generated.extend(scan_mcp())
generated.extend(scan_internal_markdown(repo_root / ".claude" / "skills", "internal_skill", "internal_skill"))
generated.extend(scan_internal_markdown(repo_root / ".claude" / "agents", "internal_agent", "internal_agent"))
generated.extend(scan_scripts())

generated_by_id = {entry["id"]: entry for entry in generated}
all_ids = sorted(set(existing_by_id) | set(generated_by_id))

merged_capabilities: list[dict[str, Any]] = []
for capability_id in all_ids:
    generated_entry = copy.deepcopy(generated_by_id.get(capability_id, {}))
    existing_entry = copy.deepcopy(existing_by_id.get(capability_id, {}))
    merged = dict(existing_entry)
    merged.update(generated_entry)

    merged.setdefault("name", capability_id)
    merged.setdefault("command", None)
    merged.setdefault("path", None)
    merged.setdefault("version", None)
    merged.setdefault("status", "unknown")
    merged.setdefault("auth_status", infer_auth_status(merged.get("kind", "")))
    if "verified_at" not in merged:
        merged["verified_at"] = None
    merged.setdefault("risk_level", "medium")
    merged.setdefault("supports_dry_run", False)
    merged.setdefault("owner_approval_required_for", [])
    merged.setdefault("common_operations", [])
    merged.setdefault("mcp_compat", {"resource_type": None, "tool_schema": None})

    if existing_entry and generated_entry:
        stable_keys = ("kind", "command", "path", "version", "status", "auth_status")
        if all(existing_entry.get(key) == generated_entry.get(key) for key in stable_keys):
            merged["verified_at"] = existing_entry.get("verified_at")

    if merged.get("status") != "available" and capability_id in existing_by_id:
        old = existing_by_id[capability_id]
        if old.get("status") == "available" and capability_id not in generated_by_id:
            merged["status"] = "unknown"
            merged["verified_at"] = old.get("verified_at")

    if "error_detail" not in generated_entry and "error_detail" in existing_entry:
        merged["error_detail"] = existing_entry["error_detail"]
    if merged.get("error_detail") is None:
        merged.pop("error_detail", None)

    merged["common_operations"] = merge_operations(
        existing_entry.get("common_operations") or [],
        generated_entry.get("common_operations") or [],
        merged,
    )

    merged_capabilities.append(merged)

output_path.parent.mkdir(parents=True, exist_ok=True)
yaml.safe_dump(
    {"capabilities": merged_capabilities},
    output_path.open("w"),
    sort_keys=False,
    allow_unicode=False,
    width=100,
)

summary = {
    "output": str(output_path),
    "count": len(merged_capabilities),
    "available": sum(1 for item in merged_capabilities if item.get("status") == "available"),
    "kinds": {},
}
for item in merged_capabilities:
    kind = item.get("kind", "unknown")
    summary["kinds"][kind] = summary["kinds"].get(kind, 0) + 1

print(json.dumps(summary))
PY
