#!/bin/bash
# check-skill-compliance.sh
# スキル準拠チェック（Iron Law 違反の検出）
# 参照: obra/superpowers 圧力テスト

set -uo pipefail

SKILLS_DIR=".claude/skills"
RULES_DIR=".claude/rules"
AGENTS_DIR=".claude/agents"
ERRORS=0

echo "=== Skill Compliance Check ==="
echo ""

# 1. CSO チェック: description がワークフローを含んでいないか
echo "--- CSO Check: description should only say WHEN to use ---"
for f in "$AGENTS_DIR"/*.md; do
  desc=$(head -10 "$f" | grep "description:" | sed 's/description: *//' || true)
  if [ -n "$desc" ]; then
    verb_count=$(echo "$desc" | grep -oE '(する|して|実行|作成|確認|更新|生成|分析|検出)' | wc -l | tr -d ' ')
    if [ "$verb_count" -gt 3 ]; then
      echo "  WARN: $f - description に動詞が ${verb_count} 個（ワークフロー記述の可能性）"
      echo "        → description は「いつ使うか」のみにする"
    fi
  fi
done
echo ""

# 2. Iron Law チェック: 重要スキルに Iron Law セクションがあるか
echo "--- Iron Law Check: critical skills should have Iron Law ---"
CRITICAL_SKILLS=(
  "testing.md"
  "security.md"
  "review-criteria.md"
  "task-breakdown.md"
  "requirements-specification.md"
)
for skill in "${CRITICAL_SKILLS[@]}"; do
  if [ -f "$SKILLS_DIR/$skill" ]; then
    if ! grep -q "Iron Law" "$SKILLS_DIR/$skill"; then
      echo "  WARN: $SKILLS_DIR/$skill - Iron Law セクションがない"
      ERRORS=$((ERRORS + 1))
    fi
  fi
done
echo ""

# 3. 合理化防止ルールの存在チェック
echo "--- Rationalization Prevention Check ---"
if [ ! -f "$RULES_DIR/rationalization-prevention.md" ]; then
  echo "  FAIL: rationalization-prevention.md が存在しない"
  ERRORS=$((ERRORS + 1))
else
  echo "  OK: rationalization-prevention.md が存在する"
fi
echo ""

# 4. org-reviewer が二段階レビューを実装しているか
echo "--- Two-Stage Review Check ---"
if [ -f "$AGENTS_DIR/org-reviewer.md" ]; then
  if grep -q "Stage 1" "$AGENTS_DIR/org-reviewer.md" && grep -q "Stage 2" "$AGENTS_DIR/org-reviewer.md"; then
    echo "  OK: org-reviewer に二段階レビューが実装されている"
  else
    echo "  WARN: org-reviewer に二段階レビューが未実装"
    ERRORS=$((ERRORS + 1))
  fi
fi
echo ""

# 5. レポート検証プロトコルの存在チェック
echo "--- Report Verification Check ---"
if grep -q "信用しない\|信用するな\|Do Not Trust" "$RULES_DIR/agent-coordination.md" 2>/dev/null; then
  echo "  OK: agent-coordination にレポート検証プロトコルがある"
else
  echo "  WARN: agent-coordination にレポート検証プロトコルがない"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# 結果
echo "=== Results ==="
if [ "$ERRORS" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "WARNINGS/ERRORS: $ERRORS"
  exit 1
fi
