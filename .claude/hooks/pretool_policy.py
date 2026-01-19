#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd()))
CONTROL = ROOT / ".ai" / "CONTROL.yaml"

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

def block(msg: str):
    # exit code 2 => tool call is blocked; stderr is shown to Claude
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

    allow_push = read_flag("allow_push", False)
    allow_push_main = read_flag("allow_push_main", False)
    allow_main_mutation = read_flag("allow_main_mutation", False)
    allow_deploy = read_flag("allow_deploy", False)
    allow_destructive_ops = read_flag("allow_destructive_ops", False)
    allow_os_mutation = read_flag("allow_os_mutation", False)
    main_branch = read_value("main_branch", "main")

    # ---- OS mutation guard: block writes/edits to OS files unless approved ----
    if tool in ("Write", "Edit"):
        path = tool_input.get("path", "") or ""
        # OSとして守りたい範囲
        if path == "CLAUDE.md" or path.startswith(".claude/") or path.startswith(".ai/CONTROL.yaml"):
            if not allow_os_mutation:
                block(f"OrgOS blocked: OS mutation requires Owner approval (allow_os_mutation=true). Target={path}")

    # ---- Bash guard ----
    if tool != "Bash":
        allow_json("non-bash tool allowed")
        return

    cmd = (tool_input.get("command") or "").strip()
    if not cmd:
        allow_json("empty bash command")
        return

    # Destructive/system-dangerous commands
    if re.search(r"\b(sudo|mkfs|dd\s+if=|shutdown|reboot)\b", cmd):
        block("OrgOS blocked: dangerous system command.")

    if re.search(r"\brm\s+-rf\b", cmd) or re.search(r"\bgit\s+clean\s+-f", cmd):
        if not allow_destructive_ops:
            block("OrgOS blocked: destructive ops disabled (allow_destructive_ops=false).")
        allow_json("destructive ops allowed by Owner flag")
        return

    # Git governance
    if cmd.startswith("git "):
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

    # Deploy guard (examples: adjust per project)
    if re.search(r"\b(kubectl|terraform|pulumi)\b", cmd) or re.search(r"\bdeploy\b", cmd):
        if not allow_deploy:
            block("OrgOS blocked: deploy operations require Owner approval (allow_deploy=true).")

    allow_json("bash allowed by policy")

if __name__ == "__main__":
    main()
