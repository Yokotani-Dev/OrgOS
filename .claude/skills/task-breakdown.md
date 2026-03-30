# タスク分解スキル

> 要件を TASKS.yaml のタスクに分解する手法

> **参照元**: GitHub awesome-copilot breakdown-plan / create-implementation-plan skills

---

## タスク分解の原則

### INVEST 基準

タスクは以下の基準を満たすべき:

| 基準 | 意味 | チェック |
|------|------|---------|
| **I**ndependent | 他タスクに依存せず単独で完了可能 | deps が最小限か？ |
| **N**egotiable | 実装方法に柔軟性がある | 手段を限定しすぎていないか？ |
| **V**aluable | ユーザーまたはシステムに価値を提供 | 完了時に何が動くようになるか？ |
| **E**stimable | サイズが見積もり可能 | 不明点が多すぎないか？ |
| **S**mall | 1 Tick（1セッション）で完了可能 | 分割すべきか？ |
| **T**estable | 完了を客観的に確認可能 | acceptance が明確か？ |

---

## タスクサイズの見積もり

### T-Shirt サイズ

| サイズ | 目安 | TASKS.yaml での扱い |
|--------|------|-------------------|
| **XS** | 1ファイル、10行以内の変更 | 即実行、同一 Tick |
| **S** | 1-2ファイル、50行以内 | 1タスク、同一 Tick |
| **M** | 3-5ファイル、200行以内 | 1タスク、専用 Tick |
| **L** | 5+ファイル、500行以内 | 2-3タスクに分割 |
| **XL** | モジュール横断、500行超 | Epic として分解必須 |

### 分割の判断基準

```
タスクが以下に該当 → 分割する:

✅ 1 Tick で完了しない見込み
✅ allowed_paths が 3 ディレクトリ以上
✅ acceptance が 5 項目以上
✅ 「〜と〜と〜」のように AND で繋がる
✅ 異なるスキルセットが必要（UI + API + DB）
```

---

## 分解パターン

### パターン 1: レイヤー分割

フルスタック機能をレイヤーごとに分割。

```yaml
# ❌ 悪い例: 1タスクに全レイヤー
- id: T-010
  title: "ユーザー登録機能の実装"
  acceptance:
    - "DBスキーマ作成"
    - "API実装"
    - "フロントエンド実装"
    - "テスト作成"
    - "E2Eテスト"

# ✅ 良い例: レイヤーごとに分割
- id: T-010
  title: "ユーザー登録: DBスキーマ + マイグレーション"
  deps: []
  allowed_paths: ["prisma/", "src/db/"]
  acceptance:
    - "users テーブルが作成される"
    - "マイグレーションが通る"

- id: T-011
  title: "ユーザー登録: API エンドポイント"
  deps: ["T-010"]
  allowed_paths: ["src/api/", "src/services/"]
  acceptance:
    - "POST /api/users が 201 を返す"
    - "バリデーションエラーで 400 を返す"
    - "重複メールで 409 を返す"

- id: T-012
  title: "ユーザー登録: フロントエンド"
  deps: ["T-011"]
  allowed_paths: ["src/components/", "src/app/"]
  acceptance:
    - "登録フォームが表示される"
    - "成功時にダッシュボードへリダイレクト"
    - "エラー時にインラインメッセージ表示"
```

### パターン 2: フロー分割

ユーザーフローの各ステップを独立タスクに。

```yaml
# 認証フロー → 3タスクに分割
- id: T-020
  title: "認証: ログイン機能"
  deps: []
  spec_refs: ["REQ-001"]

- id: T-021
  title: "認証: パスワードリセット"
  deps: ["T-020"]  # ログインの基盤が必要
  spec_refs: ["REQ-002"]

- id: T-022
  title: "認証: ソーシャルログイン（OAuth）"
  deps: ["T-020"]  # ログインの基盤が必要
  spec_refs: ["REQ-003"]
```

### パターン 3: リスク分割

不確実性の高い部分を先に分離。

```yaml
# 技術検証（スパイク）→ 実装 の2段階
- id: T-030
  title: "スパイク: WebSocket リアルタイム通知の技術検証"
  deps: []
  acceptance:
    - "WebSocket 接続が確立できる"
    - "メッセージの送受信が動作する"
    - "DECISIONS.md に技術選定を記録"

- id: T-031
  title: "リアルタイム通知の実装"
  deps: ["T-030"]  # スパイク完了後
  acceptance:
    - "通知がリアルタイムで届く"
    - "再接続ロジックが動作する"
```

---

## 依存関係（deps）の設計

### 原則

```
deps は最小限にする。不要な依存は並列実行を妨げる。

✅ 良い deps:
  T-011 deps: ["T-010"]  # API は DB スキーマに依存

❌ 悪い deps:
  T-012 deps: ["T-010", "T-011"]  # T-011 が T-010 に依存するなら T-010 は不要
  （推移的依存は書かない）
```

### 依存関係の種類

