#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PROPOSAL_DIR="${PROPOSAL_DIR:-$REPO_ROOT/.ai/_machine/evolution/proposals}"
APPLIED_DIR="${APPLIED_DIR:-$REPO_ROOT/.ai/_machine/evolution/applied}"
CIRCUIT_BREAKER="${CIRCUIT_BREAKER:-$REPO_ROOT/scripts/evolution/circuit-breaker.sh}"

usage() {
  cat <<'EOF'
Usage: bash scripts/evolution/apply.sh <proposal_id|proposal_path> [--stage shadow|canary|progressive|full]

Rollout stages:
  shadow       Record the candidate and structured trace without changing files.
  canary       Apply one proposal, write an application record, and create a 24h monitor marker.
  progressive  Recognized but intentionally blocked in this task.
  full         Recognized but intentionally blocked in this task.

The engine reads fixture proposals only. It does not call an LLM API.
EOF
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

PROPOSAL_REF=""
REQUESTED_STAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)
      REQUESTED_STAGE="${2:-}"
      if [[ -z "$REQUESTED_STAGE" ]]; then
        echo "--stage requires shadow, canary, progressive, or full" >&2
        exit 2
      fi
      shift 2
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

export REPO_ROOT PROPOSAL_DIR APPLIED_DIR PROPOSAL_REF REQUESTED_STAGE CIRCUIT_BREAKER

python3 - <<'PY'
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import yaml

repo_root = Path(os.environ["REPO_ROOT"]).resolve()
proposal_dir = Path(os.environ["PROPOSAL_DIR"])
if not proposal_dir.is_absolute():
    proposal_dir = repo_root / proposal_dir
applied_dir = Path(os.environ["APPLIED_DIR"])
if not applied_dir.is_absolute():
    applied_dir = repo_root / applied_dir
proposal_ref = os.environ["PROPOSAL_REF"]
requested_stage = os.environ.get("REQUESTED_STAGE", "")
circuit_breaker = Path(os.environ["CIRCUIT_BREAKER"])
if not circuit_breaker.is_absolute():
    circuit_breaker = repo_root / circuit_breaker
kernel_files_path = repo_root / ".claude/evals/KERNEL_FILES"

STAGES = {"shadow", "canary", "progressive", "full"}
AUTONOMY_VALUES = {
    "silent_execute",
    "execute_with_report",
    "ask_before_execute",
    "owner_only",
}
FORBIDDEN_TARGETS = {
    "AGENTS.md",
    "CLAUDE.md",
    "manager.md",
    ".claude/agents/manager.md",
    ".claude/rules/acceptance-pre-write.md",
    ".claude/rules/authority-layer.md",
    ".claude/rules/domain-constraint-sync.md",
    ".claude/rules/memory-lifecycle.md",
    ".claude/rules/parallel-session-policy.md",
    ".claude/rules/pre-implementation-risk-profile.md",
    ".claude/rules/project-flow.md",
    ".claude/rules/quality-contract.md",
    ".claude/rules/rationalization-prevention.md",
    ".claude/rules/request-intake-loop.md",
    ".claude/rules/user-journey-sync.md",
}
FORBIDDEN_PREFIXES = {
    ".claude/agents/",
    ".claude/commands/",
    ".claude/hooks/",
    ".env.",
    "secrets/",
}
FORBIDDEN_EXACT = {".env"}
FORBIDDEN_TEXT_RE = re.compile(
    r"\b(disable|bypass|ignore|weaken|remove)\b.*\b(iron law|rationalization|owner approval|protected file)\b",
    re.IGNORECASE,
)


def log(level: str, event: str, **fields: Any) -> None:
    payload = {
        "level": level,
        "trace": "apply",
        "event": event,
        "at": utc_now().isoformat().replace("+00:00", "Z"),
    }
    payload.update(fields)
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))


def fail(kind: str, message: str, recovery: str, exit_code: int = 1) -> None:
    log("error", "failed", error_class=kind, message=message, recovery=recovery)
    raise SystemExit(exit_code)


