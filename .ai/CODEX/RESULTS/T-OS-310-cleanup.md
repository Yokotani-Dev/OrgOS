# T-OS-310-cleanup Result

## Deleted File Record: `.claude/agents/org-implementer.md` First 30 Lines

```markdown
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
```

## Changes

- Deleted `.claude/agents/org-implementer.md`.
- Removed `.claude/agents/org-implementer.md` from `.orgos-manifest.yaml` publish targets.
- Updated `.orgos-manifest.yaml` publish Rules block from 13 listed rule files to 23 tracked rule files.
- Added a top-level `.orgos-manifest.yaml` `rules:` metadata list with the requested 23 rule names.

## Manifest Rule Counts

- Before: 13 rule file paths in `publish` (no top-level `rules:` section present). Work Order context expected 9.
- After: 23 rule file paths in `publish`.
- After: 23 entries in top-level `rules:`.

## Rule Inventory Check

Command requested:

```bash
ls .claude/rules/*.md | xargs -n1 basename | sed 's/\.md$//' | sort
```

Observed filesystem result: 24 files.

```text
agent-coordination
ai-driven-development
authority-layer
capability-preflight
coherence-mode
cross-session-consistency
design-documentation
eval-loop
handoff-protocol
literacy-adaptation
memory-lifecycle
next-step-guidance
output-management
owner-task-minimization
patterns
performance
plan-sync
proactive-mode
project-flow
rationalization-prevention
request-intake-loop
session-bootstrap
session-management
user-journey-sync
```

Tracked rule files are 23 and match the Work Order rule list. The extra filesystem entry is untracked:

```text
.claude/rules/user-journey-sync.md
```

Recommendation: create a separate task to decide whether `user-journey-sync` should be formalized in the manifest and release set, or removed from the working tree.

## Dead Reference Grep

Command:

```bash
rg -n "org-implementer" -g '!.env' -g '!.env.*' -g '!secrets/**'
```

Result before edits:

```text
requirements.md:246:    org-implementer.md
requirements.md:1133:> `.claude/agents/org-implementer.md`
requirements.md:1137:name: org-implementer
```

These appear to be historical/dead references in `requirements.md`. This task did not edit them because `requirements.md` is outside the allowed write paths. Recommendation: handle cleanup or archival clarification in a separate task.

## Verification

- `.claude/agents/org-implementer.md` removed.
- `.orgos-manifest.yaml` no longer lists `org-implementer.md`.
- `.orgos-manifest.yaml` has 23 top-level `rules:` entries.
- `.orgos-manifest.yaml` has 23 tracked rule file paths in `publish`.
- YAML validation: pending final command run.

## Handoff Packet

```yaml
task_id: T-OS-310-cleanup
agent: codex-worker
status: DONE_WITH_CONCERNS
completed_at: 2026-05-01
trace_id: T-OS-310-cleanup-codex
changed_files:
  - .claude/agents/org-implementer.md
  - .orgos-manifest.yaml
  - .ai/CODEX/RESULTS/T-OS-310-cleanup.md
assumptions:
  - The Work Order's 23-rule list corresponds to tracked rules.
  - The untracked user-journey-sync rule is outside this cleanup scope.
decisions_made:
  - Removed deprecated org-implementer from the publish manifest together with the physical file.
  - Updated manifest rules to the requested tracked 23-rule set.
unresolved_questions:
  - Should untracked .claude/rules/user-journey-sync.md become an official 24th rule?
downstream_impacts:
  - /org-import and publish manifests no longer distribute the deprecated org-implementer agent.
  - The tracked rule set is fully represented in the manifest.
memory_updates: []
verification:
  - final verification commands pending
```

## Status

DONE_WITH_CONCERNS
