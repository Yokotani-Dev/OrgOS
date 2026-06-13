# T-OS-155F Result

## 1. 変更ファイル

- `.claude/schemas/handoff-packet.yaml`
- `.claude/rules/handoff-protocol.md`

## 2. F1-F8 対応表

| ID | 対応内容 |
|---|---|
| F1 | `handoff-packet.yaml` を YAML として全面修正し、`:` を含む説明文字列を quote 化。Ruby/Python の両方で parse 成功を確認。 |
| F2 | `memory_updates` を target 別 `oneOf` 相当の variants に再定義。`USER_PROFILE.facts` / `USER_PROFILE.preferences` / `CAPABILITIES` / `DECISIONS` ごとに payload shape を固定し、scope registry と quarantine 動作を schema / protocol の両方に追加。 |
| F3 | `trace_id` 単独から `trace.request_trace_id` / `trace.span_id` / `trace.attempt` / `trace.parent_span_id` / `trace.resume_of` へ拡張。protocol に request/span/retry/resume の責務を記述。 |
| F4 | `retry_policy` を protocol に追加。`max_attempts: 3`、backoff、`BLOCKED` 停止条件、3 回失敗時の quarantine / escalation / partial salvage を明文化。 |
| F5 | `legacy_result_fallback` を protocol に追加。`packet missing or schema_version absent` を検出条件とし、`2026-06-01` 以降 reject の sunset を明記。 |
| F6 | machine-readable violation 条件として `empty_array_prohibited` と `evidence_required` を protocol に追加。lint script が判定すべき仕様として記述。 |
| F7 | packet 必須フィールドに `schema_version: "1.0"` を追加。protocol 側にも必須と明記。 |
| F8 | OpenAI Agents SDK / LangGraph 向けの trace mapping reference を protocol に追加し、span tree / durable resume との対応を整理。 |

## 3. YAML parse 成功コマンドの出力

```bash
$ ruby -e 'require "yaml"; YAML.load_file(".claude/schemas/handoff-packet.yaml")' && echo OK
OK

$ python3 -c "import yaml; yaml.safe_load(open('.claude/schemas/handoff-packet.yaml'))" && echo OK
OK
```

## 4. ステータス

DONE
