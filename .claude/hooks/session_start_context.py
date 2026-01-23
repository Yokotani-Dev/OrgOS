#!/usr/bin/env python3
from datetime import datetime, timedelta
from pathlib import Path
import os
import re
import subprocess

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd()))
CONTROL = ROOT / ".ai" / "CONTROL.yaml"
SESSIONS_DIR = ROOT / ".ai" / "sessions"
RUN_LOG_DAYS = 7

def read_flag(key: str, default: bool = False) -> bool:
    """CONTROL.yaml からフラグを読む"""
    if not CONTROL.exists():
        return default
    text = CONTROL.read_text(encoding="utf-8", errors="ignore")
    m = re.search(rf"^{re.escape(key)}:\s*(true|false)", text, re.MULTILINE | re.IGNORECASE)
    if not m:
        return default
    return m.group(1).lower() == "true"

def check_orgos_dev_origin():
    """OrgOS-Dev リポジトリに接続されているかチェック"""
    try:
        result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            capture_output=True, text=True, cwd=ROOT
        )
        if result.returncode == 0:
            origin_url = result.stdout.strip()
            if "OrgOS-Dev" in origin_url:
                return origin_url
    except Exception:
        pass
    return None


def get_recent_sessions(days: int = RUN_LOG_DAYS) -> list:
    """直近N日間のセッションファイルを取得"""
    if not SESSIONS_DIR.exists():
        return []

    cutoff = datetime.now() - timedelta(days=days)
    sessions = []

    for f in SESSIONS_DIR.glob("*.md"):
        if f.name.startswith("."):
            continue
        try:
            date_str = f.stem[:10]
            file_date = datetime.strptime(date_str, "%Y-%m-%d")
            if file_date >= cutoff:
                sessions.append(f)
        except ValueError:
            continue

    return sorted(sessions, reverse=True)


def load_session_learnings() -> list:
    """直近セッションから学びを抽出"""
    recent = get_recent_sessions()
    if not recent:
        return []

    learnings = []
    for session in recent[:3]:
        content = session.read_text(encoding="utf-8", errors="ignore")
        if "## Key Learnings" in content:
            start = content.find("## Key Learnings")
            end = content.find("\n## ", start + 1)
            if end == -1:
                end = len(content)
            section = content[start:end]
            lines = [l.strip() for l in section.split("\n") if l.strip().startswith("-")]
            for line in lines:
                if line and line not in learnings and "(発見した" not in line:
                    learnings.append(line)
    return learnings[:5]  # 最大5件

def main():
    # SessionStart: stdoutはコンテキストに入る（軽く）
    msg = []

    # OrgOS-Dev 接続チェック（is_orgos_dev=true なら警告スキップ）
    is_orgos_dev = read_flag("is_orgos_dev", False)
    if not is_orgos_dev:
        orgos_dev_origin = check_orgos_dev_origin()
        if orgos_dev_origin:
            msg.append("⚠️ WARNING: OrgOS-Dev リポジトリに接続されています")
            msg.append(f"   origin: {orgos_dev_origin}")
            msg.append("   新しいプロジェクトを始める場合は `/org-init` を実行して切断してください。")
            msg.append("   OrgOS自体の開発を続ける場合は管理者コードを入力してください。")
            msg.append("")

    dashboard = ROOT / ".ai" / "DASHBOARD.md"
    inbox = ROOT / ".ai" / "OWNER_INBOX.md"
    control = ROOT / ".ai" / "CONTROL.yaml"
    tasks = ROOT / ".ai" / "TASKS.yaml"

    msg.append("OrgOS SessionStart:")
    msg.append(f"- Read: {dashboard}")
    msg.append(f"- Owner questions: {inbox}")
    msg.append(f"- Control plane: {control}")
    msg.append("")
    msg.append("⚠️ 重要: 依頼を受けたら必ず OrgOS フローで処理すること")
    msg.append(f"- まず {tasks} を確認して既存タスクとの関連を判断")
    msg.append("- EnterPlanMode は使用禁止 → 代わりに TASKS.yaml で管理")
    msg.append("- 小タスク: 即実行 + RUN_LOG記録")
    msg.append("- 中〜大タスク: TASKS.yaml に追加 → /org-tick で実行")
    msg.append("")
    msg.append("Ownerが介入する場合は .ai/OWNER_COMMENTS.md に追記。Managerは次Tickで反映する。")

    # セッション間メモリ: 直近の学びをロード
    learnings = load_session_learnings()
    if learnings:
        msg.append("")
        msg.append("💡 Recent learnings from past sessions:")
        for learning in learnings:
            msg.append(f"  {learning}")

    print("\n".join(msg))

if __name__ == "__main__":
    main()
