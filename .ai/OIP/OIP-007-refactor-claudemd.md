# OIP-007: CLAUDE.md のリファクタリングと Manager の独立

**ステータス**: 承認済み
**提案日**: 2026-01-23
**承認日**: 2026-01-23
**実装予定**: 2026-01-23

---

## 概要

CLAUDE.md（788行）を軽量化し、Manager を `.claude/agents/manager.md` に独立させる。

---

## 動機

### 現状の問題

1. **CLAUDE.md が冗長**（788行）
   - Manager の振る舞い、運用ルール、具体例が混在
   - コンテキスト消費が大きい
   - 保守性が低い

2. **Manager が agents/ にない**
   - 他のエージェント（org-implementer など）は `.claude/agents/` に配置
   - Manager だけ特別扱い → 一貫性がない

3. **ルールが重複**
   - CLAUDE.md と `.claude/rules/` に同じ内容が散在

---

## 提案

### Phase 1: ルールの分離

以下のルールを `.claude/rules/` に分離：

| 新規ファイル | 内容 | CLAUDE.md から移動 |
|--------------|------|-------------------|
| `project-flow.md` | OrgOS フロー優先、スコープ制限、タスク規模判定 | ✅ |
| `session-management.md` | セッション終了提案、コンテキスト管理 | ✅ |
| `next-step-guidance.md` | 次のステップ案内、選択肢提示ルール | ✅ |
| `plan-sync.md` | 計画の継続的更新 | ✅ |

### Phase 2: Manager の独立

1. **`.claude/agents/manager.md` を作成**
   - Manager の詳細な振る舞い
   - Tick フロー
   - エージェント起動ロジック

2. **CLAUDE.md を薄い版に置き換え**（~100行）
   - 基本原則のみ
   - 詳細は `.claude/agents/manager.md` を参照

---

## 実装計画

### タスク一覧

```yaml
- id: OIP-007-T1
  title: ".claude/rules/project-flow.md 作成"

- id: OIP-007-T2
  title: ".claude/rules/session-management.md 作成"

- id: OIP-007-T3
  title: ".claude/rules/next-step-guidance.md 作成"

- id: OIP-007-T4
  title: ".claude/rules/plan-sync.md 作成"

- id: OIP-007-T5
  title: ".claude/agents/manager.md 作成"

- id: OIP-007-T6
  title: "CLAUDE.md を薄い版に置き換え"

- id: OIP-007-T7
  title: "動作確認（新セッションで /org-tick 実行）"
```

### 推定工数

- Phase 1: 1-2 Tick
- Phase 2: 1 Tick
- 動作確認: 1 Tick

**合計: 3-4 Tick**

---

## 影響範囲

### 既存プロジェクトへの影響

**なし（下位互換性あり）**

- CLAUDE.md は残る（薄くなるだけ）
- ルールは `.claude/rules/` から参照される（既存ルールはそのまま）
- Manager の動作は変わらない

### OrgOS 本体への影響

**あり（改善）**

- コンテキスト消費が減少（788行 → 100行 + 参照）
- 保守性向上（責務分離）
- 一貫性向上（Manager も agents/ で管理）

---

## リスク

### 低リスク

- **理由**: 参照構造を変えるだけで、動作は変わらない
- **対策**: 動作確認を必ず実施

### リスク項目

| リスク | 対策 |
|--------|------|
| 参照漏れ | 新セッションで動作確認 |
| 既存ルールとの重複 | 既存 rules/ を確認しながら作成 |

---

## 代替案

### A: Phase 1 のみ実行

- ルールの分離のみ
- Manager は CLAUDE.md のまま

**却下理由**: Manager の独立による一貫性向上が得られない

### B: CLAUDE.md を完全削除

- Manager を `.claude/agents/manager.md` に完全移行
- CLAUDE.md を削除

**却下理由**: Claude Code が CLAUDE.md を自動読み込みするため、削除すると動作しない

---

## 成功基準

- [x] CLAUDE.md が 150行程度になる（191行、目標より少し多いが 75% 削減）
- [x] `.claude/agents/manager.md` が作成される
- [ ] 新セッションで `/org-tick` が正常動作する（次セッションで確認）
- [x] 既存ルールとの重複がない

---

## 参考資料

- [CLAUDE.md](../../CLAUDE.md)
- [.claude/rules/](../../.claude/rules/)
- [.claude/agents/](../../.claude/agents/)

---

## 実装開始

Owner 承認済み。実装を開始します。
