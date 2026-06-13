#!/usr/bin/env python3
"""
セッション間メモリ永続化フック

Stop 時: セッションの学びを .ai/_machine/sessions/ に保存
SessionStart 時: 直近のセッションログを読み込んでコンテキストに追加
"""
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd()))
SESSIONS_DIR = ROOT / ".ai" / "_machine" / "sessions"
LEARNED_DIR = ROOT / ".ai" / "_machine" / "learnings"
STATUS_FILE = ROOT / ".ai" / "STATUS.md"
DECISIONS_FILE = ROOT / ".ai" / "DECISIONS.md"
RUN_LOG_DAYS = 7  # 直近N日間のセッションログを参照


def get_today_session_file() -> Path:
    """今日のセッションファイルパスを取得"""
    today = datetime.now().strftime("%Y-%m-%d")
    return SESSIONS_DIR / f"{today}.md"


def get_recent_sessions(days: int = RUN_LOG_DAYS) -> list[Path]:
    """直近N日間のセッションファイルを取得"""
    if not SESSIONS_DIR.exists():
        return []

    cutoff = datetime.now() - timedelta(days=days)
    sessions = []

    for f in SESSIONS_DIR.glob("*.md"):
        if f.name.startswith("."):
            continue
        try:
            # YYYY-MM-DD.md 形式を想定
            date_str = f.stem[:10]
            file_date = datetime.strptime(date_str, "%Y-%m-%d")
            if file_date >= cutoff:
                sessions.append(f)
        except ValueError:
            continue

    return sorted(sessions, reverse=True)


def extract_recent_activity() -> str:
    """STATUS.md から Recent Activity を抽出"""
    if not STATUS_FILE.exists():
        return ""

    content = STATUS_FILE.read_text(encoding="utf-8", errors="ignore")
    # Recent Activity セクションを抽出
    if "## Recent Activity" in content:
        start = content.find("## Recent Activity")
        end = content.find("\n---", start)
        if end == -1:
            end = len(content)
        return content[start:end].strip()
    return ""


def on_session_start():
    """SessionStart: 直近のセッションログを読み込んで案内"""
    recent = get_recent_sessions()

    if not recent:
        return

    msg = ["", "📚 Recent session context available:"]
    for session in recent[:3]:  # 最新3件まで表示
        msg.append(f"  - {session.name}")

    # 最新セッションの学びをサマリ表示
    latest = recent[0]
    content = latest.read_text(encoding="utf-8", errors="ignore")

    # Key Learnings セクションがあれば抽出
    if "## Key Learnings" in content:
        start = content.find("## Key Learnings")
        end = content.find("\n## ", start + 1)
        if end == -1:
            end = len(content)
        learnings = content[start:end].strip()
        if learnings:
            msg.append("")
            msg.append("💡 From last session:")
            # 最初の3項目のみ
            lines = [l for l in learnings.split("\n") if l.strip().startswith("-")]
            for line in lines[:3]:
                msg.append(f"  {line}")

    print("\n".join(msg))


def on_session_end():
    """Stop: セッションの学びを保存"""
    SESSIONS_DIR.mkdir(parents=True, exist_ok=True)

    session_file = get_today_session_file()
    now = datetime.now().strftime("%H:%M")

    # 既存のセッションファイルがあれば追記、なければ新規作成
    if session_file.exists():
        content = session_file.read_text(encoding="utf-8", errors="ignore")
        # End Time を更新
        if "End:" in content:
            lines = content.split("\n")
            for i, line in enumerate(lines):
                if line.startswith("End:"):
                    lines[i] = f"End: {now}"
                    break
            content = "\n".join(lines)
        session_file.write_text(content, encoding="utf-8")
    else:
        # 新規セッションファイル作成
        recent_activity = extract_recent_activity()
        template = f"""# Session Log: {datetime.now().strftime("%Y-%m-%d")}

Start: {now}
End: {now}

## Summary

(セッション終了時に自動更新 or /org-learn で手動追記)

## Key Learnings

- (発見したパターン、ワークアラウンド、エラー解決策など)

## Recent Activity

{recent_activity if recent_activity else "(STATUS.md から抽出)"}

## Notes

(追加メモ)
"""
        session_file.write_text(template, encoding="utf-8")

    # stderr に出力（ユーザーへの通知）
    print(f"📝 Session log saved: {session_file.relative_to(ROOT)}", file=sys.stderr)


def main():
    """メイン: 引数に応じて処理を分岐"""
    if len(sys.argv) < 2:
        print("Usage: session_memory.py [start|end]", file=sys.stderr)
        sys.exit(1)

    action = sys.argv[1]

    if action == "start":
        on_session_start()
    elif action == "end":
        # Stop フックからの呼び出し: stdin から JSON を読む
        try:
            _ = json.load(sys.stdin)
        except:
            pass
        on_session_end()
        # 空の JSON を返す（ブロックしない）
        print(json.dumps({}))
    else:
        print(f"Unknown action: {action}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
