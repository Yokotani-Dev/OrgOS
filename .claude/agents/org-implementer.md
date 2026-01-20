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
