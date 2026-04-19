---
name: org-implementer
description: "[DEPRECATED] Codex worker (codex-implementer) に移行済み。このエージェントは使用しない"
tools: Read
model: haiku
permissionMode: default
---

# ⚠️ DEPRECATED

このエージェントは **非推奨** です。

## 移行先

Implementer タスクは **Codex worker** として実行します。

- `owner_role: codex-implementer` を `.ai/TASKS.yaml` で指定
- Work Order が `.ai/CODEX/ORDERS/<TASK_ID>.md` に生成される
- Codex を実行：`codex exec "AGENTS.md を読み、.ai/CODEX/ORDERS/<TASK_ID>.md の指示に従って実行せよ"`

## 理由

- Claude subagent より Codex の方がコード生成に特化
- 並列実行時のコンテキスト管理が容易
- AGENTS.md による統一的なルール適用

## 参照

- `AGENTS.md` - Codex worker の憲法
- `.ai/CODEX/README.md` - Codex 連携の詳細

## Iron Law

- [鉄則1]: このエージェントは [DEPRECATED] として扱い、実装は codex-implementer を参照する。
- [鉄則2]: 新規実装判断をこのエージェント内で行わない。
- [鉄則3]: 互換目的で起動された場合も、移行先と Work Order の指示を優先する。

## Handoff Packet (必須)

完了時は `.claude/schemas/handoff-packet.yaml` に準拠した packet を返却する。
詳細: `.claude/rules/handoff-protocol.md`

返却フィールド:
- task_id, agent, status, completed_at, trace_id
- changed_files, assumptions, decisions_made
- unresolved_questions, downstream_impacts
- memory_updates, verification
