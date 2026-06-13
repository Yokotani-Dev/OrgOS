"""Pure policy evaluation for OrgOS kernel invariants.

Inputs: action context (tool, command, path, cwd, actor, lease state, mode config).
Outputs: Decision(allow|deny|warn, invariant_id, reason).

Plan contract checks may inspect .ai/_machine/plans relative to cwd. Callers can
provide plan_contracts in mode_config to keep tests pure.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from fnmatch import fnmatch
from pathlib import Path
from typing import Optional
import re
import shlex


KERNEL_MODES = {"warn", "enforce", "disabled"}
PROTECTED_BRANCHES = {"main", "master", "develop"}
WRITE_TOOLS = {"Edit", "Write", "MultiEdit"}
GENERATED_FILE_PATTERNS = [
    r".*\.generated\.(md|yaml|json)$",
    r"\.ai/DASHBOARD\.generated\.md$",
    r"\.ai/TASKS\.generated\.yaml$",
    r"\.ai/DECISIONS\.generated\.md$",
    r"\.ai/GLOSSARY\.generated\.md$",
]
PROTECTED_STATE_FILES = {
    ".ai/TASKS.yaml",
    ".ai/DASHBOARD.md",
    ".ai/STATUS.md",
    ".ai/CONTROL.yaml",
    ".ai/OWNER_INBOX.md",
    ".ai/OWNER_COMMENTS.md",
    ".ai/DECISIONS.md",
    ".ai/RISKS.md",
    ".ai/RUN_LOG.md",
    ".ai/EVENTS.jsonl",
}


class InvariantId(str, Enum):
    IntegratorOnlyCommit = "IntegratorOnlyCommit"
    PerTaskWorktree = "PerTaskWorktree"
    ProtectedBranchNoTouch = "ProtectedBranchNoTouch"
    LeaseBeforeWrite = "LeaseBeforeWrite"
    StateMutationViaOrgTool = "StateMutationViaOrgTool"
    DurableArtifactBeforeCleanup = "DurableArtifactBeforeCleanup"
    OwnerApprovalForIrreversibleOps = "OwnerApprovalForIrreversibleOps"
    PlanContractRequired = "PlanContractRequired"
    DangerousShell = "DangerousShell"
    KernelFileNoTouch = "KernelFileNoTouch"
    KernelSelfModification = "KernelSelfModification"
    IntegratorIsScriptNotAgent = "IntegratorIsScriptNotAgent"


@dataclass(frozen=True)
class Decision:
    outcome: str  # "allow" | "warn" | "deny"
    invariant_id: Optional[str] = None
    reason: Optional[str] = None


@dataclass(frozen=True)
class GitCommand:
    subcmd: str
    args: list[str]
    raw_command: str


def parse_git_command(command: str) -> Optional[GitCommand]:
    """Parse the first executable git command from a shell command string."""
    for segment in _shell_command_segments(command):
        git = _parse_git_segment(segment, command)
        if git is not None:
            return git
    return None


def is_protected_state_file(path: str) -> bool:
    """Pure check against protected state file patterns."""
    repo_path = normalize_policy_path(path)
    return _matches_repo_path(repo_path, PROTECTED_STATE_FILES)


def is_generated_file(path: str) -> bool:
    """Pure check against generated file path patterns."""
    repo_path = normalize_policy_path(path)
    return any(re.search(pattern, repo_path) for pattern in GENERATED_FILE_PATTERNS)


def is_kernel_file(path: str) -> bool:
    repo_path = normalize_policy_path(path)
    return (
        _matches_repo_path(repo_path, {"AGENTS.md", "CLAUDE.md"})
        or repo_path.startswith(".claude/")
        or "/.claude/" in repo_path
        or repo_path.startswith(".ai/_machine/codex/ORDERS/")
        or "/.ai/_machine/codex/ORDERS/" in repo_path
    )


def path_covers(allowed_path: str, target_path: str) -> bool:
    """Return true when allowed_path exactly, prefix, or glob-covers target_path."""
    scope = normalize_policy_path(allowed_path)
    target = normalize_policy_path(target_path)
    if not scope:
        return True
    if _has_glob(scope):
        return fnmatch(target, scope)
    scope = scope.rstrip("/")
    return target == scope or target.startswith(scope + "/")


def any_lease_covers(leases: list[dict], path: str) -> bool:
    """Pure check given list of active leases."""
    target = normalize_policy_path(path)
    for lease in leases:
        if lease.get("status", "active") != "active":
            continue
        allowed_paths = lease.get("allowed_paths", [])
        if not isinstance(allowed_paths, list):
            continue
        for allowed_path in allowed_paths:
            if path_covers(str(allowed_path), target):
                return True
    return False


def evaluate(
    tool: str,
    command: str,
    path: str,
    cwd: str,
    actor_role: str,
    active_leases: list[dict],
    mode_config: dict,
) -> Decision:
    """
    Main policy evaluation. Returns the first active violation decision,
    or Decision(outcome='allow') if no violation is active.
    """
    violations = _detect_violations(tool, command, path, cwd, actor_role, active_leases, mode_config)
    for invariant_id, reason in violations:
        mode = _get_invariant_mode(invariant_id, mode_config)
        if mode == "disabled":
            continue
        if mode == "warn":
            return Decision(outcome="warn", invariant_id=invariant_id, reason=reason)
        return Decision(outcome="deny", invariant_id=invariant_id, reason=reason)
    return Decision(outcome="allow")


def _detect_violations(
    tool: str,
    command: str,
    path: str,
    cwd: str,
    actor_role: str,
    active_leases: list[dict],
    mode_config: dict,
) -> list[tuple[str, str]]:
    """All invariant checks; return list of (invariant_id, reason)."""
    violations: list[tuple[str, str]] = []

    if tool == "Bash":
        git = parse_git_command(command)
        if git:
            if git.subcmd in {"commit", "push"}:
                violations.append((InvariantId.IntegratorOnlyCommit.value, f"raw git {git.subcmd} is blocked"))

            if git.subcmd == "commit":
                _append_plan_contract_violation(
                    violations,
                    tool=tool,
                    path=path,
                    cwd=cwd,
                    actor_role=actor_role,
                    active_leases=active_leases,
                    mode_config=mode_config,
                )

            if git.subcmd == "reset" and "--hard" in git.args:
                violations.append((InvariantId.ProtectedBranchNoTouch.value, "git reset --hard is blocked"))

            if git.subcmd == "branch" and any(arg in git.args for arg in ("-f", "-D", "-d")):
                violations.append((InvariantId.ProtectedBranchNoTouch.value, "branch mutation is blocked"))

            if git.subcmd in {"checkout", "switch"}:
                target = _infer_git_target(git.args)
                if target in PROTECTED_BRANCHES:
                    violations.append((InvariantId.ProtectedBranchNoTouch.value, f"checkout/switch to {target} blocked"))

            if git.subcmd in {"merge", "rebase", "cherry-pick", "pull"}:
                violations.append((InvariantId.IntegratorOnlyCommit.value, f"git {git.subcmd} requires integrator script"))

            if git.subcmd == "worktree" and any(arg in git.args for arg in ("add", "remove", "prune")):
                violations.append((InvariantId.PerTaskWorktree.value, "worktree mutation requires org wrapper"))

        if _dangerous_shell(command):
            violations.append((InvariantId.DangerousShell.value, "destructive/remote-exec pattern blocked"))

    elif tool in WRITE_TOOLS:
        target = normalize_policy_path(path, cwd)
        if is_generated_file(target):
            violations.append((InvariantId.StateMutationViaOrgTool.value, "direct edit of generated file blocked"))
        elif is_protected_state_file(target):
            violations.append((InvariantId.StateMutationViaOrgTool.value, f"direct edit of {target or path} is blocked"))
        elif is_kernel_file(target):
            violations.append((InvariantId.KernelFileNoTouch.value, f"kernel file edit of {target or path} is blocked"))
        elif not _is_outside_cwd(path, cwd) and not any_lease_covers(active_leases, target):
            violations.append((InvariantId.LeaseBeforeWrite.value, f"write to {target or path} without active lease covering it"))
        else:
            _append_plan_contract_violation(
                violations,
                tool=tool,
                path=path,
                cwd=cwd,
                actor_role=actor_role,
                active_leases=active_leases,
                mode_config=mode_config,
            )

    return violations


def _get_invariant_mode(invariant_id: str, config: dict) -> str:
    """Per-invariant mode lookup with default fallback."""
    if not isinstance(config, dict):
        return "warn"
    invariants = config.get("invariants", {})
    if not isinstance(invariants, dict):
        invariants = {}
    return _valid_kernel_mode(invariants.get(invariant_id), _valid_kernel_mode(config.get("default")))


def _append_plan_contract_violation(
    violations: list[tuple[str, str]],
    *,
    tool: str,
    path: str,
    cwd: str,
    actor_role: str,
    active_leases: list[dict],
    mode_config: dict,
) -> None:
    task_id = _resolve_plan_contract_task_id(tool, path, cwd, actor_role, active_leases)
    if not task_id:
        return
    if not _plan_contract_subsystem_present(cwd, mode_config):
        return
    if _plan_contract_exists(task_id, cwd, mode_config):
        return
    violations.append(
        (
            InvariantId.PlanContractRequired.value,
            f"PlanContractRequired: .ai/_machine/plans/{task_id}.plan.yaml not found",
        )
    )


def _resolve_plan_contract_task_id(
    tool: str,
    path: str,
    cwd: str,
    actor_role: str,
    active_leases: list[dict],
) -> Optional[str]:
    """Resolve the task id whose plan contract applies to this mutation."""
    if _is_manager_bootstrap_context(actor_role):
        return None

    if tool in WRITE_TOOLS:
        target = normalize_policy_path(path, cwd)
        if _is_plan_contract_path(target) or _is_outside_cwd(path, cwd):
            return None
        lease = _find_covering_lease(active_leases, target)
        return _lease_task_id(lease) if lease else None

    if tool == "Bash":
        task_ids = {
            task_id
            for lease in active_leases
            for task_id in [_lease_task_id(lease)]
            if task_id and lease.get("status", "active") == "active"
        }
        if len(task_ids) == 1:
            return next(iter(task_ids))
    return None


def _find_covering_lease(active_leases: list[dict], path: str) -> Optional[dict]:
    for lease in active_leases:
        if lease.get("status", "active") != "active":
            continue
        allowed_paths = lease.get("allowed_paths", [])
        if not isinstance(allowed_paths, list):
            continue
        for allowed_path in allowed_paths:
            if path_covers(str(allowed_path), path):
                return lease
    return None


def _lease_task_id(lease: Optional[dict]) -> Optional[str]:
    if not isinstance(lease, dict):
        return None
    task_id = str(lease.get("task_id", "") or "").strip()
    return task_id or None


def _is_manager_bootstrap_context(actor_role: str) -> bool:
    role = str(actor_role or "").strip().lower().replace("_", "-")
    return role in {"manager-bootstrap", "bootstrap", "system-bootstrap"}


def _is_plan_contract_path(path: str) -> bool:
    repo_path = normalize_policy_path(path)
    return repo_path == ".ai/_machine/plans" or repo_path.startswith(".ai/_machine/plans/")


def _plan_contract_exists(task_id: str, cwd: str, mode_config: dict) -> bool:
    if not _is_safe_task_id(task_id):
        return False

    expected_path = f".ai/_machine/plans/{task_id}.plan.yaml"
    configured = _configured_plan_contract_exists(task_id, expected_path, mode_config)
    if configured is not None:
        return configured

    plan_path = _resolve_policy_root(cwd) / expected_path
    try:
        return plan_path.is_file()
    except OSError:
        return False


def _plan_contract_subsystem_present(cwd: str, mode_config: dict) -> bool:
    if isinstance(mode_config, dict) and isinstance(mode_config.get("plan_contracts"), dict):
        return True
    try:
        return (_resolve_policy_root(cwd) / ".ai" / "_machine" / "plans").is_dir()
    except OSError:
        return False


def _configured_plan_contract_exists(task_id: str, expected_path: str, mode_config: dict) -> Optional[bool]:
    if not isinstance(mode_config, dict):
        return None
    plan_contracts = mode_config.get("plan_contracts")
    if not isinstance(plan_contracts, dict):
        return None

    if "existing_task_ids" in plan_contracts:
        values = plan_contracts.get("existing_task_ids")
        return isinstance(values, list) and task_id in {str(value) for value in values}

    if "existing_plans" in plan_contracts:
        values = plan_contracts.get("existing_plans")
        return isinstance(values, list) and (
            task_id in {str(value) for value in values}
            or expected_path in {normalize_policy_path(str(value)) for value in values}
        )

    if "existing_plan_paths" in plan_contracts:
        values = plan_contracts.get("existing_plan_paths")
        return isinstance(values, list) and expected_path in {
            normalize_policy_path(str(value)) for value in values
        }

    return None


def _resolve_policy_root(cwd: str) -> Path:
    candidate = Path(str(cwd or ".")).expanduser()
    if candidate.is_file():
        candidate = candidate.parent
    for path in (candidate, *candidate.parents):
        if (path / ".ai").is_dir() or (path / ".git").exists():
            return path
    return candidate


def _is_safe_task_id(task_id: str) -> bool:
    return bool(re.match(r"^[A-Za-z0-9._-]+$", task_id))


def normalize_policy_path(raw_path: str, cwd: str = "") -> str:
    path = str(raw_path or "").strip().replace("\\", "/")
    root = str(cwd or "").strip().replace("\\", "/").rstrip("/")
    if not path:
        return ""
    while path.startswith("./"):
        path = path[2:]
    while root.startswith("./"):
        root = root[2:]
    if root and path == root:
        return ""
    if root and path.startswith(root + "/"):
        path = path[len(root) + 1 :]
    path = re.sub(r"/+", "/", path)
    return path.strip("/")


def _shell_command_segments(command: str) -> list[list[str]]:
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()")
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        return []

    segments: list[list[str]] = []
    current: list[str] = []
    for token in tokens:
        if token and all(char in ";&|()" for char in token):
            if current:
                segments.append(current)
                current = []
            continue
        current.append(token)
    if current:
        segments.append(current)
    return segments


def _parse_git_segment(tokens: list[str], raw_command: str) -> Optional[GitCommand]:
    idx = _skip_command_prefix(tokens, 0)
    if idx >= len(tokens) or tokens[idx] != "git":
        return None

    idx += 1
    while idx < len(tokens):
        token = tokens[idx]
        if token == "-C" and idx + 1 < len(tokens):
            idx += 2
            continue
        if token in ("-c", "--git-dir", "--work-tree") and idx + 1 < len(tokens):
            idx += 2
            continue
        if token.startswith("--git-dir=") or token.startswith("--work-tree="):
            idx += 1
            continue
        if token.startswith("-"):
            idx += 1
            continue
        return GitCommand(token, tokens[idx + 1 :], raw_command)
    return None


def _skip_command_prefix(tokens: list[str], idx: int) -> int:
    while idx < len(tokens):
        token = tokens[idx]
        if token == "command":
            idx += 1
            continue
        if token == "env":
            idx += 1
            while idx < len(tokens):
                current = tokens[idx]
                if current == "--":
                    idx += 1
                    break
                if current in ("-u", "--unset") and idx + 1 < len(tokens):
                    idx += 2
                    continue
                if current.startswith("-"):
                    idx += 1
                    continue
                if _is_assignment(current):
                    idx += 1
                    continue
                break
            continue
        if _is_assignment(token):
            idx += 1
            continue
        break
    return idx


def _infer_git_target(args: list[str]) -> Optional[str]:
    idx = 0
    while idx < len(args):
        token = args[idx]
        if token == "--":
            return args[idx + 1] if idx + 1 < len(args) else None
        if token in ("-b", "-B", "-c", "-C", "--branch", "--create", "--force-create", "-t", "--track"):
            idx += 2
            continue
        if token in ("--detach", "-q", "--quiet", "--guess", "--no-guess", "--merge", "--conflict"):
            idx += 1
            continue
        if token.startswith("-"):
            idx += 1
            continue
        if token in ("-", "@{-1}"):
            return None
        return token
    return None


def _dangerous_shell(command: str) -> bool:
    return bool(
        re.search(r"\brm\s+-rf\s+/", command)
        or re.search(r"^\s*rm\s+-rf\b", command)
        or re.search(r"^\s*git\s+clean\s+-f", command)
        or re.search(r"\b(sudo|mkfs|dd\s+if=|shutdown|reboot)\b", command)
        or re.search(r"curl[^|]+\|\s*(ba)?sh", command)
    )


def _is_assignment(token: str) -> bool:
    return bool(re.match(r"^[A-Za-z_][A-Za-z0-9_]*=.*", token))


def _has_glob(path: str) -> bool:
    return any(char in path for char in "*?[")


def _matches_repo_path(repo_path: str, protected_paths: set[str]) -> bool:
    return repo_path in protected_paths or any(repo_path.endswith("/" + item) for item in protected_paths)


def _is_outside_cwd(path: str, cwd: str) -> bool:
    raw = str(path or "").strip().replace("\\", "/")
    root = str(cwd or "").strip().replace("\\", "/").rstrip("/")
    if not raw.startswith("/") or not root.startswith("/"):
        return False
    return raw != root and not raw.startswith(root + "/")


def _valid_kernel_mode(value: object, default: str = "warn") -> str:
    mode = str(value or "").strip()
    return mode if mode in KERNEL_MODES else default
