# OrgOS Evals 設計書

> OIP-AUTO を安全に適用するための免疫系。Eval スクリプト群で変更の安全性を検証する。

**ステータス**: 実装完了
**作成日**: 2026-02-13
**関連タスク**: T-INT-004

---

## 1. 目的

Intelligence Worker が生成する OIP-AUTO（OrgOS 改善提案）を安全に自動適用するための検証基盤。

- Level 0（情報記録のみ）: Eval 不要、自動適用
- Level 1（Userland 軽微変更）: Eval pass で自動承認
- Level 2+: Owner 承認必須

---

## 2. Kernel / Userland 境界

### Kernel（自動変更禁止）

| ファイル | 理由 |
|----------|------|
| `.claude/rules/security.md` | 安全制御の根幹 |
| `.claude/rules/review-criteria.md` | レビュー基準の定義 |
| `.claude/rules/project-flow.md` | OrgOS 基本フロー |
| `.ai/CONTROL.yaml` | OS 制御設定 |

管理: [.claude/evals/KERNEL_FILES](../../.claude/evals/KERNEL_FILES)

### Userland（Intelligence が提案可能）

| パス | 内容 |
|------|------|
| `.claude/agents/*.md` | エージェント定義 |
| `.claude/rules/agent-coordination.md` | モデル選択・並列実行 |
| `.claude/rules/performance.md` | パフォーマンス設定 |
| `.claude/skills/*.md` | 技術スキル |
| `.claude/rules/testing.md` | テスト基準（追加方向のみ） |

---

## 3. Eval スクリプト一覧

| スクリプト | 検証内容 | カテゴリ |
|-----------|---------|---------|
| `check-kernel-boundary.sh` | 変更ファイルが Kernel に含まれないか | 安全性 |
| `check-schema.sh` | TASKS.yaml / CONTROL.yaml のスキーマ検証 | 整合性 |
| `check-agent-defs.sh` | エージェント定義の必須フィールド | 整合性 |
| `check-security.sh` | セキュリティルールの存在・一貫性 | 安全性 |
| `check-oip-format.sh` | OIP-AUTO の必須フィールド | 品質 |

### 実行方法

```bash
# 全 Eval 実行
.claude/evals/run-all.sh

# JSON 出力
.claude/evals/run-all.sh --json

# OIP PR の変更ファイル指定
.claude/evals/run-all.sh --changed-files .claude/agents/org-architect.md .claude/skills/coding-standards.md
```

### 出力フォーマット

```json
{
  "timestamp": "2026-02-13T05:28:18Z",
  "overall": "pass",
  "pass": 5, "fail": 0, "warn": 0,
  "results": [
    {"eval": "kernel-boundary", "status": "pass", "details": "..."},
    ...
  ]
}
```

---

## 4. org-tick 統合

Step 9A として OIP PR 検出 + Eval 判定を実行:

1. `gh pr list --label oip-auto` で PR を検出
2. 変更ファイルから Level を判定
3. Level 1: Eval 実行 → pass なら自動マージ
4. Level 2+: Owner 通知

---

## 5. 将来の拡張

- Eval スクリプトの追加（パフォーマンス、互換性チェックなど）
- CI/CD パイプラインとの統合
- 自動ロールバック（T-INT-005）
