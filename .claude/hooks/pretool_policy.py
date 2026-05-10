#!/usr/bin/env python3
import json
import os
import re
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd()))
CONTROL = ROOT / ".ai" / "CONTROL.yaml"
STATE_DIR = ROOT / ".claude" / "state"
KERNEL_FILES_PATH = ROOT / ".claude" / "evals" / "KERNEL_FILES"
GIT_LOCK_SCRIPT = ROOT / "scripts" / "git" / "acquire-lock.sh"
GIT_LOCK_RELEASE_SCRIPT = ROOT / "scripts" / "git" / "release-lock.sh"
BRANCH_CHECK_SCRIPT = ROOT / "scripts" / "git" / "check-branch-consistency.sh"
GIT_LOCK_FILE = STATE_DIR / "git.lock"
_KERNEL_FILES_CACHE: Optional[set[str]] = None
_POLICY_ACQUIRED_GIT_LOCK = False
BRANCH_GUARDED_GIT_OPS = ("checkout", "switch", "commit", "merge", "rebase", "stash", "push")
BRANCH_GUARD_PATTERN = re.compile(
    r"(^|[;&|()]\s*)git(?:\s+(?:-C\s+\S+|-c\s+\S+|--git-dir=\S+|--work-tree=\S+))*\s+("
    + "|".join(BRANCH_GUARDED_GIT_OPS)
    + r")\b(?P<args>[^;&|()]*)"
)


def read_flag(key: str, default: bool = False) -> bool:
    if not CONTROL.exists():
        return default
    text = CONTROL.read_text(encoding="utf-8", errors="ignore")
    m = re.search(rf"^{re.escape(key)}:\s*(true|false)\s*$", text, re.MULTILINE | re.IGNORECASE)
    if not m:
        return default
    return m.group(1).lower() == "true"

def read_value(key: str, default: str = "") -> str:
    if not CONTROL.exists():
        return default
    text = CONTROL.read_text(encoding="utf-8", errors="ignore")
    m = re.search(rf"^{re.escape(key)}:\s*\"?([^\n\"]+)\"?\s*$", text, re.MULTILINE)
    return m.group(1).strip() if m else default


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


def target_file_from_tool_input(tool_input: dict) -> str:
    for key in ("path", "file_path"):
        value = str(tool_input.get(key, "") or "").strip()
        if value:
            return normalize_repo_path(value)
    return ""


def load_kernel_files() -> set[str]:
    global _KERNEL_FILES_CACHE
    if _KERNEL_FILES_CACHE is not None:
        return _KERNEL_FILES_CACHE

    kernel_files: set[str] = set()
    if KERNEL_FILES_PATH.exists():
        for line in KERNEL_FILES_PATH.read_text(encoding="utf-8", errors="ignore").splitlines():
            entry = line.strip()
            if not entry or entry.startswith("#"):
                continue
            kernel_files.add(normalize_repo_path(entry))

    _KERNEL_FILES_CACHE = kernel_files
    return _KERNEL_FILES_CACHE


def block_kernel_file(target_file: str) -> None:
    message = f"KERNEL_FILE protection: {target_file} cannot be edited (allow_os_mutation=true でも禁止)"
    context = {
        "event": "pretool_policy_block",
        "target_file": target_file,
        "reason": "kernel_file_always_forbidden",
    }
    block(message + "\n" + json.dumps(context, ensure_ascii=False, sort_keys=True))


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def safe_session_id(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "_", value.strip())
    return cleaned[:120] or "unknown"


def get_session_id(data: dict, tool_input: dict) -> str:
    for env_key in ("CLAUDE_SESSION_ID", "CODEX_SESSION_ID", "ORGOS_SESSION_ID"):
        value = os.environ.get(env_key, "").strip()
        if value:
            return safe_session_id(value)

    for key in ("session_id", "sessionId"):
        value = str(data.get(key, "") or tool_input.get(key, "")).strip()
        if value:
            return safe_session_id(value)

    transcript_path = str(data.get("transcript_path", "")).strip()
    if transcript_path:
        return safe_session_id(Path(transcript_path).stem)

    return "default"


