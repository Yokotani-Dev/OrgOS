#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SCHEMA_PATH="${SCHEMA_PATH:-$REPO_ROOT/.claude/schemas/capability-roles.yaml}"
ROLE_ID=""
JSON_OUTPUT=0

usage() {
  cat <<'EOF'
Usage: bash scripts/capabilities/role-routing.sh <role_id> [--json]

Returns a proposal-only routing recommendation for a capability role.
Model names are not resolved here; output uses semver-style aliases.

Options:
  --schema <path>  Read a custom capability-roles schema.
  --json           Emit JSON instead of text.
  -h, --help       Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --schema)
      SCHEMA_PATH="${2:-}"
      if [[ -z "$SCHEMA_PATH" ]]; then
        echo "--schema requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --json)
      JSON_OUTPUT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$ROLE_ID" ]]; then
        echo "Only one role_id is accepted" >&2
        usage >&2
        exit 2
      fi
      ROLE_ID="$1"
      shift
      ;;
  esac
done

if [[ -z "$ROLE_ID" ]]; then
  usage >&2
  exit 2
fi

export REPO_ROOT SCHEMA_PATH ROLE_ID JSON_OUTPUT

python3 - <<'PY'
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
schema_path = Path(os.environ["SCHEMA_PATH"])
if not schema_path.is_absolute():
    schema_path = repo_root / schema_path
role_id = os.environ["ROLE_ID"]
json_output = os.environ["JSON_OUTPUT"] == "1"


def log(level: str, event: str, **fields: Any) -> None:
    payload = {
        "level": level,
        "event": event,
        "component": "capability-role-routing",
        "role_id": role_id,
        **fields,
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), file=sys.stderr)


def load_schema(path: Path) -> dict[str, Any]:
    if not path.exists():
        log("error", "schema_missing", path=str(path))
        raise SystemExit(1)
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception as exc:  # noqa: BLE001 - CLI boundary with structured log.
        log("error", "schema_read_failed", path=str(path), error=str(exc))
        raise SystemExit(1)
    if not isinstance(data, dict):
        log("error", "schema_invalid_type", path=str(path))
        raise SystemExit(1)
    return data


def score(alias: str, characteristics: dict[str, Any], requirements: dict[str, Any]) -> tuple[float, list[str]]:
    reasons: list[str] = []
    total = 0.0
    checks = 0

    def numeric(name: str, default: float = 0.0) -> float:
        value = characteristics.get(name, default)
        return float(value) if isinstance(value, (int, float)) else default

    context = numeric("context_window_tokens")
    context_min = float(requirements.get("context_window_tokens_min", 1))
    total += min(context / context_min, 1.0)
    checks += 1
    reasons.append(f"context_window_tokens={int(context)} >= {int(context_min)}")

    reasoning = numeric("reasoning_quality")
    reasoning_min = float(requirements.get("reasoning_quality_min", 0))
    total += min(reasoning / reasoning_min, 1.0) if reasoning_min > 0 else 1.0
    checks += 1
    reasons.append(f"reasoning_quality={reasoning:.2f} >= {reasoning_min:.2f}")

    latency = numeric("latency_seconds", 999.0)
    latency_max = float(requirements.get("latency_seconds_max", 999))
    total += min(latency_max / latency, 1.25) if latency > 0 else 0.0
    checks += 1
    reasons.append(f"latency_seconds={latency:.2f} <= {latency_max:.2f}")

    for req_key, char_key in (
        ("tool_use_quality_min", "tool_use_quality"),
        ("code_quality_min", "code_quality"),
    ):
        if req_key not in requirements:
            continue
        actual = numeric(char_key)
        required = float(requirements[req_key])
        total += min(actual / required, 1.0) if required > 0 else 1.0
        checks += 1
        reasons.append(f"{char_key}={actual:.2f} >= {required:.2f}")

    return (total / max(checks, 1), reasons)


schema = load_schema(schema_path)
instance = schema.get("x-orgos-default-instance")
if not isinstance(instance, dict):
    log("error", "default_instance_missing", path=str(schema_path))
    raise SystemExit(1)

aliases = instance.get("model_aliases")
roles = instance.get("roles")
if not isinstance(aliases, dict) or not isinstance(roles, list):
    log("error", "default_instance_invalid", path=str(schema_path))
    raise SystemExit(1)

role = next((row for row in roles if isinstance(row, dict) and row.get("role_id") == role_id), None)
if role is None:
    log("error", "role_not_found", available=[row.get("role_id") for row in roles if isinstance(row, dict)])
    raise SystemExit(1)

requirements = role.get("required_characteristics") if isinstance(role.get("required_characteristics"), dict) else {}
candidate_scores: list[dict[str, Any]] = []
for candidate in role.get("candidate_models", []):
    alias = str(candidate)
    entry = aliases.get(alias)
    if not isinstance(entry, dict):
        candidate_scores.append({"alias": alias, "eligible": False, "score": 0.0, "reasons": ["alias missing from catalog"]})
        continue
    characteristics = entry.get("characteristics") if isinstance(entry.get("characteristics"), dict) else {}
    model_score, reasons = score(alias, characteristics, requirements)
    candidate_scores.append({"alias": alias, "eligible": True, "score": round(model_score, 4), "reasons": reasons})

eligible = [row for row in candidate_scores if row["eligible"]]
if not eligible:
    log("error", "no_eligible_candidate")
    raise SystemExit(1)

recommended = max(eligible, key=lambda row: row["score"])
payload = {
    "role_id": role_id,
    "recommended_model_alias": recommended["alias"],
    "reason": recommended["reasons"],
    "fallback_chain": role.get("fallback_chain", []),
    "candidate_scores": candidate_scores,
    "regression_test_ref": role.get("regression_test_ref"),
    "semantic_equivalence_test": {
        "status": "placeholder",
        "ref": role.get("semantic_equivalence_test_ref", f"manual://semantic-equivalence/{role_id}"),
        "note": "Manual trigger only; automatic regression execution is out of scope for T-OS-327.",
    },
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
}

log("info", "routing_recommendation", recommended_model_alias=recommended["alias"])
if json_output:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
else:
    print(f"role_id: {payload['role_id']}")
    print(f"recommended_model_alias: {payload['recommended_model_alias']}")
    print("reason:")
    for item in payload["reason"]:
        print(f"  - {item}")
    print("fallback_chain:")
    for item in payload["fallback_chain"]:
        print(f"  - {item}")
    print(f"regression_test_ref: {payload['regression_test_ref']}")
    print(f"semantic_equivalence_test: {payload['semantic_equivalence_test']['status']} ({payload['semantic_equivalence_test']['ref']})")
PY
