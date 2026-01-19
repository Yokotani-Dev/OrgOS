# /org-codex - Codex タスク実行コマンド

Codex worker に委任されたタスクを実行する。
`/org-tick` で Codex タスクが検出された場合、このコマンドの実行を案内する。

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

1. **CONTROL.yaml の `codex.approval_mode` を確認**
   - `suggest`: 提案のみ（デフォルト、安全）
   - `auto-edit`: 編集は自動、実行は確認
   - `full-auto`: 全自動（危険）

2. **Codex コマンドを生成**:
   ```bash
   codex exec --approval-mode <MODE> "AGENTS.md を読み、.ai/CODEX/ORDERS/<TASK_ID>.md の指示に従って実行せよ"
   ```

3. **実行方法を Owner に提示**:
   - approval_mode が `full-auto` の場合のみ自動実行可能
   - それ以外は Owner に実行を促す（対話的な承認が必要なため）

### Step 4: 実行（full-auto モードの場合）

`codex.auto_exec: true` かつ `approval_mode: full-auto` の場合：

1. Bash で `codex exec` を実行
2. 結果を待機（タイムアウト: 10分）
3. `.ai/CODEX/RESULTS/<TASK_ID>.md` を確認
4. 成功時: TASKS.yaml のステータスを `review` に更新
5. 失敗時: ステータスを `blocked` に更新、エラー内容を記録

### Step 5: 手動実行の案内（suggest/auto-edit モードの場合）

Owner に以下を表示：

```
## Codex 実行待ち

以下のコマンドをターミナルで実行してください：

### T-XXX (<タスクタイトル>)

```bash
codex exec --approval-mode suggest "AGENTS.md を読み、.ai/CODEX/ORDERS/T-XXX.md の指示に従って実行せよ"
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

approval_mode: `suggest` のため、手動実行が必要です。

以下のコマンドをターミナルで実行してください：

**T-010:**
```bash
codex exec --approval-mode suggest "AGENTS.md を読み、.ai/CODEX/ORDERS/T-010.md の指示に従って実行せよ"
```

**T-020:**
```bash
codex exec --approval-mode suggest "AGENTS.md を読み、.ai/CODEX/ORDERS/T-020.md の指示に従って実行せよ"
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

## 注意事項

- Codex がインストールされていない場合は先にインストールが必要
- `approval_mode: full-auto` は危険。テスト環境以外では `suggest` 推奨
- 結果は `.ai/CODEX/RESULTS/<TASK_ID>.md` に出力される
- レビュータスクは Review Packet (`.ai/REVIEW/PACKETS/<TASK_ID>.md`) も参照する