| 種類 | 説明 | 例 |
|------|------|-----|
| **技術的依存** | コードレベルで前のタスクが必要 | API → DB スキーマ |
| **データ依存** | 前のタスクの出力が入力になる | テスト → 実装 |
| **環境依存** | インフラ・設定が必要 | デプロイ → 環境構築 |

### 並列実行可能な組み合わせ

```
DB スキーマ ──→ API 実装 ──→ 統合テスト
                              ↑
UI モック ───→ UI 実装 ──────┘

↑ DB スキーマ と UI モック は並列実行可能
```

---

## TASKS.yaml エントリの書き方

### 必須フィールド

```yaml
- id: T-XXX                    # 一意の ID
  title: "動詞: 具体的な成果物"  # 何が完了するか明確に
  status: queued               # queued | running | blocked | review | done
  deps: ["T-YYY"]             # 最小限の依存
  owner_role: "codex-implementer"  # 実行者
  allowed_paths: ["src/auth/"] # 変更対象ディレクトリ
  acceptance:                  # 完了条件（Given-When-Then 推奨）
    - "POST /api/auth/login が 200 を返す"
    - "無効な認証情報で 401 を返す"
```

### タイトルの書き方

```
// ❌ 悪い例: 曖昧
- title: "認証機能"
- title: "バグ修正"
- title: "改善"

// ✅ 良い例: 動詞 + 具体的な成果物
- title: "実装: JWT ログインエンドポイント"
- title: "修正: パスワードリセットメールが送信されない問題"
- title: "リファクタ: UserService を Repository パターンに分離"
- title: "スパイク: Stripe 決済 API の技術検証"
```

### acceptance の書き方

```yaml
# ❌ 悪い例: 曖昧
acceptance:
  - "動作する"
  - "テストが通る"

# ✅ 良い例: 検証可能
acceptance:
  - "POST /api/users が CreateUserReq を受け取り 201 + User を返す"
  - "email 重複時に 409 ConflictError を返す"
  - "Unit テストカバレッジ 80% 以上"
  - "REQ-001 の Given-When-Then を満たす"
```

---

## Epic の分解手順

大きな機能を段階的に分解するフロー:

```
1. SPEC.md の要件（REQ-XXX）をグルーピング
   → 関連する REQ をまとめて「機能グループ」を特定

2. 各機能グループを T-Shirt サイズで見積もり
   → XL 以上なら更に分割

3. レイヤー分割 or フロー分割 or リスク分割を適用
   → 各タスクが INVEST 基準を満たすか確認

4. deps を設計
   → 並列実行可能な部分を最大化

5. TASKS.yaml に登録
   → allowed_paths の衝突がないか確認
   → spec_refs で仕様書を逆参照
```

---

## Iron Law

> タスク分解の鉄則。例外なし。

1. **「TBD」「TODO」「後で決める」を acceptance に書かない** - 検証できない条件は条件ではない
2. **タスクサイズ L 以上を登録しない** - 必ず M 以下に分割してから登録する
3. **acceptance は Given-When-Then または検証可能な形式のみ** - 「動作する」「正しく処理される」は禁止

---

## 計画粒度ガイド

> obra/superpowers の「2-5分ステップ」思想を OrgOS に適用

### 原則: 各タスクの acceptance 条件は具体的で即座に検証可能

```
❌ 悪い例（曖昧）:
  acceptance:
    - "認証機能が動作する"
    - "エラーハンドリングが適切"

✅ 良い例（検証可能）:
  acceptance:
    - "POST /api/auth/login に有効な credentials → 200 + JWT token"
    - "無効な password → 401 + { error: 'Invalid credentials' }"
    - "存在しない email → 401（ユーザー列挙を防ぐため同じエラー）"
```

### acceptance 品質チェック

各条件が以下を満たすか確認:

| チェック | 説明 |
|---------|------|
| **入力が明確** | 何を与えるか具体的に記述されている |
| **出力が明確** | 何が返るか（ステータスコード、レスポンス形式）が記述されている |
| **自動検証可能** | テストコードで検証できる形式である |
| **曖昧語がない** | 「適切」「正しく」「うまく」を含まない |

---

## チェックリスト

タスク分解完了時に確認:

- [ ] 各タスクが INVEST 基準を満たしている
- [ ] タスクサイズが M 以下（L 以上は分割済み）
- [ ] deps が最小限（推移的依存を除去）
- [ ] allowed_paths が重複していない（並列実行可能）
- [ ] acceptance が検証可能な形式で記述されている（「TBD」「TODO」なし）
- [ ] すべての P0/P1 要件（REQ-XXX）がタスクでカバーされている
- [ ] タイトルが「動詞: 具体的な成果物」形式
- [ ] acceptance に曖昧語（「適切」「正しく」「うまく」）がない

---

## 参考資料

- [GitHub breakdown-plan](https://github.com/github/awesome-copilot)
- [TASKS.yaml](../../.ai/TASKS.yaml)
- [requirements-specification.md](requirements-specification.md)
- [.claude/rules/project-flow.md](../rules/project-flow.md)