def utc_now() -> datetime:
    override = os.environ.get("ORGOS_APPLY_NOW")
    if override:
        try:
            return datetime.fromisoformat(override.replace("Z", "+00:00")).astimezone(timezone.utc)
        except ValueError:
            print(
                json.dumps(
                    {
                        "level": "error",
                        "trace": "apply",
                        "event": "failed",
                        "error_class": "invalid_argument",
                        "message": "ORGOS_APPLY_NOW is not ISO8601",
                        "recovery": "Unset it or pass an ISO8601 timestamp.",
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                )
            )
            raise SystemExit(1)
    return datetime.now(timezone.utc).replace(microsecond=0)


def rel_to_repo(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(repo_root).as_posix()
    except ValueError:
        return resolved.as_posix()


def proposal_path() -> Path:
    candidate = Path(proposal_ref)
    if candidate.suffix in {".yaml", ".yml"} or "/" in proposal_ref:
        path = candidate if candidate.is_absolute() else repo_root / candidate
    else:
        path = proposal_dir / f"{proposal_ref}.yaml"
    if not path.exists():
        fail("missing_input", f"proposal not found: {path}", "Run synthesize.sh first or pass a valid path.", 2)
    return path


def load_yaml(path: Path) -> dict[str, Any]:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as exc:
        fail("invalid_input", f"YAML is invalid: {exc}", "Regenerate or repair the proposal.")
    if not isinstance(data, dict):
        fail("invalid_input", "proposal YAML is not an object", "Regenerate the proposal.")
    return data


def load_kernel_files() -> set[str]:
    if not kernel_files_path.exists():
        return set()
    protected: set[str] = set()
    for raw_line in kernel_files_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        protected.add(line)
    return protected


def target_contains_iron_law(target: str, absolute_target: Path) -> bool:
    if not target.startswith(".claude/rules/") or not absolute_target.exists():
        return False
    try:
        text = absolute_target.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return False
    return "Iron Law" in text or "鉄則" in text


def circuit_state_path() -> Path:
    configured = os.environ.get("ORGOS_CIRCUIT_BREAKER_STATE")
    if configured:
        path = Path(configured)
        return path if path.is_absolute() else repo_root / path
    return repo_root / ".ai/_machine/evolution/circuit-breaker.yaml"


def load_circuit_state() -> dict[str, Any]:
    path = circuit_state_path()
    if not path.exists():
        return {}
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError:
        return {}
    return data if isinstance(data, dict) else {}


def run_circuit_breaker(action: str, *args: str) -> None:
    result = subprocess.run(
        ["bash", str(circuit_breaker), action, *args],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode == 0:
        return
    if action == "check":
        fail(
            "circuit_breaker_open",
            "circuit breaker rejected automatic apply",
            "Owner review must restore .ai/_machine/evolution/circuit-breaker.yaml before apply resumes.",
        )
    fail(
        "circuit_breaker_update_failed",
        f"circuit breaker command failed: {action}",
        "Inspect scripts/evolution/circuit-breaker.sh and the state file before retrying.",
    )


def state_path() -> Path:
    return applied_dir / "rollback-state.yaml"


def load_state() -> dict[str, Any]:
    path = state_path()
    if not path.exists():
        return {"consecutive_reverts": 0, "halted": False}
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as exc:
        fail("invalid_state", f"rollback state is invalid: {exc}", "Repair rollback-state.yaml after review.")
    if not isinstance(data, dict):
        return {"consecutive_reverts": 0, "halted": False}
    return data


def enforce_not_halted() -> None:
    state = load_state()
    count = int(state.get("consecutive_reverts") or 0)
    if bool(state.get("halted")) or count >= 3:
        fail(
            "halted_after_reverts",
            f"apply engine stopped after {count} consecutive rollback(s)",
            "Manager/Owner review must reset .ai/_machine/evolution/applied/rollback-state.yaml before applying again.",
        )


def validate_proposal(proposal: dict[str, Any]) -> None:
    for field in ("proposal_id", "proposed_change", "autonomy_recommendation", "iron_law_check"):
        if field not in proposal:
            fail("schema_validation", f"proposal missing required field: {field}", "Validate against evolution-proposal.yaml.")
    if not re.fullmatch(r"P-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}", str(proposal["proposal_id"])):
        fail("schema_validation", "proposal_id has invalid format", "Regenerate the proposal.")
    if not isinstance(proposal.get("proposed_change"), dict):
        fail("schema_validation", "proposed_change must be an object", "Regenerate the proposal.")
    if str(proposal.get("autonomy_recommendation")) not in AUTONOMY_VALUES:
        fail("schema_validation", "autonomy_recommendation is invalid", "Regenerate the proposal.")


def target_path(proposal: dict[str, Any]) -> tuple[str, Path]:
    target = str(proposal["proposed_change"].get("target_file") or "").strip()
    if not target:
        fail("schema_validation", "proposed_change.target_file is required", "Regenerate the proposal.")
    candidate = Path(target)
    if candidate.is_absolute():
        fail("path_violation", f"absolute target_file is not allowed: {target}", "Use a repository-relative target path.")
    resolved = (repo_root / candidate).resolve()
    try:
        normalized = resolved.relative_to(repo_root).as_posix()
    except ValueError:
        fail("path_violation", f"target escapes repository: {target}", "Use a repository-relative target path.")
    return normalized, resolved


def iron_law_check(proposal: dict[str, Any], target: str, absolute_target: Path) -> dict[str, Any]:
    iron = proposal.get("iron_law_check") if isinstance(proposal.get("iron_law_check"), dict) else {}
    kernel_targets = load_kernel_files()
    protected_targets = FORBIDDEN_TARGETS | kernel_targets
    violations: list[str] = []
    if target in protected_targets or target in FORBIDDEN_EXACT:
        violations.append(f"target_file is protected by Iron Law: {target}")
    if target in kernel_targets:
        violations.append(f"target_file is listed in KERNEL_FILES: {target}")
    for prefix in sorted(FORBIDDEN_PREFIXES):
        if target.startswith(prefix):
            violations.append(f"target_file is protected by Iron Law prefix: {prefix}")
    if target_contains_iron_law(target, absolute_target):
        violations.append(f"target_file contains Iron Law text and is blocked from automatic apply: {target}")
    if iron.get("status") == "rejected":
        for item in iron.get("violations") or []:
            violations.append(str(item))
    change = proposal.get("proposed_change") if isinstance(proposal.get("proposed_change"), dict) else {}
    haystack = "\n".join(str(change.get(key) or "") for key in ("description", "diff"))
    if FORBIDDEN_TEXT_RE.search(haystack):
        violations.append("change text appears to weaken Iron Law or Owner approval")
    if violations:
        fail(
            "iron_law_rejected",
            "; ".join(dict.fromkeys(violations)),
            "Create an Owner-only proposal outside the automatic apply engine.",
        )
    return {
        "status": "passed",
        "checked_at": utc_now().isoformat().replace("+00:00", "Z"),
        "forbidden_targets": sorted(protected_targets),
        "violations": [],
    }


def iteration_counter_snapshot() -> dict[str, Any]:
    data = load_circuit_state()
    limits = data.get("limits") if isinstance(data.get("limits"), dict) else {}
    state = data.get("state") if isinstance(data.get("state"), dict) else {}
    return {
        "current_cycle_apply_count": int(state.get("current_cycle_apply_count") or 0),
        "max_apply_per_cycle": int(limits.get("max_apply_per_cycle") or 3),
        "today_apply_count": int(state.get("today_apply_count") or 0),
        "max_apply_per_day": int(limits.get("max_apply_per_day") or 10),
        "consecutive_revert_count": int(state.get("consecutive_revert_count") or 0),
        "consecutive_revert_threshold": int(limits.get("consecutive_revert_threshold") or 3),
        "breaker_state": str(state.get("breaker_state") or "closed"),
        "tripped_at": state.get("tripped_at"),
        "trip_reason": state.get("trip_reason"),
    }


def stage_for_autonomy(autonomy: str) -> str:
    if requested_stage:
        if requested_stage not in STAGES:
            fail("invalid_argument", f"unknown rollout stage: {requested_stage}", "Choose shadow, canary, progressive, or full.", 2)
        return requested_stage
    if autonomy == "silent_execute":
        return "shadow"
    if autonomy in {"execute_with_report", "ask_before_execute"}:
        return "canary"
    return "shadow"


def sha256_path(path: Path, exists: bool) -> str:
    if not exists:
        return hashlib.sha256(b"").hexdigest()
    return hashlib.sha256(path.read_bytes()).hexdigest()


def next_id(prefix: str) -> str:
    applied_dir.mkdir(parents=True, exist_ok=True)
    today = utc_now().date().isoformat()
    regex = re.compile(rf"^{re.escape(prefix)}-{today}-([0-9]{{3}})\.yaml$")
    max_seen = 0
    for path in applied_dir.glob(f"{prefix}-{today}-*.yaml"):
        match = regex.fullmatch(path.name)
        if match:
            max_seen = max(max_seen, int(match.group(1)))
    return f"{prefix}-{today}-{max_seen + 1:03d}"


def eval_result(stage: str, target: str, checksum: str) -> dict[str, Any]:
    return {
        "status": "passed",
        "stage": stage,
        "target_file": target,
        "checksum": checksum,
        "checked_at": utc_now().isoformat().replace("+00:00", "Z"),
    }


def write_yaml(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True), encoding="utf-8")


def apply_patch(diff: str) -> None:
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as handle:
        handle.write(diff)
        patch_path = Path(handle.name)
    try:
        check = subprocess.run(
            ["git", "apply", "--check", str(patch_path)],
            cwd=repo_root,
            text=True,
            capture_output=True,
            check=False,
        )
        if check.returncode != 0:
            fail(
                "patch_check_failed",
                check.stderr.strip() or check.stdout.strip() or "git apply --check failed",
                "Regenerate the proposal with an applicable unified diff.",
            )
        applied = subprocess.run(
            ["git", "apply", str(patch_path)],
            cwd=repo_root,
            text=True,
            capture_output=True,
            check=False,
        )
        if applied.returncode != 0:
            fail(
                "patch_apply_failed",
                applied.stderr.strip() or applied.stdout.strip() or "git apply failed",
                "Rollback is not needed because git apply did not complete.",
            )
    finally:
        patch_path.unlink(missing_ok=True)


def validate_diff_targets(diff: str, target: str) -> None:
    touched: set[str] = set()
    for raw_line in diff.splitlines():
        if raw_line.startswith(("--- ", "+++ ")):
            value = raw_line[4:].strip().split("\t", 1)[0]
            if value == "/dev/null":
                continue
            if value.startswith("a/") or value.startswith("b/"):
                value = value[2:]
            if value:
                touched.add(value)
    if not touched:
        fail("invalid_diff", "unified diff does not declare changed files", "Regenerate the proposal with standard ---/+++ headers.")
    if touched != {target}:
        fail(
            "target_mismatch",
            f"diff touches {sorted(touched)} but proposal target_file is {target}",
            "Regenerate the proposal so diff headers match proposed_change.target_file.",
        )


def write_canary_marker(record_id: str, proposal_id: str, target: str) -> str:
    due_at = (utc_now() + timedelta(hours=24)).isoformat().replace("+00:00", "Z")
    marker_path = applied_dir / f"{record_id}.canary-monitor.yaml"
    write_yaml(
        marker_path,
        {
            "record_id": record_id,
            "proposal_ref": proposal_id,
            "target_file": target,
            "rollout_stage": "canary",
            "status": "pending_24h_monitor",
            "created_at": utc_now().isoformat().replace("+00:00", "Z"),
            "due_at": due_at,
            "scheduled_job_scope": "out_of_scope_for_T-OS-326",
        },
    )
    return rel_to_repo(marker_path)


def main() -> None:
    run_circuit_breaker("check")
    enforce_not_halted()
    path = proposal_path()
    proposal = load_yaml(path)
    validate_proposal(proposal)

    proposal_id = str(proposal["proposal_id"])
    autonomy = str(proposal["autonomy_recommendation"])
    stage = stage_for_autonomy(autonomy)
    target, absolute_target = target_path(proposal)

    log("info", "preflight_started", proposal_ref=proposal_id, rollout_stage=stage, target_file=target)
    iron_result = iron_law_check(proposal, target, absolute_target)

    if str(proposal.get("status") or "proposed") == "rejected":
        fail("proposal_rejected", "rejected proposals are never auto-applied", "Regenerate or re-review the proposal first.")
    if autonomy == "owner_only":
        fail("approval_required", "owner_only proposals are never auto-applied", "Owner must apply manually outside this engine.")
    if stage in {"progressive", "full"}:
        fail(
            "stage_out_of_scope",
            f"{stage} rollout is recognized but not implemented in T-OS-326",
            "Use --stage shadow or --stage canary for this task.",
        )

    diff = proposal["proposed_change"].get("diff")
    before_exists = absolute_target.exists()
    before_checksum = sha256_path(absolute_target, before_exists)
    pre_eval = eval_result("pre", target, before_checksum)
    record_id = next_id("AR")

    if stage == "canary":
        if not isinstance(diff, str) or not diff.strip():
            fail("missing_diff", "canary apply requires proposed_change.diff", "Regenerate the proposal with a unified diff.")
        validate_diff_targets(diff, target)

    backup_path = applied_dir / f"{record_id}.before"
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    if before_exists:
        shutil.copyfile(absolute_target, backup_path)
    else:
        backup_path.write_bytes(b"")

    if stage == "shadow":
        after_checksum = before_checksum
        post_eval = eval_result("post_shadow", target, after_checksum)
        log("info", "shadow_recorded", proposal_ref=proposal_id, record_id=record_id, target_file=target)
    else:
        assert isinstance(diff, str)
        apply_patch(diff)
        after_checksum = sha256_path(absolute_target, absolute_target.exists())
        if after_checksum == before_checksum:
            fail("no_effect", "canary diff applied but target checksum did not change", "Inspect the diff and target file.")
        post_eval = eval_result("post", target, after_checksum)
        log("info", "canary_applied", proposal_ref=proposal_id, record_id=record_id, target_file=target)

    marker_ref = None
    if stage == "canary":
        marker_ref = write_canary_marker(record_id, proposal_id, target)

    run_circuit_breaker("increment-apply")
    iteration_counter = iteration_counter_snapshot()

    record = {
        "record_id": record_id,
        "schema": "orgos/application-record/v1",
        "proposal_ref": proposal_id,
        "target_file": target,
        "before_checksum": before_checksum,
        "after_checksum": after_checksum,
        "before_exists": before_exists,
        "backup_ref": rel_to_repo(backup_path),
        "rollout_stage": stage,
        "autonomy_level_at_apply": autonomy,
        "applied_at": utc_now().isoformat().replace("+00:00", "Z"),
        "applied_by": "system",
        "eval_results": {"pre": pre_eval, "post": post_eval},
        "rollback_ref": None,
        "iron_law_check": iron_result,
        "canary_monitor_ref": marker_ref,
        "iteration_counter": iteration_counter,
        "apply_trace": [
            {
                "at": utc_now().isoformat().replace("+00:00", "Z"),
                "event": "record_created",
                "stage": stage,
                "file_changed": stage == "canary",
                "iteration_counter": iteration_counter,
            }
        ],
    }
    record_path = applied_dir / f"{record_id}.yaml"
    write_yaml(record_path, record)
    log(
        "info",
        "completed",
        proposal_ref=proposal_id,
        record_id=record_id,
        record_path=rel_to_repo(record_path),
        rollout_stage=stage,
    )


main()
PY
