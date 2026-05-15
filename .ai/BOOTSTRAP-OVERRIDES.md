# Bootstrap Overrides — warn mode 期間中の構造的逸脱記録

## Purpose
新 kernel (Constitutional Invariants #1〜#6) は 2026-05-15 から default warn mode で
ship された。warn mode 中の Manager / Codex の violation は「許容された bootstrap 逸脱」
として記録される。enforce 化後はこの種の操作は禁止。

## Bootstrap Overrides

### BO-001: Manager 9 raw commits (Invariant #1 self-violation)
- 期間: 2026-05-14 ~ 2026-05-16
- 件数: 9 (commits 3776855, 4c19471, eb3c503, 97bd4f1, b7f5847, 3dfce93, 1a9e39d, 3397ff3, 6bea5b8)
- 根拠: warn mode、kernel が enforce する前段の bootstrap
- enforce 後は禁止: integrator-commit.sh 経由のみ

### BO-002: Manager manual cp from worktree to main repo
- 期間: 2026-05-14 ~ 2026-05-16
- 件数: 5 (T-OS-410, T-OS-411, T-OS-412, T-OS-413, T-OS-414)
- 根拠: Integrator Gate (Week 2) ship 前の手動反映
- enforce 後は禁止: queue → integrator-commit.sh フロー必須

### BO-003: TASKS.yaml direct Edit (YAML corruption 4回)
- 期間: 2026-05-14 ~ 2026-05-16
- 件数: 4 corruption events (eb3c503 で 1 回、T-OS-413/T-OS-414/T-OS-421 entry 内で各 1 回)
- 根拠: Manager Edit ツールが boundary を完全 match できなかった
- enforce 後は禁止: scripts/org/update-task.py 経由のみ

### BO-004: Manager active lease なし Edit/Write 多数
- 期間: 2026-05-14 ~ 2026-05-16
- 件数: 数十 (.ai/TASKS.yaml, .ai/REVIEW/, .ai/DECISIONS.md, .ai/CODEX/ORDERS/ への write)
- 根拠: Lease Registry (Week 3) ship 前
- enforce 後は禁止: acquire-lease.sh 先行
