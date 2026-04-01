# エージェント協調パターン

> OrgOS エージェントの効率的な協調・実行パターン

---

## モデル選択ガイダンス

### 使い分けの原則

| モデル | ユースケース | 特徴 |
|--------|--------------|------|
| **Haiku** | 単純なタスク、高速応答が必要な場合 | 低コスト、低レイテンシ |
| **Sonnet** | 通常の実装・レビュー・分析 | バランス型（デフォルト） |
| **Opus** | 複雑な設計判断、難解なデバッグ | 最高精度、高コスト |

### タスク別推奨モデル

```yaml
# Haiku を使うタスク
- ファイル検索・パターンマッチ
- 単純なフォーマット変更
- 定型的なコード生成
- ログ解析（パターン抽出）

# Sonnet を使うタスク（デフォルト）
- 機能実装
- コードレビュー
- バグ修正
- ドキュメント生成
- テスト作成

# Opus を使うタスク
- アーキテクチャ設計
- 複雑なリファクタリング
- セキュリティ監査
- パフォーマンス最適化
- 原因不明のバグ調査
```

### Task ツールでの指定方法

```typescript
// 単純なファイル検索 → Haiku
Task({
  subagent_type: "Explore",
  model: "haiku",
  prompt: "src/utils/ 内の全ての .ts ファイルを列挙"
});

// 通常の実装 → Sonnet（デフォルト）
Task({
  subagent_type: "org-implementer",
  prompt: "ユーザー認証機能を実装"
});

// 複雑な設計判断 → Opus
Task({
  subagent_type: "org-architect",
  model: "opus",
  prompt: "マイクロサービス分割の境界を設計"
});
```

---

## 並列実行パターン

### いつ並列実行するか

```
✅ 並列実行すべき場合:
- 互いに依存しないタスク
- 読み取り専用の操作
- 異なるファイル/モジュールへの変更

❌ 直列実行すべき場合:
- タスク間に依存関係がある
- 同じファイルを変更する
- 前のタスクの結果が次の入力になる
- allowed_paths が未設定のタスクがある
```

### ファイル衝突検出（Iron Law）

> **鉄則: allowed_paths が重複するタスクは絶対に並列実行しない。**

並列実行前に以下の手順で衝突を検出する:

1. **TASKS.yaml から running タスクの allowed_paths を取得**
2. **新タスクの allowed_paths と比較**
3. **衝突判定ルール**:
   - 完全一致: `src/auth/` == `src/auth/` → 衝突
   - 包含関係: `src/` contains `src/auth/` → 衝突
   - ファイル vs ディレクトリ: `src/auth/login.ts` in `src/auth/` → 衝突
4. **allowed_paths 未設定 → 他の全タスクと衝突とみなす**

衝突を検出したら:
1. 新タスクの deps に衝突タスクを自動追加
2. TASKS.yaml を更新
3. 台帳に記録（Owner への報告は不要、自動で処理）

### 並列実行の例

```typescript
// ✅ 良い例: 独立したタスクを並列実行
// 1つのメッセージで複数のTaskを呼び出す
Task({ subagent_type: "org-reviewer", prompt: "src/auth/ をレビュー" });
Task({ subagent_type: "org-reviewer", prompt: "src/api/ をレビュー" });
Task({ subagent_type: "org-tdd-coach", prompt: "tests/ のカバレッジを確認" });

// ❌ 悪い例: 依存関係があるのに並列実行
// 設計が決まる前に実装を始めてしまう
Task({ subagent_type: "org-architect", prompt: "API設計" });
Task({ subagent_type: "org-implementer", prompt: "API実装" }); // 設計結果が必要
```

### バックグラウンド実行

長時間タスクは `run_in_background: true` で非同期実行：

```typescript
// E2Eテストをバックグラウンドで実行
Task({
  subagent_type: "org-e2e-runner",
  prompt: "全E2Eテストを実行",
  run_in_background: true
});

// 他の作業を続行...

// 結果を確認
TaskOutput({ task_id: "xxx", block: false });
```

---

## マルチパースペクティブ分析

### 同じコードを複数の視点でレビュー

重要な変更は、異なる専門性を持つエージェントで多角的にレビュー：

```typescript
// セキュリティ + 設計 + テスト の3視点でレビュー
Task({ subagent_type: "org-security-reviewer", prompt: "認証モジュールの脆弱性を確認" });
Task({ subagent_type: "org-reviewer", prompt: "認証モジュールの設計妥当性を確認" });
Task({ subagent_type: "org-tdd-coach", prompt: "認証モジュールのテストカバレッジを確認" });
```

### 視点の組み合わせ例

