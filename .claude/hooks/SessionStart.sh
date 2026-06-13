#!/bin/bash
# SessionStart Hook
# 新しいセッション開始時に実行される

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTROL_FILE="$PROJECT_ROOT/.ai/CONTROL.yaml"
HANDOFF_FILE="$PROJECT_ROOT/.ai/HANDOFF.md"
DEFAULT_CHECKSUM_VERIFIER="$PROJECT_ROOT/scripts/org/check-generated-checksums.py"
CHECKSUM_VERIFIER="${ORGOS_GENERATED_CHECKSUM_VERIFIER:-$DEFAULT_CHECKSUM_VERIFIER}"
SHADOW_DB="$PROJECT_ROOT/.ai/orgos.sqlite"
REBUILD_SHADOW="$PROJECT_ROOT/scripts/org/rebuild-shadow.py"

# RC-4 / T-OS-494: the SQLite shadow + generated views are rebuildable
# projections (gitignored). Rebuild-or-refresh them before verifying so a
# fresh clone (or stale shadow) reconciles to TASKS.yaml automatically instead
# of warning "orgos.sqlite not found". Best-effort and non-blocking: a rebuild
# failure must never block session start.
rebuild_shadow_views() {
  [ -f "$REBUILD_SHADOW" ] && command -v python3 >/dev/null 2>&1 || return 0
  set +e
  rebuild_output=$(cd "$PROJECT_ROOT" && python3 "$REBUILD_SHADOW" 2>&1)
  rebuild_status=$?
  set -e
  if [ "$rebuild_status" -ne 0 ]; then
    echo ""
    echo "⚠️ Owner note: SQLite shadow rebuild skipped (rebuild-shadow.py exit $rebuild_status)"
    printf '%s\n' "$rebuild_output" | sed 's/^/  /'
    echo "Session continues (warn only)."
  fi
  return 0
}

run_generated_checksum_check() {
  local output status verifier_label verifier_mode

  # Reconcile the rebuildable shadow + views to TASKS.yaml first so the
  # checksum baseline below matches the freshly generated views.
  rebuild_shadow_views

  verifier_label="$CHECKSUM_VERIFIER"

  if [ -x "$CHECKSUM_VERIFIER" ]; then
    verifier_mode="direct"
  elif [ -f "$CHECKSUM_VERIFIER" ] && command -v python3 >/dev/null 2>&1; then
    verifier_mode="python"
  elif command -v "$CHECKSUM_VERIFIER" >/dev/null 2>&1; then
    verifier_mode="direct"
    verifier_label=$(command -v "$CHECKSUM_VERIFIER" 2>/dev/null || printf '%s' "$CHECKSUM_VERIFIER")
  elif [ "$CHECKSUM_VERIFIER" = "$DEFAULT_CHECKSUM_VERIFIER" ] && command -v check-generated-checksums.py >/dev/null 2>&1; then
    CHECKSUM_VERIFIER="check-generated-checksums.py"
    verifier_mode="direct"
    verifier_label=$(command -v check-generated-checksums.py 2>/dev/null || printf '%s' "check-generated-checksums.py")
  else
    # ISS-008: do not fail silently when the verifier is missing.
    # Warn visibly but never block session start (exit 0).
    echo ""
    echo "⚠️ Owner warning: checksum verifier not found: $verifier_label"
    echo "→ generated-view integrity check skipped (expected: scripts/org/check-generated-checksums.py)"
    echo "Session continues (warn only)."
    return 0
  fi

  set +e
  if [ "$verifier_mode" = "python" ]; then
    output=$(cd "$PROJECT_ROOT" && python3 "$CHECKSUM_VERIFIER" 2>&1)
  else
    output=$(cd "$PROJECT_ROOT" && "$CHECKSUM_VERIFIER" 2>&1)
  fi
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    echo ""
    echo "⚠️ Owner warning: generated checksum mismatch detected"
    echo "→ $verifier_label"
    if [ -n "$output" ]; then
      printf '%s\n' "$output" | sed 's/^/  /'
    fi
    echo "Session continues (warn only)."
  fi

  return 0
}

# 現在日付の注入（日付誤認防止）
TODAY=$(date +"%Y-%m-%d")
CURRENT_YEAR=$(date +"%Y")
echo "OrgOS SessionStart:"
echo "- Read: $PROJECT_ROOT/.ai/DASHBOARD.md"
echo "- Owner questions: $PROJECT_ROOT/.ai/OWNER_INBOX.md"
echo "- Control plane: $CONTROL_FILE"

run_generated_checksum_check

# CONTROL.yaml から handoff.enabled を確認
# ISS-008(e): 旧 pipeline (`grep "enabled:" | grep -A 1 "handoff:"`) は
# 「enabled: を含む行」の中から handoff: を探していたため恒常的に空だった。
# awk でトップレベル handoff: ブロック内の enabled: を読む。
handoff_enabled=$(awk '
  /^handoff:/ { in_block = 1; next }
  in_block && /^[^[:space:]]/ { in_block = 0 }
  in_block && $1 == "enabled:" { print $2; exit }
' "$CONTROL_FILE" 2>/dev/null || true)

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
SESSIONS_DIR="$PROJECT_ROOT/.ai/_machine/sessions"
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

# Codex CLI チェック
if ! command -v codex &>/dev/null; then
  echo ""
  echo "⚠️ Codex CLI が未インストールです（コーディング・レビューに必要）"
  echo "  npm install -g @openai/codex && codex --login"
elif [ ! -f "$HOME/.codex/auth.json" ] && [ ! -f "$HOME/.config/codex/auth.json" ]; then
  echo ""
  echo "⚠️ Codex CLI が未ログインです"
  echo "  codex --login"
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
