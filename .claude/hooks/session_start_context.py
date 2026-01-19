#!/usr/bin/env python3
from pathlib import Path
import os

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd()))

def main():
    # SessionStart: stdoutはコンテキストに入る（軽く）
    dashboard = ROOT / ".ai" / "DASHBOARD.md"
    inbox = ROOT / ".ai" / "OWNER_INBOX.md"
    control = ROOT / ".ai" / "CONTROL.yaml"
    msg = []
    msg.append("OrgOS SessionStart:")
    msg.append(f"- Read: {dashboard}")
    msg.append(f"- Owner questions: {inbox}")
    msg.append(f"- Control plane: {control}")
    msg.append("Ownerが介入する場合は .ai/OWNER_COMMENTS.md に追記。Managerは次Tickで反映する。")
    print("\n".join(msg))

if __name__ == "__main__":
    main()