| シナリオ | 推奨エージェント |
|----------|------------------|
| 新機能リリース前 | `org-reviewer` + `org-security-reviewer` + `org-tdd-coach` |
| リファクタリング | `org-reviewer` + `org-refactor-cleaner` |
| パフォーマンス問題 | `org-reviewer` + `org-build-fixer` |
| 外部API連携 | `org-security-reviewer` + `org-e2e-runner` |

---

## サブエージェント報告の検証

> **Iron Law: サブエージェントの自己報告を信用しない。検証可能な証拠を要求する。**
> **参照元**: obra/superpowers "CRITICAL: Do Not Trust the Report"

### なぜ信用できないか

サブエージェントは以下の傾向がある:
- 部分的な完了を「完了」と報告する
- エッジケースの未実装を省略する
- テストが不十分でも「テスト通過」と報告する
- エラーを「軽微」と過小評価する

### 検証プロトコル

サブエージェントからの報告を受けたら、Manager は以下を実行:

```
1. 報告を読む前に、タスクの acceptance 基準を再確認
2. 報告の「完了」項目を 1 つずつ独立に検証
   - ファイルが実際に存在するか
   - テストが実際に通るか（報告を信じず実行）
   - 変更が acceptance の各項目を満たすか
3. 報告にない問題を探す
   - 変更ファイル一覧と allowed_paths の整合性
   - 意図しない副作用の有無
```

### サブエージェントへの指示テンプレート

サブエージェント起動時に以下を含める:

```
## 報告要件

完了報告には以下を必ず含めること:

1. **変更ファイル一覧**（パス + 変更概要）
2. **acceptance 対応表**（各基準に対して何をしたか）
3. **テスト結果**（コマンド出力を含める）
4. **未解決事項**（あれば正直に報告）
5. **ステータス**: DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED

DONE_WITH_CONCERNS: 完了したが懸念事項がある
NEEDS_CONTEXT: 追加情報が必要
BLOCKED: 進行不能
```

### ステータス別の対応

| ステータス | Manager の対応 |
|-----------|---------------|
| DONE | 検証プロトコルを実行。通過すれば完了 |
| DONE_WITH_CONCERNS | 懸念事項を評価。修正タスクを生成するか判断 |
| NEEDS_CONTEXT | 追加情報を提供して再実行 |
| BLOCKED | ブロッカーを分析。別アプローチを検討 |

---

## コンテキスト管理

### コンテキストウィンドウの効率的な使用

```
1. 必要なファイルだけを読む
   - 全ファイルを読み込まない
   - Glob/Grep で対象を絞ってから Read

2. 大きなファイルは分割して読む
   - Read の offset/limit パラメータを活用
   - 関連部分のみを抽出

3. 要約を活用
   - 長い出力は要点をまとめる
   - 中間結果を DASHBOARD.md に記録
```

### エージェント間の情報共有

```
1. 台帳を経由（推奨）
   - DASHBOARD.md: 現在の状況
   - DECISIONS.md: 設計判断
   - TASKS.yaml: タスク状態

2. 直接引き継ぎ（同一セッション内）
   - 前のエージェントの出力を次の入力に
   - resume パラメータでエージェント再開
```

---

## エラー時の対応パターン

### リトライ戦略

```typescript
// 1回目: Sonnet で試行
Task({ subagent_type: "org-build-fixer", prompt: "ビルドエラーを修正" });

// 失敗した場合: Opus で再試行
Task({
  subagent_type: "org-build-fixer",
  model: "opus",
  prompt: "前回の修正で解決しなかったビルドエラーを分析・修正"
});
```

### エスカレーション

```
単純なエラー → org-build-fixer (Sonnet)
    ↓ 解決しない
複雑なエラー → org-build-fixer (Opus)
    ↓ 解決しない
設計問題の可能性 → org-architect に相談
    ↓ 解決しない
Owner に報告 → OWNER_INBOX.md に質問を追加
```

---

## /org-tick での自動選択

`/org-tick` は以下の優先度でエージェントを自動選択：

| 優先度 | 状況 | エージェント |
|--------|------|--------------|
| P0 | ビルドエラー | `org-build-fixer` |
| P0 | セキュリティアラート | `org-security-reviewer` |
| P1 | 要件不明確 | `org-planner` |
| P1 | 設計判断必要 | `org-architect` |
| P2 | 実装完了 → レビュー | `org-reviewer` + `org-security-reviewer` |
| P2 | カバレッジ不足 | `org-tdd-coach` |
| P3 | 死コード検出 | `org-refactor-cleaner` |
| 常時 | Tick終了時 | `org-scribe` |

---

## 参考資料

- [.claude/agents/](../agents/) - 各エージェントの詳細
- [.claude/commands/org-tick.md](../commands/org-tick.md) - 自動選択ロジック
- [.ai/DASHBOARD.md](../../.ai/DASHBOARD.md) - 現在の状況確認
