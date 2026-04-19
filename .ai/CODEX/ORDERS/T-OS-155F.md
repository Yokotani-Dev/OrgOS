# Work Order: T-OS-155F (Fix from T-OS-155R review)

## Task
- ID: T-OS-155F
- Title: T-OS-155 Handoff Packet の CRITICAL 修正 (YAML parse + memory_updates 安全化 + その他)
- Role: implementer
- Priority: P0

## Allowed Paths
- `.claude/schemas/handoff-packet.yaml`
- `.claude/rules/handoff-protocol.md`
- `.ai/CODEX/RESULTS/T-OS-155F.md`

## Dependencies
- T-OS-155: done
- T-OS-155R: CHANGES_REQUESTED (× 差し戻し判定)

## Context

T-OS-155R で **× 差し戻し** 判定。最重要の schema YAML parse エラーを含む。
レビュー原文: `.ai/CODEX/RESULTS/T-OS-155R.md`

### 検証済みエラー
```
ruby -e 'require "yaml"; YAML.load_file(".claude/schemas/handoff-packet.yaml")'
→ Psych::SyntaxError: mapping values are not allowed in this context at line 39 column 34
```

## Acceptance Criteria

### F1 [HIGH→CRITICAL]: YAML parse エラー修正
問題: handoff-packet.yaml が parse できない。schema SSOT として機能しない。
修正:
- `note:` 値など `:` を含む文字列を全て quote する
- `ruby -e 'require "yaml"; YAML.load_file(".claude/schemas/handoff-packet.yaml")'` で parse 成功を確認
- `python3 -c "import yaml; yaml.safe_load(open('.claude/schemas/handoff-packet.yaml'))"` でも確認

### F2 [HIGH]: memory_updates の安全化
問題: `content: any` / `scope: string` のみで宛先別 payload 制約がない。誤 packet で shared memory/decision ledger を壊し得る。
修正:
- schema で target 別 payload schema を oneOf 定義:
  ```yaml
  memory_updates:
    - oneOf:
        - target: USER_PROFILE.facts
          operation: capture|update|retire|promote
          payload:  # fact 形式に準拠
            id: string
            type: enum[...]
            value_ref: any
            scope: string
            ...
        - target: CAPABILITIES
          operation: update
          payload:
            capability_id: string
            fields_to_update: map
        - target: DECISIONS
          operation: append
          payload:
            decision_id: string
            content: string
  ```
- scope registry 定義 (許可された scope 値のリスト)
- validation failure 時の動作: `quarantine` (一時格納) → Manager レビュー → apply/discard
- handoff-protocol.md に scope registry と validation 手順を記述

### F3 [MEDIUM]: trace_id 粒度の分離
問題: 単一 trace_id で span / handoff / retry attempt / state resume を区別できない。
修正:
- schema に追加:
  ```yaml
  trace:
    request_trace_id: string  # 依頼単位の最上位 ID
    span_id: string           # 個別 subagent の実行 span
    attempt: int              # リトライ番号
    parent_span_id: string    # 親 span (handoff chain で親子関係)
    resume_of: string | null  # 再開元の span_id (durable execution 対応)
  ```
- handoff-protocol.md の trace セクションを OpenAI Agents SDK / LangGraph 粒度に合わせて拡張

### F4 [MEDIUM]: retry policy 状態遷移
問題: 3 回リトライの停止条件・backoff・escalation なし。
修正: handoff-protocol.md に以下を明記:
```yaml
retry_policy:
  max_attempts: 3
  backoff:
    - attempt_1: 0s (immediate)
    - attempt_2: 30s
    - attempt_3: 120s
  stop_conditions:
    - status: BLOCKED (即停止、retry 不要)
    - 3 回全て packet 不完全 → 対象 subagent を quarantine
  escalation:
    - 3 回失敗時: DECISIONS.md に ISSUE-HPKT-XXX として記録
    - Owner への escalation: 緊急時のみ (Iron Law 違反レベル)
  partial_salvage:
    - packet 不完全でも `changed_files` / `verification` が揃っていれば部分適用を検討
```

### F5 [MEDIUM]: legacy_result fallback
問題: 非構造化 Markdown の既存 Result の移行ルール不足。
修正:
- handoff-protocol.md に:
  ```yaml
  legacy_result_fallback:
    detection: "packet missing or schema_version absent"
    behavior: "parse best-effort from Markdown, extract Status/Changed Files/Notes"
    migration_sunset: "2026-06-01 以降は legacy_result を reject"
  ```

### F6 [MEDIUM]: machine-readable violation detection
問題: violation 検出が人手判断依存。
修正: handoff-protocol.md の違反リストに具体条件を追加:
- `empty_array_prohibited: [assumptions, decisions_made]` (空配列は Iron Law 違反)
- `evidence_required: verification.tests_run or verification.eval_results is non-empty for non-trivial tasks`
- これらを lint script の仕様として記述 (実装は T-OS-155G or 将来)

### F7 [LOW]: schema_version フィールド
修正: packet に `schema_version: "1.0"` を必須追加。v1/v2 共存の移行パスを確保。

### F8 [LOW]: tracing 設計の参照
修正: handoff-protocol.md に OpenAI Agents SDK / LangGraph の span tree / durable resume への対応表を簡潔に追加。

## Instructions

1. T-OS-155R (`.ai/CODEX/RESULTS/T-OS-155R.md`) を精読
2. まず **F1 (YAML parse)** を最優先で修正し、parse 成功を確認
3. F2-F8 を順次適用
4. 修正後に以下のコマンドで検証:
   ```bash
   ruby -e 'require "yaml"; YAML.load_file(".claude/schemas/handoff-packet.yaml")' && echo OK
   python3 -c "import yaml; yaml.safe_load(open('.claude/schemas/handoff-packet.yaml'))" && echo OK
   ```
5. **重要**: 他ファイル編集禁止

## Reference
- `.ai/CODEX/RESULTS/T-OS-155R.md` - レビュー指摘 SSOT
- `.claude/schemas/handoff-packet.yaml` - 対象
- `.claude/rules/handoff-protocol.md` - 対象

## Report

`.ai/CODEX/RESULTS/T-OS-155F.md`:
1. 変更ファイル
2. F1-F8 対応表
3. YAML parse 成功コマンドの出力
4. ステータス: DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