def expected_branch_path(session_id: str) -> Path:
    return STATE_DIR / f"expected_branch_{safe_session_id(session_id)}"


def run_git_branch() -> str:
    try:
        result = subprocess.run(
            ["git", "branch", "--show-current"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("git branch check timed out") from exc
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or "").strip()
        raise RuntimeError(f"git branch check failed: {detail}") from exc
    return result.stdout.strip()


def state_payload(session_id: str, branch: str) -> dict:
    return {
        "session_id": session_id,
        "recorded_at": utc_now(),
        "expected_branch": branch,
        "worktree_path": str(ROOT.resolve()),
    }


def record_session_branch(session_id: str, branch: Optional[str] = None) -> dict:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        current_branch = run_git_branch() if branch is None else branch
    except RuntimeError as exc:
        block(f"OrgOS blocked: cannot initialize expected branch state. {exc}")
    payload = state_payload(session_id, current_branch)
    expected_branch_path(session_id).write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return payload


def read_expected_branch(session_id: str) -> Optional[dict]:
    path = expected_branch_path(session_id)
    if not path.exists():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict) or "expected_branch" not in payload:
        return None
    return payload


def guarded_git_operation(cmd: str) -> Optional[dict]:
    match = BRANCH_GUARD_PATTERN.search(cmd)
    if not match:
        return None
    return {"op": match.group(2), "args": match.group("args").strip()}


def checkout_target(op: str, args: str) -> Optional[str]:
    if op not in ("checkout", "switch"):
        return None
    try:
        tokens = shlex.split(args)
    except ValueError:
        return None

    idx = 0
    while idx < len(tokens):
        token = tokens[idx]
        if token == "--":
            return None
        if token in ("-b", "-B", "-c", "-C", "--branch", "--create", "--force-create"):
            return tokens[idx + 1] if idx + 1 < len(tokens) else None
        if token.startswith("-"):
            idx += 1
            continue
        if token in ("-", "@{-1}"):
            return None
        return token
    return None


def log_branch_mismatch(context: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    session_id = safe_session_id(str(context.get("session_id", "default")))
    log_path = STATE_DIR / f"branch_mismatch_{session_id}.jsonl"
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(context, ensure_ascii=False, sort_keys=True) + "\n")


