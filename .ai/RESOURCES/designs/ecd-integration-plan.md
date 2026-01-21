# ECD (everything-claude-code) 統合計画

> OrgOS に everything-claude-code の機能を取り込む設計書

---

## 概要

### 目的

OrgOS は「何を作るか」を管理するが、「どう作るか」の技術ガイダンスがない。
ECD の skills/rules を取り込むことで、実装品質の基準を提供する。

### 参照元

- リポジトリ: https://github.com/affaan-m/everything-claude-code
- 作者: Affaan Mustafa（Anthropic ハッカソン優勝者）
- 特徴: 10ヶ月以上の実運用から得たベストプラクティス集

---

## 取り込み方針

### 取り込むもの

| 層 | 取り込み | 理由 |
|-----|----------|------|
| Contexts | NO | OrgOS は Stage 管理があるので不要 |
| Commands | 一部 | /org-learn のみ新規追加 |
| Agents | 一部 | org-security-reviewer 新規、org-reviewer 強化 |
| Skills | YES | OrgOS にない層。技術知識ベースとして追加 |
| Rules | YES | 品質基準として追加 |
| Hooks/MCP | NO | ユーザー環境依存。参考情報として案内のみ |

### 配置先

`.claude/` 配下に配置（OrgOS 同梱方式）

理由:
- OrgOS をクローンすれば全部揃う
- プロジェクト固有にカスタマイズする余地も残る
- `.ai/RESOURCES/` はユーザーの参照資料用なので不適切

---

## ディレクトリ構造（変更後）

```
.claude/
  agents/
    org-planner.md
    org-architect.md
    org-reviewer.md              # 強化
    org-integrator.md
    org-scribe.md
    org-implementer.md
    org-os-maintainer.md
    org-security-reviewer.md     # 新規
  commands/
    org-start.md
    org-tick.md
    org-plan.md
    org-review.md
    org-integrate.md
    org-release.md
    org-export.md
    org-import.md
    org-publish.md
    org-codex.md
    org-admin.md
    org-brief.md
    org-kickoff.md
    org-os-retro.md
    org-learn.md                 # 新規
  hooks/
    stop_gate.py
    pretool_policy.py
    session_start_context.py
  scripts/
    run-parallel.sh
  skills/                        # 新規ディレクトリ
    coding-standards.md
    backend-patterns.md
    frontend-patterns.md
    tdd-workflow.md
  rules/                         # 新規ディレクトリ
    security.md
    testing.md
    review-criteria.md
    patterns.md

.ai/
  LEARNINGS/                     # 新規ディレクトリ
    README.md
```

---

## 取り込みファイル詳細

### Skills（新規追加）

| ファイル | 元ネタ | 内容 |
|----------|--------|------|
| coding-standards.md | ECD skills/coding-standards.md | コーディング規約（TypeScript/React/API設計）、KISS/DRY/YAGNI原則 |
| backend-patterns.md | ECD skills/backend-patterns.md | リポジトリパターン、サービス層、API設計 |
| frontend-patterns.md | ECD skills/frontend-patterns.md | カスタムフック、状態管理、コンポーネント設計 |
| tdd-workflow.md | ECD skills/tdd-workflow/ + agents/tdd-guide.md | TDD手順（Red-Green-Refactor）、80%カバレッジ目標 |

### Rules（新規追加）

| ファイル | 元ネタ | 内容 |
|----------|--------|------|
| security.md | ECD rules/security.md | セキュリティチェック（OWASP Top 10、シークレット管理） |
| testing.md | ECD rules/testing.md | テスト基準（80%カバレッジ、TDD強制オプション） |
| review-criteria.md | ECD agents/code-reviewer.md + OrgOS統合 | レビュー基準（CRITICAL/HIGH/MEDIUM） |
| patterns.md | ECD rules/patterns.md | API応答形式、共通パターン |

### Agents（新規・強化）

| ファイル | 種別 | 内容 |
|----------|------|------|
| org-security-reviewer.md | 新規 | セキュリティ専門レビュー（OWASP、脆弱性検出） |
| org-reviewer.md | 強化 | review-criteria.md を参照するよう追記 |

