# Work Order: T-OS-310-cleanup — Deprecated agent 削除 + manifest 完全化

## Task
- ID: T-OS-310-cleanup (Phase 1 安全タスクとして先行実施)
- Title: org-implementer.md (DEPRECATED) を物理削除し、.orgos-manifest.yaml を全 23 rule に更新
- Role: implementer (Codex)
- Priority: P1

## Allowed Paths (write)
- `.claude/agents/org-implementer.md` (削除)
- `.orgos-manifest.yaml` (rule リスト更新)
- `.ai/CODEX/RESULTS/T-OS-310-cleanup.md` (報告書)

その他のすべてのパスは **read-only**。

## Context

Phase 1 で発見された ISS-CLD-007: `.claude/agents/org-implementer.md` は冒頭に「⚠️ DEPRECATED」と明記され、Codex Worker (`AGENTS.md` + `CODEX_WORKER_GUIDE.md`) に移行済みだが物理ファイルが残存している。新規参加者が誤って参照するリスクがあり、削除すべき。

同時に Phase 1 の ISS-CLD-023: `.orgos-manifest.yaml` が 23 rule 中 9 のみ列挙しており、`/org-import` で残り 14 rule が配布されない問題も解消する。

## Acceptance Criteria

### A1: org-implementer.md の物理削除
- `.claude/agents/org-implementer.md` を削除
- 他のファイル (TASKS.yaml の `owner_role`, manager.md の参照等) で `org-implementer` を参照している箇所がないか grep 確認
  - もし参照箇所があればそれが死参照 (古い記述) であることを report に記載するのみ。**rule / manager.md / TASKS.yaml の編集は本タスクでは禁止**
- 削除前に内容を `.ai/CODEX/RESULTS/T-OS-310-cleanup.md` の冒頭に記録 (歴史保存)

### A2: .orgos-manifest.yaml に全 23 rule を列挙
現在の `.orgos-manifest.yaml` の `rules:` セクションを以下に更新 (アルファベット順):

```yaml
rules:
  - agent-coordination
  - ai-driven-development
  - authority-layer
  - capability-preflight
  - coherence-mode
  - cross-session-consistency
  - design-documentation
  - eval-loop
  - handoff-protocol
  - literacy-adaptation
  - memory-lifecycle
  - next-step-guidance
  - output-management
  - owner-task-minimization
  - patterns
  - performance
  - plan-sync
  - proactive-mode
  - project-flow
  - rationalization-prevention
  - request-intake-loop
  - session-bootstrap
  - session-management
```

(23 rule。`.claude/rules/*.md` 一覧と一致するはず。実際に `ls .claude/rules/*.md` で照合し、もし差分があれば報告)

### A3: manifest の他セクションも整合確認 (read-only)
- `agents:` セクションに `org-implementer` が含まれていれば削除候補 (本タスクで削除可)
- それ以外のセクション (skills / commands / schemas) は手を付けない

### A4: 検証
- `.claude/agents/` に `org-implementer.md` が存在しないこと
- `.orgos-manifest.yaml` の `rules:` が 23 件で `.claude/rules/*.md` と一致すること
- `.orgos-manifest.yaml` が valid YAML であること

## Instructions

1. 削除前に `cat .claude/agents/org-implementer.md` の内容を CODEX_RESULTS の冒頭に記録
2. `ls .claude/rules/*.md | xargs -n1 basename | sed 's/\\.md$//' | sort` で実体 23 rule を取得
3. `.orgos-manifest.yaml` を必ず read してから編集 (既存の他セクションを壊さないため)
4. **OS 中核ファイル (CLAUDE.md, AGENTS.md, manager.md, .claude/rules/, .claude/schemas/) は絶対に編集しない**
5. grep で死参照を探すのみ、見つかっても本タスクでは編集しない (別タスク化を推奨として report)

## Report

`.ai/CODEX/RESULTS/T-OS-310-cleanup.md` に:
1. 削除した org-implementer.md の冒頭 30 行 (記録)
2. manifest 更新前後の rule 件数 (Before 9 / After 23)
3. 死参照 grep 結果 (もしあれば、別タスク化推奨)
4. ステータス: DONE / DONE_WITH_CONCERNS / BLOCKED

## Handoff Packet (必須)
