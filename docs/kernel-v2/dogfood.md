# T-OS-418 Manager Dogfood Execution Log

**Date**: 2026-05-16
**Actor**: Manager (Claude Opus 4.7)
**Lease**: LS-20260515T184029Z-T-OS-418-c36c80af
**Branch**: task/T-OS-418-dogfood

## Purpose

5th-round GPT-5.5 Pro Q25 dry-run の要件:
> 必須。enforce flip 前に Manager 自身が新フローで 1 commit 完走するまで、enforce してはいけない。

これまで Manager は kernel を実装したが、自分では新フローを使ってこなかった (raw `git commit` 9 回、手動 `cp` 5 回、active lease なし Edit 多数)。本 dogfood で初めて Manager が **integrator gate + lease registry + artifact preservation の end-to-end フロー** を実行する。

## Step results

### Step 1: Lease acquisition ✓
```
$ bash scripts/org/acquire-lease.sh --task-id T-OS-418 --actor-role manager --allowed-paths "docs/kernel-v2/" ...
LS-20260515T184029Z-T-OS-418-c36c80af
```
Lease file created at `.ai/leases/LS-20260515T184029Z-T-OS-418-c36c80af.json`.

### Step 2: Edit within lease ✓
This very file (`docs/kernel-v2/dogfood.md`) is being written within the lease's `allowed_paths: docs/kernel-v2/`.

### Step 3-7: (filled by subsequent steps)

## Findings

(Updated after Steps 3-7 complete)

## Conclusion

(Updated at end)

### Step 6: Integrator commit ✗ **BUG DISCOVERED**

```
$ bash scripts/org/integrator-commit.sh --task-id T-OS-418
changed path is outside allowed_paths: .ai/queue/integration/processing/
failed queue item: .ai/queue/integration/failed/T-OS-418.20260515T184114Z.json
```

**Root cause**: integrator-commit.sh moves queue item from pending/ to processing/ BEFORE running its allowed_paths check. The `git status --porcelain` scan picks up:
- `D .ai/queue/integration/pending/T-OS-418.json` (the move source)
- `?? .ai/queue/integration/processing/T-OS-418.json` (the move target)

These are integrator-internal state changes, NOT the actual diff being committed. But the check treats them as user changes and fails because lease.allowed_paths = `docs/kernel-v2/` doesn't cover `.ai/queue/`.

**Fix needed (T-OS-422)**: changed_files collector in integrator-commit.sh must filter out `.ai/queue/integration/**` (integrator-managed paths).

This is **exactly the failure mode GPT-5.5 Pro predicted in Q26 / Q29**: "test pass するが real-world で抜ける". KRT-007 passed because the test fixture doesn't have a queue item movement happening during the test (queue paths are in test temp repo, not the integrator's own internal state).

### Finding: Dogfood succeeded in finding a real bug

The dogfood exercise revealed an Iron Law-level integrator bug that 35+ KRT tests did not detect. This is **the dogfood working as intended**.

## RETRY after T-OS-422 + T-OS-423 (INTERNAL_PATHS filter expansion)

### Step 1 (retry): Lease acquisition
Lease re-acquired: LS-20260516T001928Z-T-OS-418-031ac9d6
