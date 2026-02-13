# Work Order: T-INT-005

## Task
- ID: T-INT-005
- Title: Intelligence Phase 5: ロールバック機構 + Kernel 保護
- Role: implementer

## Context

orgos-intelligence は Cloudflare Workers + Hono で構築された AI 技術トレンド収集 + OIP-AUTO 提案システム。
現在 Phase 3 まで実装済み（OIP-AUTO PR 作成 + Slack 承認/却下）。

Phase 5 では以下を追加する:
1. 自動適用（マージ）した変更のロールバック機構
2. Kernel ファイル変更の自動検知・ブロック
3. ロールバック時の Owner 通知

## Acceptance Criteria

1. **ロールバック機構**
   - Slack から「ロールバック」コマンドで approved/merged OIP を取り消せる
   - `git revert` 相当の操作を GitHub API 経由で実行（revert commit + PR 作成）
   - ロールバック後に Slack 通知: 「OIP-AUTO-XXX をロールバックしました。理由: ...」
   - OIP ステータスを `rolled_back` に更新（KV 保存）

2. **Kernel 保護の自動検知・ブロック**
   - Kernel ファイル一覧（以下の4ファイル）:
     - `.claude/rules/security.md`
     - `.claude/rules/review-criteria.md`
     - `.claude/rules/project-flow.md`
     - `.ai/CONTROL.yaml`
   - OIP 生成時に `targetFiles` が Kernel ファイルを含む場合、`impactScope` を自動的に `"Kernel"` に設定
   - Slack 承認時に Kernel スコープの OIP は通常の「OK」では承認不可
   - Kernel 承認には明示的なコマンド（例: `OIP-AUTO-XXX KERNEL-APPROVE`）が必要
   - Kernel 承認を試みた場合、警告メッセージを表示

3. **ロールバック時の Owner 通知**
   - Slack チャンネルにロールバック結果を Block Kit で投稿
   - ロールバック理由、対象 OIP、revert PR URL を含む

## Implementation Guide

### 1. 型定義の拡張 (src/types.ts)

OipAutoProposal に以下のフィールドを追加:
```typescript
// 既存フィールドに追加
rolled_back?: boolean;
rolled_back_at?: string;
roll_back_reason?: string;
revert_pr_url?: string;
revert_pr_number?: number;
merged_at?: string;        // マージ日時の記録（ロールバック対象判定用）
merge_commit_sha?: string; // revert 対象の SHA
```

### 2. ロールバック機能 (src/github/revert.ts) - 新規作成

GitHub API を使って revert を実行する関数:
```
- revertOipPullRequest(env, oip): 承認済み OIP の PR をリバートする
  - oip.merge_commit_sha を使って revert commit を作成
  - または新しい PR で `.ai/OIP/{oip.id}.md` を削除するコミットを作成
  - revert PR を作成して自動マージ
```

実装アプローチ（推奨: ファイル削除 PR 方式）:
- merge_commit_sha からの git revert は GitHub API では複雑
- 代わりに `.ai/OIP/{oip.id}.md` を削除する新しいコミット + PR を作成
- PR タイトル: `[REVERT] {oip.id}: {oip.title}`
- PR を作成後、自動マージ

### 3. Slack イベントハンドリング拡張 (src/slack/events.ts)

既存の `handleOipAction` を拡張:

**ロールバックコマンドの追加:**
- パターン: `OIP-AUTO-XXX ロールバック <理由>` or `OIP-AUTO-XXX rollback <reason>`
- ステータスが `approved` の OIP のみロールバック可能
- ロールバック実行後、Slack にロールバック結果を投稿

**Kernel 保護の追加:**
- `handleOipAction` 内で、承認時に `impactScope === "Kernel"` をチェック
- 通常の「OK」「承認」コマンドでは Kernel OIP を承認不可
- `KERNEL-APPROVE` コマンドで明示的に承認した場合のみ PR 作成
- Kernel 承認時に追加の警告メッセージを表示

### 4. OIP ジェネレーター改善 (src/analyzer/oip-generator.ts)

- `targetFiles` が Kernel ファイルを含む場合、`impactScope` を強制的に `"Kernel"` に設定
- 既存の Claude Sonnet プロンプトで Kernel/Userland 区別を指示しているが、
  生成後にダブルチェックする後処理を追加

### 5. PR 作成時のメタデータ記録 (src/slack/events.ts)

OIP 承認 → PR 作成成功時に、以下も KV に保存:
- `merged_at`: マージ日時（PR 作成時点では未マージだが、マージイベント検知が複雑なため PR 作成日時で代用可）
- `merge_commit_sha`: PR の HEAD SHA（revert 用）

### 6. Slack Block Kit (src/slack/blocks.ts)

ロールバック結果の Block Kit メッセージを追加:
```
🔄 OIP-AUTO-XXX をロールバックしました

理由: <ロールバック理由>
対象: <OIP タイトル>
Revert PR: <PR URL>

ステータス: rolled_back
```

## Kernel ファイル一覧（定数として定義）

```typescript
const KERNEL_FILES = [
  ".claude/rules/security.md",
  ".claude/rules/review-criteria.md",
  ".claude/rules/project-flow.md",
  ".ai/CONTROL.yaml",
];
```

## 注意事項

- TypeScript ビルドが通ること（`npx tsc --noEmit`）
- 既存の Phase 1-3 の機能を壊さないこと
- エラーハンドリングを適切に行うこと（GitHub API エラー、KV エラー等）
- エラーメッセージに機密情報を含めないこと
- console.error でログ出力、throw 時はサニタイズされたメッセージ

## Reference

- 設計書: OrgOS リポジトリの .ai/DESIGN/ORGOS_INTELLIGENCE.md（Section 7.5, 12, 16）
- 設計書: .ai/DESIGN/ORGOS_EVALS.md（Kernel/Userland 境界定義）
