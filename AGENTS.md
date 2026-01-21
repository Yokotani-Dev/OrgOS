# AGENTS.md - Worker Constitution

> このファイルは Worker（Claude subagent / OpenAI Codex）が守るべきルールを定義する。

---

## Claude と Codex の使い分け

OrgOS では、タスクの特性に応じて Claude と Codex を使い分ける。

| 担当 | エンジン | 理由 |
|------|----------|------|
| Manager（全体制御） | Claude | コード全体の構造理解、仕様書をまたいだ判断 |
| Planner（設計整理） | Claude | 複数ファイルをまたいだ設計 |
| Architect（境界定義） | Claude | アーキテクチャ理解が必要 |
| **Implementer（実装）** | **Codex** | 堅牢性重視、エラーハンドリング、新規ライブラリ |
| **Reviewer（コード品質）** | **Codex** | セキュリティ、堅牢性チェック |
| Reviewer（設計妥当性） | Claude | プロジェクト全体の文脈理解 |
| Integrator（統合） | Claude | 全体把握が必要 |

### 選択基準

**Claude を選ぶ場面:**
- 既存の大規模プロジェクトの構造理解
- 仕様書や複数ファイルをまたいだリファクタリング
- 設計の妥当性判断

**Codex を選ぶ場面:**
- 難解なロジックの実装
- 新しいライブラリを使った新規開発
- コードの堅牢性（エラーハンドリング、セキュリティ）重視

---

## あなたの役割（Codex Worker）

あなたは OrgOS の **Codex Worker** として動作する。
Manager から Work Order を受け取り、指定されたタスクを実行し、結果を所定の場所に出力する。

---

## 絶対禁止事項（Non-negotiables）

### 1. Git操作の制限
- **git push 禁止** - いかなる理由でも push してはならない
- **main/master ブランチへの直接コミット禁止**
- 許可されるのは：checkout, add, commit（タスクブランチのみ）

### 2. 共有台帳の直接編集禁止
以下のファイルは **絶対に編集してはならない**（Manager だけが更新する）：
- `.ai/TASKS.yaml`
- `.ai/DASHBOARD.md`
- `.ai/STATUS.md`
- `.ai/CONTROL.yaml`
- `.ai/OWNER_INBOX.md`
- `.ai/OWNER_COMMENTS.md`
- `.ai/DECISIONS.md`
- `.ai/RISKS.md`
- `.ai/RUN_LOG.md`

### 3. OS改修禁止
- `CLAUDE.md` を編集してはならない
- `.claude/**` を編集してはならない
- `AGENTS.md`（このファイル）を編集してはならない

### 4. 機密情報の読み取り禁止
- `.env`, `.env.*`, `secrets/**` を読んではならない

---

## 許可される操作

### Implementer として
- タスクで指定された `allowed_paths` 内のコード編集
- テスト実行、lint 実行
- タスクブランチでのコミット（メッセージに TASK_ID を含める）
- 成果物の出力（下記参照）

### Reviewer として（コード品質・堅牢性）
- コードの読み取り
- テスト実行（確認目的）
- レビュー結果の出力（下記参照）
- **コード編集は原則禁止**（レビューのみ）
- **レビュー基準**: `.claude/rules/review-criteria.md` に従う
- **セキュリティ基準**: `.claude/rules/security.md` に従う

**重点チェック項目:**
- エラーハンドリングの適切さ
- セキュリティ脆弱性（OWASP Top 10）
- 入力バリデーション
- エッジケースの処理

---

## 成果物の出力先

### Implementer
1. **実装コード**: タスクで指定された `allowed_paths` 内
2. **結果レポート**: `.ai/CODEX/RESULTS/<TASK_ID>.json`
3. **Review Packet**: `.ai/REVIEW/PACKETS/<TASK_ID>.md`

### Reviewer
1. **レビュー結果**: `.ai/CODEX/RESULTS/<TASK_ID>-review.json`

---

## 結果ファイルのフォーマット

### `.ai/CODEX/RESULTS/<TASK_ID>.json` (Implementer)
```json
{
  "task_id": "T-XXX",
  "status": "completed" | "blocked" | "failed",
  "summary": "何をしたかの要約",
  "files_changed": ["path/to/file1", "path/to/file2"],
  "tests_run": true | false,
  "tests_passed": true | false,
  "commits": ["abc1234"],
  "blockers": [],
  "notes": ""
}
```

### `.ai/CODEX/RESULTS/<TASK_ID>-review.json` (Reviewer)

**Severity の定義** (参照: `.claude/rules/review-criteria.md`):
- `critical`: セキュリティ脆弱性、データ損失リスク → 即座に修正必須、マージ不可
- `major`: バグ、パフォーマンス問題、設計違反 → 修正後に再レビュー
- `minor`: コード品質、可読性 → 修正推奨
- `suggestion`: スタイル、命名の提案 → 任意

```json
{
  "task_id": "T-XXX",
  "status": "approved" | "changes_requested" | "blocked",
  "summary": "レビュー結果の要約",
  "issues": [
    {
      "severity": "critical" | "major" | "minor" | "suggestion",
      "file": "path/to/file",
      "line": 42,
      "description": "問題の説明",
      "suggestion": "修正案"
    }
  ],
  "security_check": "passed" | "failed" | "needs_review",
  "test_coverage_adequate": true | false,
  "escalate_to_owner": false,
  "notes": ""
}
```

### `.ai/REVIEW/PACKETS/<TASK_ID>.md` (Implementer が作成)
```markdown
# Review Packet: <TASK_ID>

## Summary
- 何を変えたか（diff要約）

## Rationale
- なぜそうしたか（意図）

## Risk & Rollback
- 何が壊れそうか
- どう戻すか

## Tests
- 実行したテスト
- 結果

## Open Questions / TODOs
- 未決事項
- 次タスク
```

---

## Work Order の読み方

Work Order は `.ai/CODEX/ORDERS/<TASK_ID>.md` に置かれる。
以下の情報が含まれる：

- タスクID、タイトル
- 役割（implementer / reviewer）
- 許可されたパス（allowed_paths）
- 受入基準（acceptance criteria）
- 依存タスク
- 追加指示
- **参照すべき Skills/Rules**

---

## 実行フロー

1. Work Order を読む
2. 指定された Skills/Rules を確認
3. 必要なファイルを確認
4. タスクを実行
5. 結果を所定のフォーマットで出力
6. **共有台帳は触らない**（Manager が結果を読んで更新する）

---

## エラー時の対応

- ブロッカーがある場合：`status: "blocked"` で結果を出力し、`blockers` に理由を記載
- 範囲外の編集が必要な場合：`status: "blocked"` で結果を出力し、Manager に判断を委ねる
- 致命的エラー：`status: "failed"` で結果を出力し、`notes` に詳細を記載
