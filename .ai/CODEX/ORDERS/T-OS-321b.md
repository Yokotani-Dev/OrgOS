# Work Order: T-OS-321b — OWNER_INBOX Helper Scripts (補完)

## Task
- ID: T-OS-321b (T-OS-321 残作業)
- Title: T-OS-321 で network 切断により未完了の scripts/inbox/ helper を実装
- Role: implementer (Codex)
- Priority: P1

## Allowed Paths (write)
- `scripts/inbox/` (新規ディレクトリ)
- `.ai/CODEX/RESULTS/T-OS-321b.md` (報告書)

## Context

T-OS-321 (OWNER_INBOX を Decision Table に転換) は 2026-05-01 に Codex で実行されたが、network 断により完了前に切断。
**完了済み**: `.ai/OWNER_INBOX.md` を Decision Console format に転換、test 残滓 4 件を archive、`.claude/schemas/decision-card.yaml` 作成。
**未完了**: `scripts/inbox/` 配下の helper scripts。

本タスクはその残作業のみを行う。

## Acceptance Criteria

`scripts/inbox/` 配下に以下を新規作成:

### A1: add-decision.sh
- 引数: `--type <type_a/b/c/d> --decision "..." --recommendation A/B/C --risk low/medium/high --options '[{"key":"A","label":"...","consequence":"...","is_recommended":true},...]' --deadline ISO8601`
- 自動 ID 発番: `D-YYYY-MM-DD-NNN` (NNN は当日連番)
- `.ai/OWNER_INBOX.md` の該当優先度セクションに Decision Card を append
- decision-card.yaml schema validation を行う

### A2: list-pending.sh
- `.ai/OWNER_INBOX.md` から status: pending の Card を抽出
- 表形式で表示 (id / decision / recommendation / risk / deadline / 残日数)
- `--json` フラグで JSON 出力

### A3: expire-old.sh
- deadline 超過の pending Card を検出
- 各 Card の `default_if_no_response` に従い処理:
  - `auto_apply` → status: auto_applied (synthetic Owner approve のみ)
  - `defer_7d` → deadline を 7 日延長
  - `escalate` → 高優先度に昇格
  - `no_op` → status: expired
- 処理結果を log

### A4: archive.sh
- `status: approved/rejected/auto_applied/expired` の Card を `## Archived` セクションへ移動
- 元のセクションから削除

### A5: 検証
- `bash scripts/inbox/list-pending.sh` が動作 (現状 0 件 pending を表示)
- 各スクリプトに `--help` フラグ
- shellcheck / lint pass

## Instructions

1. 既存 `.ai/OWNER_INBOX.md` の format を必ず read してから実装
2. `.claude/schemas/decision-card.yaml` の schema に整合
3. bash + python (yaml parsing) で実装
4. **OS 中核ファイル (CLAUDE.md, AGENTS.md, manager.md, .claude/rules/) は絶対に編集しない**
5. `.ai/OWNER_INBOX.md` の編集は scripts 経由でのみ (本タスクで直接編集しない)

## Report

`.ai/CODEX/RESULTS/T-OS-321b.md` に:
1. 変更ファイル一覧
2. 各スクリプトの動作確認結果
3. ステータス: DONE / DONE_WITH_CONCERNS / BLOCKED

## Handoff Packet (必須)
