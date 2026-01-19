#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd()))
CONTROL = ROOT / ".ai" / "CONTROL.yaml"
TASKS = ROOT / ".ai" / "TASKS.yaml"

def flag(key: str, default=False) -> bool:
    if not CONTROL.exists():
        return default
    text = CONTROL.read_text(encoding="utf-8", errors="ignore")
    m = re.search(rf"^{re.escape(key)}:\s*(true|false)\s*$", text, re.MULTILINE | re.IGNORECASE)
    return (m.group(1).lower() == "true") if m else default

def tasks_remaining() -> bool:
    if not TASKS.exists():
        return False
    t = TASKS.read_text(encoding="utf-8", errors="ignore")
    # queued/running/blocked/review が残っていれば継続
    return bool(re.search(r"status:\s*(queued|running|blocked|review)\b", t))

def main():
    _ = json.load(sys.stdin)  # not used now

    autopilot = flag("autopilot", False)
    paused = flag("paused", False)
    awaiting_owner = flag("awaiting_owner", False)

    if not autopilot or paused or awaiting_owner:
        # stopping allowed
        print(json.dumps({}))
        sys.exit(0)

    if tasks_remaining():
        # block stopping -> Claude must continue (次の発話で/org-tickを実行する運用)
        print(json.dumps({
            "decision": "block",
            "reason": "OrgOS autopilot: tasks remain. Run /org-tick to proceed (or set paused:true / awaiting_owner:true)."
        }))
        sys.exit(0)

    # no tasks -> allow stop
    print(json.dumps({}))
    sys.exit(0)

if __name__ == "__main__":
    main()
