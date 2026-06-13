#!/usr/bin/env python3
"""PreToolUse hook adapter for OrgOS policy evaluation."""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).parent))
import policy_core


DEFAULT_KERNEL_MODE = "warn"
KERNEL_MODES = {"warn", "enforce", "disabled"}
ORGOS_KERNEL_MODE_FILE = ".claude/state/kernel-mode.json"
ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd()))


def valid_kernel_mode(value: object, default: str = DEFAULT_KERNEL_MODE) -> str:
    mode = str(value or "").strip()
    return mode if mode in KERNEL_MODES else default


def load_mode_config() -> dict:
    """Read .claude/state/kernel-mode.json, normalizing v1 and v2 schemas."""
    override = os.environ.get("ORGOS_KERNEL_MODE_OVERRIDE", "").strip()
    if override in KERNEL_MODES:
        return {"schema_version": "orgos.kernel-mode.override", "default": override, "invariants": {}}

    try:
        with (ROOT / ORGOS_KERNEL_MODE_FILE).open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {"schema_version": "orgos.kernel-mode.v2", "default": DEFAULT_KERNEL_MODE, "invariants": {}}

    if not isinstance(payload, dict):
        return {"schema_version": "orgos.kernel-mode.v2", "default": DEFAULT_KERNEL_MODE, "invariants": {}}

    schema_version = str(payload.get("schema_version", "") or "").strip()
    if schema_version in ("", "orgos.kernel-mode.v1", "v1"):
        return {
            "schema_version": "orgos.kernel-mode.v1",
            "default": valid_kernel_mode(payload.get("mode")),
            "invariants": {},
        }

    invariants = payload.get("invariants", {})
    if not isinstance(invariants, dict):
        invariants = {}
    return {
        "schema_version": schema_version,
        "default": valid_kernel_mode(payload.get("default")),
        "invariants": {
            str(invariant_id): valid_kernel_mode(mode)
            for invariant_id, mode in invariants.items()
            if valid_kernel_mode(mode, "") in KERNEL_MODES
        },
    }


def resolve_policy_root(cwd: str = "") -> Path:
    candidate = Path(cwd).expanduser() if cwd else ROOT
    if not candidate.is_absolute():
        candidate = ROOT / candidate
    candidate = candidate.resolve(strict=False)
    if candidate.is_file():
        candidate = candidate.parent

    for path in (candidate, *candidate.parents):
        if (path / ".ai").is_dir() or (path / ".git").exists():
            return path
    return ROOT


def parse_lease_time(value: str) -> Optional[datetime]:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def is_expired(lease: dict) -> bool:
    expires_at = parse_lease_time(str(lease.get("expires_at", "") or ""))
    return expires_at is not None and expires_at <= datetime.now(timezone.utc)


def load_active_leases(cwd: str) -> list[dict]:
    """Read leases/*.json from cwd. Returns active, non-expired leases.

    Layout compat (T-OS-497): prefer the new .ai/_machine/leases layout; fall
    back to the legacy .ai/leases dir when _machine is absent (belt-and-
    suspenders before migrate-layout.sh has run). Inlined two-path lookup
    keeps this kernel hook free of cross-module imports.
    """
    ai_dir = resolve_policy_root(cwd) / ".ai"
    leases_dir = ai_dir / "_machine" / "leases"
    if not leases_dir.is_dir():
        legacy_dir = ai_dir / "leases"
        leases_dir = legacy_dir if legacy_dir.is_dir() else leases_dir
    if not leases_dir.is_dir():
        return []

    result: list[dict] = []
    for path in leases_dir.glob("*.json"):
        try:
            with path.open("r", encoding="utf-8") as handle:
                lease = json.load(handle)
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(lease, dict) and lease.get("status") == "active" and not is_expired(lease):
            result.append(lease)
    return result


def get_actor_role(tool_input: dict) -> str:
    """Infer actor role from hook input or explicit test fixture fields."""
    actor = tool_input.get("actor")
    if isinstance(actor, dict) and actor.get("role"):
        return str(actor["role"])
    for key in ("actor_role", "expected_actor", "role"):
        value = str(tool_input.get(key, "") or "").strip()
        if value:
            return value
    return os.environ.get("ORGOS_ACTOR_ROLE", "unknown")


def extract_context(data: dict) -> tuple[str, str, str, str, str]:
    """Return tool, command, path, cwd, actor_role for fixture or PreToolUse JSON."""
    if "tool_input" in data or "tool_name" in data:
        tool = str(data.get("tool_name", "") or "")
        tool_input = data.get("tool_input", {}) or {}
        command = str(tool_input.get("command", "") or "")
        raw_path = str(tool_input.get("path", "") or tool_input.get("file_path", "") or "")
        cwd = str(tool_input.get("cwd", data.get("cwd", "")) or "")
        return tool, command, normalize_repo_path(raw_path), cwd, get_actor_role({**data, **tool_input})

    tool = str(data.get("tool", "") or "")
    command = str(data.get("command", "") or "")
    path = str(data.get("path", "") or "")
    cwd = str(data.get("cwd", "") or "")
    return tool, command, path, cwd, get_actor_role(data)


def normalize_repo_path(raw_path: str) -> str:
    path = raw_path.strip()
    if not path:
        return ""

    candidate = Path(path).expanduser()
    if candidate.is_absolute():
        try:
            return candidate.resolve(strict=False).relative_to(ROOT.resolve()).as_posix()
        except ValueError:
            return candidate.resolve(strict=False).as_posix()

    posix_path = Path(path).as_posix()
    while posix_path.startswith("./"):
        posix_path = posix_path[2:]
    return posix_path


def load_input() -> tuple[dict, bool]:
    if "--test-fixture" in sys.argv:
        idx = sys.argv.index("--test-fixture")
        try:
            fixture_path = sys.argv[idx + 1]
        except IndexError:
            print("Usage: pretool_policy.py [--test-fixture FIXTURE.json]", file=sys.stderr)
            sys.exit(2)
        with open(fixture_path, "r", encoding="utf-8") as handle:
            return json.load(handle), True

    if len(sys.argv) != 1:
        print("Usage: pretool_policy.py [--test-fixture FIXTURE.json]", file=sys.stderr)
        sys.exit(2)
    return json.load(sys.stdin), False


def allow_json(reason: str) -> None:
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": reason,
        }
    }
    print(json.dumps(out))


def emit_decision(decision: policy_core.Decision, fixture_mode: bool) -> int:
    if decision.outcome == "allow":
        if not fixture_mode:
            allow_json("allowed by OrgOS policy")
        return 0

    marker = "ORGOS_POLICY_WARN" if decision.outcome == "warn" else "ORGOS_POLICY_DENY"
    print(f"{marker}: {decision.invariant_id}: {decision.reason}", file=sys.stderr)
    if decision.outcome == "warn":
        print("  (kernel mode=warn; would be blocked in enforce mode)", file=sys.stderr)
        if not fixture_mode:
            allow_json("constitutional invariant warning emitted")
        return 0
    return 2


def main() -> int:
    data, fixture_mode = load_input()
    tool, command, path, cwd, actor_role = extract_context(data)
    root_hint = cwd or str(ROOT)
    decision = policy_core.evaluate(
        tool=tool,
        command=command,
        path=path,
        cwd=root_hint,
        actor_role=actor_role,
        active_leases=load_active_leases(root_hint),
        mode_config=load_mode_config(),
    )
    return emit_decision(decision, fixture_mode)


if __name__ == "__main__":
    sys.exit(main())
