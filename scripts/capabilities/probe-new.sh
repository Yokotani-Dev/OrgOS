#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
KNOWN_PATH="${KNOWN_PATH:-$REPO_ROOT/.ai/CAPABILITIES.example.yaml}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.ai/EVOLUTION/proposals}"
SOURCE_FIXTURE=""
STDOUT=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash scripts/capabilities/probe-new.sh [options]

Detect new model-alias / MCP / CLI capabilities by comparing known
.ai/CAPABILITIES.example.yaml entries with offline stub or fixture sources.
No provider API calls are made.

Options:
  --known <path>           Known capability YAML. Default: .ai/CAPABILITIES.example.yaml
  --source-fixture <path>  YAML/JSON source fixture to use instead of the built-in stub.
  --output-dir <path>      Proposal output directory. Default: .ai/EVOLUTION/proposals
  --stdout                Print generated proposals to stdout.
  --dry-run               Do not write proposal files.
  -h, --help              Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --known)
      KNOWN_PATH="${2:-}"
      if [[ -z "$KNOWN_PATH" ]]; then
        echo "--known requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --source-fixture)
      SOURCE_FIXTURE="${2:-}"
      if [[ -z "$SOURCE_FIXTURE" ]]; then
        echo "--source-fixture requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      if [[ -z "$OUTPUT_DIR" ]]; then
        echo "--output-dir requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --stdout)
      STDOUT=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

export REPO_ROOT KNOWN_PATH OUTPUT_DIR SOURCE_FIXTURE STDOUT DRY_RUN

python3 - <<'PY'
from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
known_path = Path(os.environ["KNOWN_PATH"])
if not known_path.is_absolute():
    known_path = repo_root / known_path
output_dir = Path(os.environ["OUTPUT_DIR"])
if not output_dir.is_absolute():
    output_dir = repo_root / output_dir
source_fixture = os.environ.get("SOURCE_FIXTURE", "")
stdout_enabled = os.environ["STDOUT"] == "1"
dry_run = os.environ["DRY_RUN"] == "1"

FORBIDDEN_TARGETS = {
    "AGENTS.md",
    "CLAUDE.md",
    ".claude/rules/rationalization-prevention.md",
    ".claude/rules/request-intake-loop.md",
}

DEFAULT_SOURCE_CAPABILITIES: list[dict[str, Any]] = [
    {
        "id": "reasoning-primary@^1.1.0",
        "kind": "model_alias",
        "source": "openai_changelog_stub",
        "source_url": "stub://openai/changelog",
        "role_hint": "deep-reasoning",
        "capability_class": "reasoning",
        "summary": "New reasoning alias candidate with larger long-context suitability.",
        "target_file": ".claude/schemas/capability-roles.yaml",
    },
    {
        "id": "codegen-primary@^1.1.0",
        "kind": "model_alias",
        "source": "anthropic_changelog_stub",
        "source_url": "stub://anthropic/changelog",
        "role_hint": "code-generation",
        "capability_class": "code",
        "summary": "New code generation alias candidate for implementation-heavy tasks.",
        "target_file": ".claude/schemas/capability-roles.yaml",
    },
    {
        "id": "mcp_vercel_gateway",
        "kind": "mcp",
        "source": "vercel_changelog_stub",
        "source_url": "stub://vercel/changelog",
        "role_hint": "tool-use",
        "capability_class": "tool-use",
        "summary": "New MCP gateway candidate for hosted model routing.",
        "target_file": ".ai/CAPABILITIES.example.yaml",
    },
]


def utc_now() -> datetime:
    override = os.environ.get("ORGOS_PROBE_NOW")
    if override:
        try:
            return datetime.fromisoformat(override.replace("Z", "+00:00")).astimezone(timezone.utc)
        except ValueError:
            log("warning", "invalid_time_override", value=override)
    return datetime.now(timezone.utc).replace(microsecond=0)


def log(level: str, event: str, **fields: Any) -> None:
    payload = {
        "level": level,
        "event": event,
        "component": "capability-probe-new",
        **fields,
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), file=sys.stderr)


def load_yaml_or_json(path: Path) -> Any:
    raw = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        return json.loads(raw)
    return yaml.safe_load(raw)


def load_known_ids(path: Path) -> set[str]:
    if not path.exists():
        log("warning", "known_capabilities_missing", path=str(path), recovery="using empty known set")
        return set()
    try:
        data = load_yaml_or_json(path) or {}
    except Exception as exc:  # noqa: BLE001 - CLI boundary with structured log.
        log("warning", "known_capabilities_read_failed", path=str(path), error=str(exc), recovery="using empty known set")
        return set()

    capabilities = data.get("capabilities") if isinstance(data, dict) else []
    if not isinstance(capabilities, list):
        log("warning", "known_capabilities_invalid", path=str(path), recovery="using empty known set")
        return set()

    known: set[str] = set()
    for capability in capabilities:
        if not isinstance(capability, dict):
            continue
        for key in ("id", "command", "name"):
            value = capability.get(key)
            if value:
                known.add(str(value))
    return known