def log_policy_event(context: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    session_id = safe_session_id(str(context.get("session_id", "default")))
    log_path = STATE_DIR / f"pretool_policy_{session_id}.jsonl"
    payload = {"logged_at": utc_now(), **context}
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")


def read_git_lock_holder() -> dict:
    try:
        return json.loads(GIT_LOCK_FILE.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def session_holds_git_lock(session_id: str) -> bool:
    import fcntl

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        with GIT_LOCK_FILE.open("a+", encoding="utf-8") as handle:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                handle.seek(0)
                try:
                    payload = json.load(handle)
                except json.JSONDecodeError:
                    return False
                holder_session = str(payload.get("sessionId", payload.get("session_id", "")))
                return holder_session == session_id
            else:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
                return False
    except OSError:
        return False


def recent_log_tail(path: Path, max_chars: int = 1200) -> str:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""
    return text[-max_chars:].strip()


def acquire_git_lock(session_id: str, cmd: str) -> None:
    global _POLICY_ACQUIRED_GIT_LOCK

    if session_holds_git_lock(session_id):
        log_policy_event(
            {
                "event": "git_lock_already_held",
                "session_id": session_id,
                "lock_file": str(GIT_LOCK_FILE),
                "command": cmd,
            }
        )
        return

    if not GIT_LOCK_SCRIPT.exists():
        block(f"OrgOS blocked: git lock script missing: {GIT_LOCK_SCRIPT}")

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    lock_log = STATE_DIR / f"git_lock_acquire_{session_id}.log"
    env = os.environ.copy()
    env.setdefault("ORGOS_SESSION_ID", session_id)
    env.setdefault("CLAUDE_PROJECT_DIR", str(ROOT))

    log_policy_event(
        {
            "event": "git_lock_acquire_start",
            "session_id": session_id,
            "lock_file": str(GIT_LOCK_FILE),
            "script": str(GIT_LOCK_SCRIPT),
            "command": cmd,
        }
    )

    try:
        log_handle = lock_log.open("a", encoding="utf-8")
        process = subprocess.Popen(
            ["bash", str(GIT_LOCK_SCRIPT), "--timeout", "30"],
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
            stdout=log_handle,
            stderr=log_handle,
            text=True,
            env=env,
            start_new_session=True,
        )
    except OSError as exc:
        block(f"OrgOS blocked: failed to start git lock acquisition. {exc}")

    deadline = time.monotonic() + 31
    try:
        while time.monotonic() < deadline:
            if session_holds_git_lock(session_id):
                _POLICY_ACQUIRED_GIT_LOCK = True
                log_policy_event(
                    {
                        "event": "git_lock_acquire_passed",
                        "session_id": session_id,
                        "holder": read_git_lock_holder(),
                        "log_file": str(lock_log),
                    }
                )
                return

            status = process.poll()
            if status is not None:
                detail = recent_log_tail(lock_log)
                block(
                    "OrgOS blocked: failed to acquire git lock before git mutation.\n"
                    f"Exit status: {status}\n"
                    f"Lock file: {GIT_LOCK_FILE}\n"
                    f"Log file: {lock_log}\n"
                    f"Detail: {detail or '(no output)'}"
                )

            time.sleep(0.1)
    finally:
        log_handle.close()

    if process.poll() is None:
        process.terminate()
    detail = recent_log_tail(lock_log)
    block(
        "OrgOS blocked: timed out waiting for git lock acquisition.\n"
        f"Lock file: {GIT_LOCK_FILE}\n"
        f"Log file: {lock_log}\n"
        f"Detail: {detail or '(no output)'}"
    )


def release_policy_git_lock() -> None:
    global _POLICY_ACQUIRED_GIT_LOCK

    if not _POLICY_ACQUIRED_GIT_LOCK or not GIT_LOCK_RELEASE_SCRIPT.exists():
        return

    try:
        result = subprocess.run(
            ["bash", str(GIT_LOCK_RELEASE_SCRIPT)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=7,
        )
        log_policy_event(
            {
                "event": "git_lock_released_after_policy_block",
                "exit_status": result.returncode,
                "stdout": result.stdout.strip(),
                "stderr": result.stderr.strip(),
                "lock_file": str(GIT_LOCK_FILE),
            }
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        log_policy_event(
            {
                "event": "git_lock_release_after_policy_block_failed",
                "error": str(exc),
                "lock_file": str(GIT_LOCK_FILE),
            }
        )
    finally:
        _POLICY_ACQUIRED_GIT_LOCK = False


def run_branch_block_check(session_id: str, require_lock: bool) -> None:
    if not BRANCH_CHECK_SCRIPT.exists():
        block(f"OrgOS blocked: branch consistency script missing: {BRANCH_CHECK_SCRIPT}")

    args = ["bash", str(BRANCH_CHECK_SCRIPT), "--block-if-mismatch"]
    if require_lock:
        args.append("--require-lock")

    env = os.environ.copy()
    env.setdefault("ORGOS_SESSION_ID", session_id)
    env.setdefault("CLAUDE_PROJECT_DIR", str(ROOT))

    result = subprocess.run(
        args,
        cwd=ROOT,
        capture_output=True,
        text=True,
        env=env,
        timeout=5,
    )
    log_policy_event(
        {
            "event": "branch_block_check",
            "session_id": session_id,
            "exit_status": result.returncode,
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip(),
            "require_lock": require_lock,
        }
    )
    if result.returncode != 0:
        detail = "\n".join(part for part in (result.stderr.strip(), result.stdout.strip()) if part)
        block(f"OrgOS blocked: branch consistency gate failed.\n{detail}")


def enforce_git_mutation_gate(data: dict, tool_input: dict, cmd: str) -> bool:
    operation = guarded_git_operation(cmd)
    if operation is None:
        return False

    session_id = get_session_id(data, tool_input)
    acquire_git_lock(session_id, cmd)
    # checkout/switch operations resolve mismatches; skip strict --block-if-mismatch gate
    # and rely on verify_branch_consistency (target == expected check) instead.
    op = str(operation.get("op", ""))
    if op not in ("checkout", "switch"):
        run_branch_block_check(session_id, require_lock=True)
    verify_branch_consistency(data, tool_input, cmd)
    return True


def verify_branch_consistency(data: dict, tool_input: dict, cmd: str) -> None:
    operation = guarded_git_operation(cmd)
    if operation is None:
        return

    session_id = get_session_id(data, tool_input)
    expected = read_expected_branch(session_id)
    if expected is None:
        expected = record_session_branch(session_id)

    try:
        current_branch = run_git_branch()
    except RuntimeError as exc:
        block(f"OrgOS blocked: cannot verify git branch consistency. {exc}")
    expected_branch = str(expected.get("expected_branch", ""))
    op = str(operation.get("op", ""))
    target_branch = checkout_target(op, str(operation.get("args", "")))

    if op in ("checkout", "switch") and target_branch and target_branch != expected_branch:
        context = {
            "event": "branch_switch_target_mismatch",
            "detected_at": utc_now(),
            "session_id": session_id,
            "expected_branch": expected_branch,
            "current_branch": current_branch,
            "target_branch": target_branch,
            "command": cmd,
            "state_file": str(expected_branch_path(session_id)),
            "worktree_path": str(ROOT.resolve()),
            "tool_name": data.get("tool_name", ""),
        }
        log_branch_mismatch(context)
        block(
            "OrgOS blocked: git branch switch target does not match expected branch.\n"
            f"Expected branch: {expected_branch or '(detached/empty)'}\n"
            f"Current branch: {current_branch or '(detached/empty)'}\n"
            f"Requested target: {target_branch}\n"
            f"Session: {session_id}\n"
            f"State file: {expected_branch_path(session_id)}\n"
            "Owner-approved branch switches must update the expected branch first."
        )

    if op in ("checkout", "switch") and target_branch == expected_branch:
        return

    if current_branch == expected_branch:
        return

    context = {
        "event": "branch_mismatch",
        "detected_at": utc_now(),
        "session_id": session_id,
        "expected_branch": expected_branch,
        "current_branch": current_branch,
        "command": cmd,
        "state_file": str(expected_branch_path(session_id)),
        "worktree_path": str(ROOT.resolve()),
        "tool_name": data.get("tool_name", ""),
    }
    log_branch_mismatch(context)
    block(
        "OrgOS blocked: git branch mismatch detected before git operation.\n"
        f"Expected branch: {expected_branch or '(detached/empty)'}\n"
        f"Current branch: {current_branch or '(detached/empty)'}\n"
        f"Session: {session_id}\n"
        f"State file: {expected_branch_path(session_id)}\n"
        "Stop and ask Owner before continuing. If this branch change was intentional, "
        "update the expected branch explicitly before retrying."
    )


def ensure_session_branch_recorded(session_id: str) -> None:
    if read_expected_branch(session_id) is None:
        record_session_branch(session_id)


def block(msg: str):
    # exit code 2 => tool call is blocked; stderr is shown to Claude
    release_policy_git_lock()
    print(msg, file=sys.stderr)
    sys.exit(2)

def allow_json(reason: str):
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": reason
        }
    }
    print(json.dumps(out))
    sys.exit(0)

def main():
    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input", {}) or {}
    session_id = get_session_id(data, tool_input)

    allow_push = read_flag("allow_push", False)
    allow_push_main = read_flag("allow_push_main", False)
    allow_main_mutation = read_flag("allow_main_mutation", False)
    allow_deploy = read_flag("allow_deploy", False)
    allow_destructive_ops = read_flag("allow_destructive_ops", False)
    allow_os_mutation = read_flag("allow_os_mutation", False)
    main_branch = read_value("main_branch", "main")

    # ---- Kernel file guard: always block protected OS core files ----
    if tool in ("Write", "Edit"):
        path = target_file_from_tool_input(tool_input)
        if path in load_kernel_files():
            block_kernel_file(path)

        # ---- OS mutation guard: block writes/edits to OS files unless approved ----
        if path in ("AGENTS.md", "CLAUDE.md", ".ai/CONTROL.yaml") or path.startswith(".claude/"):
            if not allow_os_mutation:
                block(f"OrgOS blocked: OS mutation requires Owner approval (allow_os_mutation=true). Target={path}")

    # ---- Bash guard ----
    if tool != "Bash":
        ensure_session_branch_recorded(session_id)
        allow_json("non-bash tool allowed")
        return

    cmd = (tool_input.get("command") or "").strip()
    if not cmd:
        ensure_session_branch_recorded(session_id)
        allow_json("empty bash command")
        return

    ensure_session_branch_recorded(session_id)

    # Destructive/system-dangerous commands
    if re.search(r"\b(sudo|mkfs|dd\s+if=|shutdown|reboot)\b", cmd):
        block("OrgOS blocked: dangerous system command.")

    # Destructive rm/git clean - only match at command start, not in strings/messages
    if re.match(r"^\s*rm\s+-rf\b", cmd) or re.match(r"^\s*git\s+clean\s+-f", cmd):
        # Allow rm -rf for temp directories
        if re.search(r"\brm\s+-rf\s+(/tmp/|/var/folders/|/private/tmp/)", cmd):
            allow_json("rm -rf allowed for temp directory")
            return
        if not allow_destructive_ops:
            block("OrgOS blocked: destructive ops disabled (allow_destructive_ops=false).")
        allow_json("destructive ops allowed by Owner flag")
        return

    # Git governance
    if cmd.startswith("git "):
        mutation_gate_applied = enforce_git_mutation_gate(data, tool_input, cmd)
        if not mutation_gate_applied:
            verify_branch_consistency(data, tool_input, cmd)

        # Block push unless approved
        if re.match(r"^git\s+push\b", cmd):
            # push main / push others
            if re.search(rf"\b{re.escape(main_branch)}\b", cmd) or re.search(r"\bHEAD:main\b", cmd):
                if not allow_push_main:
                    block("OrgOS blocked: push to main disabled (allow_push_main=false).")
            else:
                if not allow_push:
                    block("OrgOS blocked: git push disabled (allow_push=false).")
            allow_json("git push allowed by Owner flag")
            return

        # Protect main mutation (best-effort)
        # (完全に厳密なブランチ検知は環境差があるため、最小限の禁止として運用)
        if re.match(r"^git\s+(commit|merge|rebase|cherry-pick|reset|tag)\b", cmd):
            if not allow_main_mutation and re.search(rf"\b{re.escape(main_branch)}\b", cmd):
                block(f"OrgOS blocked: main mutation disabled (allow_main_mutation=false).")

    else:
        mutation_gate_applied = enforce_git_mutation_gate(data, tool_input, cmd)
        if not mutation_gate_applied:
            verify_branch_consistency(data, tool_input, cmd)

    # Deploy guard (examples: adjust per project)
    if re.search(r"\b(kubectl|terraform|pulumi)\b", cmd) or re.search(r"\bdeploy\b", cmd):
        if not allow_deploy:
            block("OrgOS blocked: deploy operations require Owner approval (allow_deploy=true).")

    allow_json("bash allowed by policy")

if __name__ == "__main__":
    main()