### Commands（新規）

| ファイル | 元ネタ | 内容 |
|----------|--------|------|
| org-learn.md | ECD commands/learn.md | セッション中の学びを抽出し .ai/LEARNINGS/ に保存 |

---

## 実装フェーズ

### Phase 2-1: Skills 追加

```
作業内容:
1. .claude/skills/ ディレクトリ作成
2. coding-standards.md 作成（ECD ベース、OrgOS向け調整）
3. backend-patterns.md 作成（ECD そのまま or 軽微調整）
4. frontend-patterns.md 作成（ECD そのまま or 軽微調整）
5. tdd-workflow.md 作成（ECD 複数ファイルを統合）

依存: なし
```

### Phase 2-2: Rules 追加

```
作業内容:
1. .claude/rules/ ディレクトリ作成
2. security.md 作成（ECD ベース）
3. testing.md 作成（ECD ベース）
4. review-criteria.md 作成（ECD code-reviewer + OrgOS基準統合）
5. patterns.md 作成（ECD ベース）

依存: なし
```

### Phase 2-3: org-reviewer 強化

```
作業内容:
1. org-reviewer.md を編集
2. 「.claude/rules/review-criteria.md に従ってレビューする」を追記
3. Review Packet の出力形式に基準適合状況を追加

依存: Phase 2-2 完了後
```

### Phase 2-4: org-security-reviewer 新規作成

```
作業内容:
1. org-security-reviewer.md 作成
2. ECD security-reviewer.md をベースにOrgOS向け調整
3. OWASP Top 10 チェック、シークレット検出を含める

依存: Phase 2-2 完了後
```

### Phase 2-5: org-learn コマンド新規作成

```
作業内容:
1. .ai/LEARNINGS/ ディレクトリ作成
2. .ai/LEARNINGS/README.md 作成
3. .claude/commands/org-learn.md 作成
4. セッション振り返り → パターン抽出 → 保存のフロー実装

依存: なし
```

### Phase 2-6: ドキュメント更新

```
作業内容:
1. CLAUDE.md に skills/rules の説明追加
2. ORGOS_QUICKSTART.md 更新
3. 必要に応じて AGENTS.md 更新

依存: 全Phase完了後
```

---

## 統合方針の詳細

### Skills の参照方法

Work Order 生成時に参照を明記:

```markdown
## 参照資料
- コーディング規約: .claude/skills/coding-standards.md
- TDDワークフロー: .claude/skills/tdd-workflow.md
```

### TDD の適用方法

タスク単位で workflow を指定:

```yaml
# TASKS.yaml
- id: T-003
  title: 認証機能の実装
  workflow: tdd          # TDD 強制
  coverage_target: 80%   # カバレッジ目標
```

### レビュー基準の適用

org-reviewer が自動的に review-criteria.md を参照:

```markdown
## レビュー結果

### CRITICAL（即修正必須）
- なし

### HIGH（修正推奨）
- src/utils.ts:45-120 - 関数が75行（50行以下推奨）

### MEDIUM（改善提案）
- src/hooks.ts:12 - useMemo で最適化可能

**判定: ⚠️ HIGH問題あり、修正後に再レビュー**
```

### 学習の蓄積

/org-learn 実行時:

```
.ai/LEARNINGS/
  2026-01-21-supabase-rls-gotcha.md
  2026-01-22-nextjs-caching-issue.md
```

---

## リスクと対策

| リスク | 対策 |
|--------|------|
| ECD の内容が OrgOS の思想と合わない部分がある | OrgOS 向けに調整して取り込む |
| Skills/Rules が増えすぎてメンテナンス負荷増大 | 厳選して取り込む、定期的に棚卸し |
| Codex worker が Skills を無視する | Work Order に明示的に参照を記載 |
| ECD のアップデートに追従できない | Fork ではなく「インスパイア」として独自管理 |

---

## 承認

- [ ] Owner 承認
- [ ] 実装開始

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-21 | 初版作成 |
