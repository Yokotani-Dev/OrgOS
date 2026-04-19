# T-OS-181F Result

- Status: DONE
- Target: `scripts/session/bind-request.sh`

## 修正内容

- Ruby heredoc 冒頭に `# encoding: utf-8` を追加し、日本語 multibyte 入力を UTF-8 として確実に解釈するよう修正。
- 空入力時は stderr で終了せず、`classification: "empty_request"` の JSON を返すよう変更。
- YAML 読み込みを `Psych::Exception` まで rescue し、壊れた YAML でも JSON を返しつつ `warnings` に内容を格納するよう変更。
- `.ai/TASKS.yaml` / `.ai/GOALS.yaml` 未存在時は空データへフォールバック。

## 実行サンプル

### 1. 日本語入力

```bash
echo "このログから error 抽出して" | bash scripts/session/bind-request.sh
```

```json
{
  "classification": "new_project",
  "related_tasks": [],
  "related_milestones": [],
  "related_decisions": [],
  "suggested_action": "confirm_new_project",
  "response_prefix": "【文脈】既存タスクとは独立。新規プロジェクト化を推奨",
  "warnings": []
}
```

### 2. 既存タスク参照の日本語入力

```bash
echo "T-OS-180 の設計を確認したい" | bash scripts/session/bind-request.sh
```

```json
{
  "classification": "task_continuation",
  "related_tasks": [
    {
      "id": "T-OS-180",
      "title": "[Owner-P0] Session Bootstrap Protocol — 単発チャット問題の根本解決",
      "similarity": 1.0
    }
  ],
  "related_milestones": [],
  "related_decisions": [],
  "suggested_action": "bind",
  "response_prefix": "【文脈】T-OS-180 (running) の延長として処理します",
  "warnings": []
}
```

### 3. 新規作業の日本語入力

```bash
echo "新しいサービス X を作りたい" | bash scripts/session/bind-request.sh
```

```json
{
  "classification": "new_project",
  "related_tasks": [],
  "related_milestones": [],
  "related_decisions": [],
  "suggested_action": "confirm_new_project",
  "response_prefix": "【文脈】既存タスクとは独立。新規プロジェクト化を推奨",
  "warnings": []
}
```

## 追加確認

### ASCII 退行確認

```bash
echo "check the status" | bash scripts/session/bind-request.sh
```

- JSON 出力を確認。エラーなし。

### 空入力

```bash
printf '' | bash scripts/session/bind-request.sh
```

- `classification: "empty_request"` を返すことを確認。

### `.ai/TASKS.yaml` 未存在 fallback

- `/tmp` の隔離ディレクトリで `bind-request.sh` のみ配置し、`.ai/TASKS.yaml` なしで実行。
- JSON 出力を確認。クラッシュなし。

### 壊れた YAML

- `/tmp` の隔離ディレクトリで壊れた `.ai/TASKS.yaml` を用意して実行。
- JSON 出力を確認。
- `warnings` に `Psych::SyntaxError` が格納されることを確認。
