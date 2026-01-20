# /org-codex - Codex タスク実行コマンド

OpenAI Codex CLI を使って、Codex worker に委任されたタスクを実行する。
`/org-tick` で Codex タスクが検出された場合、このコマンドの実行を案内する。

---

## 前提条件

- OpenAI Codex CLI がインストールされていること
  ```bash
  npm i -g @openai/codex
  # または
  brew install --cask codex
  ```
- `codex login` で認証済みであること

---

## 引数

- `<task_id>` (オプション): 特定のタスクIDを指定。省略時は実行待ちの全 Codex タスクを処理

## 実行手順

### Step 1: Codex タスクの検出

`.ai/TASKS.yaml` を読み、以下の条件に合致するタスクを抽出：

```yaml
# 条件
- owner_role: "codex-implementer" または "codex-reviewer"
- status: "queued" または "running"
- deps: すべて "done"
```

引数で `<task_id>` が指定されていれば、そのタスクのみ対象とする。

### Step 2: Work Order の確認

各タスクについて `.ai/CODEX/ORDERS/<TASK_ID>.md` が存在するか確認。

**存在しない場合**:
- エラー: 「Work Order が見つかりません。`/org-tick` で生成してください」

**存在する場合**:
- Work Order の内容を表示

### Step 3: Codex 実行コマンドの生成と実行

タスクごとに以下を実行：

1. **CONTROL.yaml の `codex.sandbox` と `codex.approval` を確認**

   **sandbox オプション** (`-s, --sandbox`):
   - `read-only`: 読み取りのみ（最も安全、デフォルト）
   - `workspace-write`: ワークスペース内の書き込み許可
   - `danger-full-access`: フルアクセス（危険）

   **approval オプション** (`-a, --ask-for-approval`):
   - `untrusted`: 毎回確認（最も安全）
   - `on-failure`: 失敗時のみ確認
   - `on-request`: 要求時のみ確認
   - `never`: 確認なし（危険）

   **ショートカット**:
   - `--full-auto`: `--ask-for-approval on-request --sandbox workspace-write` と同等

2. **Codex コマンドを生成**:

   **標準モード（推奨）**:
   ```bash
   codex exec "AGENTS.md を読み、.ai/CODEX/ORDERS/<TASK_ID>.md の指示に従って実行せよ"
   ```

   **自動編集モード**:
   ```bash
   codex exec --full-auto "AGENTS.md を読み、.ai/CODEX/ORDERS/<TASK_ID>.md の指示に従って実行せよ"
   ```

   **完全自動モード（CI環境のみ）**:
   ```bash
   codex exec --ask-for-approval never --sandbox workspace-write "AGENTS.md を読み、.ai/CODEX/ORDERS/<TASK_ID>.md の指示に従って実行せよ"
   ```

3. **実行方法を Owner に提示**:
   - `auto_exec: true` かつ適切な approval 設定の場合のみ自動実行可能
   - それ以外は Owner に実行を促す（対話的な承認が必要なため）

### Step 4: 実行（auto_exec: true の場合）

`codex.auto_exec: true` の場合：

1. Bash で `codex exec` を実行
2. 結果を待機（タイムアウト: 10分）
3. `.ai/CODEX/RESULTS/<TASK_ID>.md` を確認
4. 成功時: TASKS.yaml のステータスを `review` に更新
5. 失敗時: ステータスを `blocked` に更新、エラー内容を記録

### Step 5: 手動実行の案内（auto_exec: false の場合）

Owner に以下を表示：

```
## Codex 実行待ち

以下のコマンドをターミナルで実行してください：

### T-XXX (<タスクタイトル>)

```bash
codex exec "AGENTS.md を読み、.ai/CODEX/ORDERS/T-XXX.md の指示に従って実行せよ"
```

または、自動編集を許可する場合：

```bash
codex exec --full-auto "AGENTS.md を読み、.ai/CODEX/ORDERS/T-XXX.md の指示に従って実行せよ"
```

実行後、結果が `.ai/CODEX/RESULTS/T-XXX.md` に出力されたら `/org-tick` で次のステップへ進みます。
```

---

## 出力例

### Codex タスクがある場合

```
## /org-codex - Codex タスク実行

### 実行待ちタスク

| ID | Title | Role | Status |
|----|-------|------|--------|
| T-010 | Logic Apps 機能マッピング | codex-implementer | queued |
| T-020 | Graph API権限の洗い出し | codex-implementer | queued |

### 実行方法

`auto_exec: false` のため、手動実行が必要です。

以下のコマンドをターミナルで実行してください：

**T-010:**
```bash
codex exec "AGENTS.md を読み、.ai/CODEX/ORDERS/T-010.md の指示に従って実行せよ"
```

**T-020:**
```bash
codex exec "AGENTS.md を読み、.ai/CODEX/ORDERS/T-020.md の指示に従って実行せよ"
```

実行完了後、`/org-tick` で結果を確認してください。
```

### Codex タスクがない場合

```
## /org-codex - Codex タスク実行

実行待ちの Codex タスクはありません。
`/org-tick` でプロジェクトを進めてください。
```

---

## TASKS.yaml の owner_role 設定

Codex で実行するタスクは以下の role を設定：

```yaml
tasks:
  - id: T-010
    title: "実装タスク"
    status: queued
    deps: ["T-001"]
    owner_role: "codex-implementer"  # ← Codex で実装
    allowed_paths: ["src/", "tests/"]
    acceptance:
      - "機能が実装されている"
      - "テストがパスする"

  - id: T-010-review
    title: "T-010 のレビュー"
    status: queued
    deps: ["T-010"]
    owner_role: "codex-reviewer"  # ← Codex でレビュー
    allowed_paths: ["src/", "tests/"]
    acceptance:
      - "コード品質OK"
      - "セキュリティチェックOK"
```

---

## CONTROL.yaml の codex 設定

```yaml
codex:
  # true: Manager が codex exec を自動実行
  # false: Ownerが手動で codex exec を実行（デフォルト、推奨）
  auto_exec: false

  # sandbox ポリシー
  # read-only: 読み取りのみ（最も安全）
  # workspace-write: ワークスペース書き込み許可（推奨）
  # danger-full-access: フルアクセス（危険）
  sandbox: "workspace-write"

  # 承認ポリシー
  # untrusted: 毎回確認（最も安全）
  # on-failure: 失敗時のみ確認
  # on-request: 要求時のみ確認（推奨）
  # never: 確認なし（CI環境のみ）
  approval: "on-request"
```

---

## 注意事項

- Codex CLI がインストールされていない場合: `npm i -g @openai/codex` または `brew install --cask codex`
- 認証が必要: `codex login` を実行
- `--ask-for-approval never` は危険。CI環境以外では使用しない
- 結果は `.ai/CODEX/RESULTS/<TASK_ID>.md` に出力される
- レビュータスクは Review Packet (`.ai/REVIEW/PACKETS/<TASK_ID>.md`) も参照する
- 詳細: https://developers.openai.com/codex/cli/
