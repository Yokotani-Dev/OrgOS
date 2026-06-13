#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PROPOSAL_DIR="${PROPOSAL_DIR:-$REPO_ROOT/.ai/_machine/evolution/proposals}"
ADD_DECISION="${ADD_DECISION:-$REPO_ROOT/scripts/inbox/add-decision.sh}"

usage() {
  cat <<'EOF'
Usage: bash scripts/evolution/peer-review.sh <proposal_id|proposal_path> [--fixture auto|agree|disagree]

Options:
  --fixture <mode>           Stub reviewer mode. Default: auto.
  --skip-inbox               Do not call add-decision.sh on disagreement; for isolated smoke tests.
  -h, --help                 Show this help.

This task intentionally uses a fixture reviewer. It does not call an LLM API.
EOF
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

PROPOSAL_REF=""
FIXTURE_MODE="${ORGOS_PEER_REVIEW_FIXTURE:-auto}"
SKIP_INBOX="${ORGOS_SYNTHESIS_SKIP_INBOX:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fixture)
      FIXTURE_MODE="${2:-}"
      if [[ -z "$FIXTURE_MODE" ]]; then
        echo "--fixture requires auto, agree, or disagree" >&2
        exit 2
      fi
      shift 2
      ;;
    --skip-inbox)
      SKIP_INBOX=1
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
      if [[ -n "$PROPOSAL_REF" ]]; then
        echo "Only one proposal id/path may be provided" >&2
        exit 2
      fi
      PROPOSAL_REF="$1"
      shift
      ;;
  esac
done

if [[ -z "$PROPOSAL_REF" ]]; then
  echo "proposal_id or proposal_path is required" >&2
  exit 2
fi

export REPO_ROOT PROPOSAL_DIR ADD_DECISION PROPOSAL_REF FIXTURE_MODE SKIP_INBOX

python3 - <<'PY'
from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
proposal_dir = Path(os.environ["PROPOSAL_DIR"])
if not proposal_dir.is_absolute():
    proposal_dir = repo_root / proposal_dir
add_decision = Path(os.environ["ADD_DECISION"])
if not add_decision.is_absolute():
    add_decision = repo_root / add_decision
proposal_ref = os.environ["PROPOSAL_REF"]
fixture_mode = os.environ["FIXTURE_MODE"]
skip_inbox = os.environ["SKIP_INBOX"] == "1"


def fail(kind: str, message: str, recovery: str) -> None:
    print(
        json.dumps(
            {
                "level": "error",
                "trace": "review",
                "error_class": kind,
                "message": message,
                "recovery": recovery,
            },
            ensure_ascii=False,
        ),
        file=sys.stderr,
    )
    raise SystemExit(1)


def utc_now() -> datetime:
    override = os.environ.get("ORGOS_REVIEW_NOW")
    if override:
        try:
            return datetime.fromisoformat(override.replace("Z", "+00:00")).astimezone(timezone.utc)
        except ValueError:
            fail("invalid_argument", "ORGOS_REVIEW_NOW is not ISO8601", "Unset it or pass an ISO8601 timestamp.")
    return datetime.now(timezone.utc).replace(microsecond=0)


def proposal_path() -> Path:
    candidate = Path(proposal_ref)
    if candidate.suffix in {".yaml", ".yml"} or "/" in proposal_ref:
        path = candidate if candidate.is_absolute() else repo_root / candidate
    else:
        path = proposal_dir / f"{proposal_ref}.yaml"
    if not path.exists():
        fail("missing_input", f"proposal not found: {path}", "Run synthesize.sh first or pass a valid path.")
    return path


def load_proposal(path: Path) -> dict[str, Any]:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as exc:
        fail("invalid_input", f"proposal YAML is invalid: {exc}", "Regenerate or repair the proposal.")
    if not isinstance(data, dict):
        fail("invalid_input", "proposal YAML is not an object", "Regenerate the proposal.")
    return data


def validate_for_review(proposal: dict[str, Any]) -> None:
    for field in ("proposal_id", "proposed_change", "iron_law_check", "reviewer_a"):
        if field not in proposal:
            fail("schema_validation", f"proposal missing required field: {field}", "Validate against evolution-proposal.yaml.")
    if not isinstance(proposal.get("proposed_change"), dict):
        fail("schema_validation", "proposed_change must be an object", "Regenerate the proposal.")


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(repo_root))
    except ValueError:
        return str(path)