def load_source_capabilities(path_text: str) -> list[dict[str, Any]]:
    if not path_text:
        log("info", "source_stub_loaded", source_count=len(DEFAULT_SOURCE_CAPABILITIES))
        return list(DEFAULT_SOURCE_CAPABILITIES)

    path = Path(path_text)
    if not path.is_absolute():
        path = repo_root / path
    if not path.exists():
        log("warning", "source_fixture_missing", path=str(path), recovery="skipping source check")
        return []

    try:
        data = load_yaml_or_json(path) or []
    except Exception as exc:  # noqa: BLE001 - CLI boundary with structured log.
        log("warning", "source_fixture_read_failed", path=str(path), error=str(exc), recovery="skipping source check")
        return []

    capabilities = data.get("capabilities") if isinstance(data, dict) else data
    if not isinstance(capabilities, list):
        log("warning", "source_fixture_invalid", path=str(path), recovery="skipping source check")
        return []

    rows = [row for row in capabilities if isinstance(row, dict) and row.get("id") and row.get("kind")]
    log("info", "source_fixture_loaded", path=str(path), source_count=len(rows))
    return rows


def next_index(date_text: str) -> int:
    if dry_run:
        return 1
    output_dir.mkdir(parents=True, exist_ok=True)
    pattern = re.compile(rf"^P-{re.escape(date_text)}-([0-9]{{3}})\\.ya?ml$")
    highest = 0
    for path in output_dir.iterdir():
        match = pattern.match(path.name)
        if match:
            highest = max(highest, int(match.group(1)))
    return highest + 1


def proposal_for(capability: dict[str, Any], proposal_id: str, event_id: str, now_text: str) -> dict[str, Any]:
    target_file = str(capability.get("target_file") or ".ai/CAPABILITIES.example.yaml")
    forbidden = target_file in FORBIDDEN_TARGETS
    status = "rejected" if forbidden else "proposed"
    return {
        "proposal_id": proposal_id,
        "schema": "orgos/evolution-proposal/v1",
        "status": status,
        "source_events": [event_id],
        "problem_class": "P1",
        "proposed_change": {
            "target_file": target_file,
            "change_type": "add",
            "description": (
                f"Register new {capability.get('kind')} capability {capability.get('id')} "
                f"from {capability.get('source')} as a proposal-only update."
            ),
            "diff": None,
        },
        "rationale": {
            "summary": str(capability.get("summary") or "New capability appeared in an offline source fixture."),
            "evidence": [
                f"source={capability.get('source')}",
                f"source_url={capability.get('source_url', 'stub://unknown')}",
                f"kind={capability.get('kind')}",
                f"role_hint={capability.get('role_hint', 'unknown')}",
                "real_api_call=false",
            ],
        },
        "estimated_blast_radius": "local",
        "estimated_risk_level": "low",
        "autonomy_recommendation": "ask_before_execute",
        "iron_law_check": {
            "status": "rejected" if forbidden else "passed",
            "checked_at": now_text,
            "forbidden_patterns": sorted(FORBIDDEN_TARGETS),
            "violations": [target_file] if forbidden else [],
            "self_check": "No protected rule weakening detected." if not forbidden else "Protected target rejected.",
        },
        "reviewer_a": {
            "name": "capability-probe-stub",
            "kind": "stub",
            "reviewed_at": now_text,
            "verdict": "reject" if forbidden else "propose",
            "confidence": 0.84,
            "notes": "Provider API calls intentionally skipped for T-OS-327.",
        },
        "reviewer_b": None,
        "agreement": None,
        "escalation_target": None,
        "proposal_trace": [
            {
                "at": now_text,
                "stage": "capability_probe",
                "known_path": str(known_path.relative_to(repo_root) if known_path.is_relative_to(repo_root) else known_path),
                "source": capability.get("source"),
                "capability_id": capability.get("id"),
                "outcome": status,
            }
        ],
    }


now = utc_now()
date_text = now.date().isoformat()
now_text = now.isoformat().replace("+00:00", "Z")
known_ids = load_known_ids(known_path)
source_capabilities = load_source_capabilities(source_fixture)

new_capabilities = [
    capability for capability in source_capabilities
    if str(capability.get("id")) not in known_ids
]
log("info", "probe_completed", known_count=len(known_ids), source_count=len(source_capabilities), new_count=len(new_capabilities))

start = next_index(date_text)
proposals: list[tuple[Path, dict[str, Any]]] = []
for offset, capability in enumerate(new_capabilities, start=0):
    index = start + offset
    proposal_id = f"P-{date_text}-{index:03d}"
    event_id = f"EVO-{date_text}-{index:03d}"
    proposal = proposal_for(capability, proposal_id, event_id, now_text)
    proposals.append((output_dir / f"{proposal_id}.yaml", proposal))

if stdout_enabled:
    for _, proposal in proposals:
        print("---")
        print(yaml.safe_dump(proposal, sort_keys=False, allow_unicode=True))

if not dry_run:
    output_dir.mkdir(parents=True, exist_ok=True)
    for path, proposal in proposals:
        path.write_text(yaml.safe_dump(proposal, sort_keys=False, allow_unicode=True), encoding="utf-8")
        log("info", "proposal_written", path=str(path), proposal_id=proposal["proposal_id"])

print(json.dumps({
    "status": "completed",
    "known_count": len(known_ids),
    "source_count": len(source_capabilities),
    "new_count": len(new_capabilities),
    "proposal_count": len(proposals),
    "output_dir": str(output_dir),
}, ensure_ascii=False))
PY
