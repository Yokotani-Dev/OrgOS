#!/bin/bash
# SessionStart Hook
# 新しいセッション開始時に実行される

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTROL_FILE="$PROJECT_ROOT/.ai/CONTROL.yaml"
HANDOFF_FILE="$PROJECT_ROOT/.ai/HANDOFF.md"

# CONTROL.yaml から handoff.enabled を確認
handoff_enabled=$(grep "enabled:" "$CONTROL_FILE" | grep -A 1 "handoff:" | tail -1 | sed 's/.*enabled: //' | tr -d ' ')

if [ "$handoff_enabled" = "true" ]; then
  echo ""
  echo "🔄 プロジェクト引き継ぎが検出されました"
  echo ""
  echo "引き継ぎドキュメントを確認してください："
  echo "→ $HANDOFF_FILE"
  echo ""
  echo "📌 次のステップ："
  echo "1. HANDOFF.md を読んで、引き継ぎ情報を確認"
  echo "2. 不明点があれば OWNER_COMMENTS.md に記入"
  echo "3. /org-tick で作業を再開"
  echo ""
fi

# セッション間のメモリをロード（既存の機能）
SESSIONS_DIR="$PROJECT_ROOT/.ai/sessions"
if [ -d "$SESSIONS_DIR" ]; then
  latest_session=$(ls -t "$SESSIONS_DIR"/*.md 2>/dev/null | head -1)
  if [ -n "$latest_session" ]; then
    echo "📝 前回のセッション学習をロード: $(basename "$latest_session")"
  fi
fi

# DASHBOARD.md の表示
DASHBOARD_FILE="$PROJECT_ROOT/.ai/DASHBOARD.md"
if [ -f "$DASHBOARD_FILE" ]; then
  cat "$DASHBOARD_FILE"
fi

# Owner への案内
OWNER_INBOX="$PROJECT_ROOT/.ai/OWNER_INBOX.md"
if [ -f "$OWNER_INBOX" ]; then
  pending_questions=$(grep -c "^###" "$OWNER_INBOX" 2>/dev/null || echo "0")
  if [ "$pending_questions" -gt 0 ]; then
    echo ""
    echo "📬 Owner への質問が $pending_questions 件あります"
    echo "→ $OWNER_INBOX"
  fi
fi

# CONTROL.yaml の表示
echo ""
echo "⚙️  Control plane: $CONTROL_FILE"
echo ""
echo "⚠️ 重要: 依頼を受けたら必ず OrgOS フローで処理すること"
echo "- まず $PROJECT_ROOT/.ai/TASKS.yaml を確認して既存タスクとの関連を判断"
echo "- EnterPlanMode は使用禁止 → 代わりに TASKS.yaml で管理"
echo "- 小タスク: 即実行 + RUN_LOG記録"
echo "- 中〜大タスク: TASKS.yaml に追加 → /org-tick で実行"
echo ""
echo "Ownerが介入する場合は .ai/OWNER_COMMENTS.md に追記。Managerは次Tickで反映する。"