def auto_agreement(proposal: dict[str, Any]) -> tuple[str, str]:
    iron = proposal.get("iron_law_check") if isinstance(proposal.get("iron_law_check"), dict) else {}
    risk = str(proposal.get("estimated_risk_level") or "medium")
    status = str(proposal.get("status") or "proposed")
    if status == "rejected" or iron.get("status") == "rejected":
        return ("agree", "Reviewer B agrees with Reviewer A rejection; no owner escalation needed.")
    if risk in {"critical", "high"}:
        return ("disagree", "Reviewer B requires owner decision for high-risk synthesis output.")
    return ("agree", "Reviewer B agrees this proposal can proceed as an apply candidate.")


def decision_options() -> str:
    return json.dumps(
        [
            {
                "key": "A",
                "label": "APPROVE",
                "consequence": "Treat this proposal as eligible for the later apply workflow.",
            },
            {
                "key": "B",
                "label": "DEFER",
                "consequence": "Keep the proposal but do not proceed until more context is available.",
            },
            {
                "key": "C",
                "label": "REJECT",
                "consequence": "Close the proposal and do not apply it.",
            },
        ],
        ensure_ascii=False,
        separators=(",", ":"),
    )


def add_owner_decision(proposal: dict[str, Any], reason: str) -> str | None:
    if skip_inbox:
        return None
    if not add_decision.exists():
        fail("missing_integration", f"add-decision.sh not found: {add_decision}", "Restore scripts/inbox/add-decision.sh.")
    deadline = (now + timedelta(days=1)).astimezone().isoformat(timespec="seconds")
    target = proposal.get("proposed_change", {}).get("target_file", "UNKNOWN")
    decision = f"Resolve peer-review disagreement for {proposal['proposal_id']} targeting {target}"
    cmd = [
        "bash",
        str(add_decision),
        "--type",
        "type_a_direction",
        "--decision",
        decision,
        "--recommendation",
        "B",
        "--recommendation-reason",
        reason,
        "--risk",
        "high" if proposal.get("estimated_risk_level") in {"high", "critical"} else "medium",
        "--options",
        decision_options(),
        "--default-if-no-response",
        "escalate",
        "--deadline",
        deadline,
    ]
    try:
        result = subprocess.run(cmd, cwd=repo_root, check=True, text=True, capture_output=True)
    except subprocess.CalledProcessError as exc:
        fail(
            "integration_failed",
            f"add-decision.sh failed: {exc.stderr.strip() or exc.stdout.strip()}",
            "Fix OWNER_INBOX schema/sections and rerun peer review.",
        )
    decision_id = result.stdout.strip().splitlines()[-1] if result.stdout.strip() else ""
    return decision_id or None


if fixture_mode not in {"auto", "agree", "disagree"}:
    fail("invalid_argument", f"--fixture is invalid: {fixture_mode}", "Choose auto, agree, or disagree.")

now = utc_now()
path = proposal_path()
proposal = load_proposal(path)
validate_for_review(proposal)

if fixture_mode == "agree":
    agreement, reason = ("agree", "Reviewer B fixture forced agreement.")
elif fixture_mode == "disagree":
    agreement, reason = ("disagree", "Reviewer B fixture forced disagreement for escalation smoke coverage.")
else:
    agreement, reason = auto_agreement(proposal)

decision_id = add_owner_decision(proposal, reason) if agreement == "disagree" else None
proposal["reviewer_b"] = {
    "name": "fixture-reviewer-b",
    "kind": "stub",
    "reviewed_at": now.isoformat().replace("+00:00", "Z"),
    "verdict": agreement,
    "confidence": 0.82 if agreement == "agree" else 0.74,
    "notes": reason,
}
proposal["agreement"] = agreement
proposal["escalation_target"] = decision_id
review_trace = proposal.get("review_trace")
if not isinstance(review_trace, list):
    review_trace = []
review_trace.append(
    {
        "at": now.isoformat().replace("+00:00", "Z"),
        "stage": "peer_review",
        "reviewer": "fixture-reviewer-b",
        "fixture_mode": fixture_mode,
        "outcome": agreement,
        "escalation_target": decision_id,
        "inbox_call": agreement == "disagree" and not skip_inbox,
    }
)
proposal["review_trace"] = review_trace
path.write_text(yaml.safe_dump(proposal, allow_unicode=True, sort_keys=False, width=1000), encoding="utf-8")

print(
    json.dumps(
        {
            "level": "info",
            "trace": "review",
            "proposal_id": proposal["proposal_id"],
            "agreement": agreement,
            "escalation_target": decision_id,
            "path": display_path(path),
        },
        ensure_ascii=False,
    ),
    file=sys.stderr,
)
print(proposal["proposal_id"])
PY
