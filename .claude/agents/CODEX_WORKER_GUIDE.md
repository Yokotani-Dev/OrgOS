# CODEX_WORKER_GUIDE

> Codex worker（OpenAI Codex CLI）が参照するガイドライン

---

## 概要

Codex worker は OrgOS Manager から委任されたタスクを実行します。
Work Order（`.ai/CODEX/ORDERS/<TASK_ID>.md`）に従って作業を進めます。

---

## 作業フロー

### 1. Work Order を読む

`.ai/CODEX/ORDERS/<TASK_ID>.md` を読み、以下を確認：
- タスクID
- タイトル
- 許可されたパス（Allowed Paths）
- 受け入れ基準（Acceptance Criteria）
- 依存関係
- 追加の指示

### 2. 関連ドキュメントを読む

Work Order に記載された参考資料を読む：
- `CODEX_WORKER_GUIDE.md`（このファイル、必読）
- `.ai/PROJECT.md`
- `.ai/GIT_WORKFLOW.md`
- `.claude/skills/*`（該当するもの）
- `.claude/rules/*`（該当するもの）

### 3. 実装・レビューを実行

Work Order の role に応じて：
- `implementer`: 実装を行う
- `reviewer`: レビューを行う

### 4. 結果を記録

`.ai/CODEX/RESULTS/<TASK_ID>.md` に結果を記録：
- ステータス（completed / blocked / failed / changes_requested）
- 実施内容
- 変更ファイル一覧
- 次のアクション

---

## 資料と成果物の管理

### 原則

**資料（resources/）は直接編集しない**

資料を編集したい場合：
1. 資料を `outputs/` にコピー
2. コピーした成果物を編集
3. 成果物を `outputs/` に配置

### 資料複製フロー

```bash
# 1. 資料を outputs/ にコピー
cp resources/samplecode/example.ts outputs/2026-01-23/example.ts

# 2. 成果物を編集
# vim outputs/2026-01-23/example.ts

# 3. 成果物はそのまま outputs/ に残す
```

### outputs/ フォルダ構造

#### 日付別

```
outputs/
├── 2026-01-23/
│   ├── sample1.ts
│   ├── sample2.md
│   └── README.md
```

**用途:**
- 日常的な作業成果物
- ad-hoc の依頼で生成したファイル

#### タスクID別

```
outputs/
├── T-003/
│   ├── implementation.ts
│   ├── tests.ts
│   └── README.md
```

**用途:**
- タスクに紐付く成果物
- 実装コード、テスト、設計ドキュメント

### Work Order での指示例

```markdown
## Instructions

資料を参考に実装してください：
- 参照: resources/samplecode/auth.ts
- 成果物: outputs/T-003/auth-implementation.ts に配置

**重要:**
- resources/ のファイルは直接編集しない
- 必要に応じて outputs/ にコピーしてから編集
```

---

## 許可されたパス（Allowed Paths）

Work Order の Allowed Paths に記載されたパス以外は変更しないでください。

例：
```
Allowed Paths:
- src/auth/
- tests/auth/
- outputs/T-003/
```

→ `src/api/` や `src/utils/` は変更不可

---

## 台帳ファイルの扱い

**Codex worker は共有台帳を直接編集しない**

台帳ファイル：
- `.ai/PROJECT.md`
- `.ai/DECISIONS.md`
- `.ai/TASKS.yaml`
- `.ai/STATUS.md`
- `.ai/DASHBOARD.md`

これらは Manager が更新します。Codex worker は読み取り専用として扱います。

---

## git ワークフロー

### ブランチ戦略

Codex worker は専用の worktree で作業します：
- `.worktrees/<TASK_ID>/` に worktree が作成されている
- ブランチ: `task/<TASK_ID>-<slug>`

### コミット

実装完了時にコミット：
```bash
git add <変更ファイル>
git commit -m "<タスクタイトル>

<詳細説明>

Task-ID: <TASK_ID>
Co-Authored-By: Codex Worker <noreply@openai.com>"
```

### プッシュ禁止

**Codex worker は git push しない**

Manager（org-integrator）が統合時にプッシュします。

---

## セキュリティ

### 秘密情報の扱い

- API キー、パスワード、トークンをハードコードしない
- 環境変数（`process.env.*`）を使用
- `.env` ファイルは git に含めない

### 保護対象ブランチ

`main` ブランチには直接コミットしない。
Manager が統合を担当します。

---

## テスト

### カバレッジ要件

- Statements: 80% 以上
- Branches: 80% 以上
- Functions: 80% 以上
- Lines: 80% 以上

### TDD ワークフロー

1. テストを書く（失敗することを確認）
2. 最小限のコードでテストを通す
3. リファクタリング

詳細: `.claude/skills/tdd-workflow.md`

---

## レビュー

### Review Packet

実装完了時に Review Packet を作成：
- `.ai/REVIEW/PACKETS/<TASK_ID>.md`
- 変更の背景、意図、トレードオフを記載

テンプレート: `.ai/REVIEW/PACKET.template.md`

---

## トラブルシューティング

### ブロッカーが発生した場合

`.ai/CODEX/RESULTS/<TASK_ID>.md` に記録：
```markdown
status: blocked
blocker: "外部APIのドキュメントが不明"
next_action: "Owner に確認が必要"
```

### 失敗した場合

```markdown
status: failed
reason: "テストが通らない"
details: |
  - テストケース: test/auth.spec.ts:42
  - エラー: Expected 200, got 401
next_action: "org-build-fixer にエスカレーション"
```

---

## 参考資料

- [.ai/PROJECT.md](../../.ai/PROJECT.md) - プロジェクト概要
- [.ai/GIT_WORKFLOW.md](../../.ai/GIT_WORKFLOW.md) - git ワークフロー
- [.claude/skills/](../skills/) - 技術知識ベース
- [.claude/rules/](../rules/) - 品質基準
- [outputs/README.md](../../outputs/README.md) - 成果物管理ガイド
