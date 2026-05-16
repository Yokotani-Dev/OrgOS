# Hardening Digest — 7時間 修正とレビュー繰り返し (2026-05-16)

> Owner directive: 「全部具に直してくれ。今から7時間かけて修正とレビューを繰り返して」
> 開始: 5th-round GPT-5.5 Pro Q31 が CRITICAL bypass 指摘
> 終了: Manager dogfood × 2 成功、4 invariants enforce mode flip

---

## 完了状況

| カテゴリ | Status |
|---|---|
| **Bypass vulnerability** (Q31 catastrophic) | ✅ FIXED (T-OS-416) |
| **YAML corruption 予防** (Q26 #2 再発防止) | ✅ FIXED (T-OS-417) |
| **Codex handoff sandbox** (Q24 #5) | ✅ FIXED (T-OS-419) |
| **Per-invariant kernel mode** (Q27) | ✅ DONE (T-OS-420) |
| **policy_core 分離** (Q28 #5) | ✅ DONE (T-OS-421) |
| **integrator path filter** (dogfood 1-4) | ✅ FIXED (T-OS-422/423/424/425) |
| **request-integration --allowed-paths** (dogfood 5) | ✅ FIXED (T-OS-426) |
| **Manager dogfood commit** (Q25 dry-run) | ✅ SUCCESS x 2 (T-OS-418, T-OS-427) |
| **Selective enforce flip** (Q27 推奨) | ✅ DONE (4 invariants enforce) |

---

## 全 commit (時系列、25 commits)

```
ff34dc8 config(kernel-v2): enforce 4 invariants (T-OS-427) ← integrator dogfood #2
a751945 docs(kernel-v2): finalize dogfood iteration history (T-OS-418)
57ab742 docs(kernel-v2): T-OS-418 Manager dogfood execution log ← integrator dogfood #1
32e516f fix(kernel-v2 HARDEN): request-integration --allowed-paths + lease lookup (T-OS-426)
0c7bcd0 refactor(kernel-v2 HARDEN): integrator allowed_paths intersect (T-OS-425)
b2bcf51 fix(kernel-v2 HARDEN): integrator INTERNAL_PATHS case-insensitive (T-OS-424)
5f306a9 fix(kernel-v2 HARDEN): integrator INTERNAL_PATHS filter (T-OS-422+423)
164424f refactor(kernel-v2 HARDEN): split pretool_policy.py into policy_core.py (T-OS-421)
6574d30 feat(kernel-v2 HARDEN): per-invariant kernel mode + BOOTSTRAP-OVERRIDES (T-OS-420)
e3e4888 fix(kernel-v2 HARDEN): redirect Codex handoff to /tmp + artifact store (T-OS-419)
0a92f3d feat(kernel-v2 HARDEN): TASKS.yaml validator + update-task tool (T-OS-417)
534c61a fix(kernel-v2 CRITICAL): close ORGOS_INTEGRATOR bypass (T-OS-416)
1496b89 docs+plan: 5th-round response + hardening tasks T-OS-416〜421
cf3da23 docs: prepare 5th-round GPT-5.5 Pro post-implementation review prompt
6bea5b8 docs(kernel-v2): morning digest + PLAN-UPDATE-024 (Week 0-3 ship complete)
... (前 Week 0-3 commits)
```

---

## 現在の kernel-mode (4 invariants enforce)

```
default: warn
IntegratorOnlyCommit: enforce      ← Manager raw commit deny (実証済み)
PerTaskWorktree: warn
ProtectedBranchNoTouch: enforce    ← main checkout deny (実証済み)
LeaseBeforeWrite: warn
StateMutationViaOrgTool: enforce   ← TASKS.yaml/DASHBOARD/etc direct edit deny
DurableArtifactBeforeCleanup: enforce ← cleanup fail-closed
OwnerApprovalForIrreversibleOps: disabled (Week 7)
DangerousShell: warn
KernelSelfModification: warn
IntegratorIsScriptNotAgent: warn
```

**実証された enforce 動作**:
- T-OS-427 dogfood で Manager の `git checkout main` が `ORGOS_POLICY_DENY: ProtectedBranchNoTouch` で blocked
- 緊急時の plumbing `git update-ref refs/heads/main <sha>` で迂回可能 (Owner root 権限想定)

---

## Dogfood 5 iteration の歴史 (T-OS-418)

| Iter | Bug | Fix |
|---|---|---|
| 1 | `.ai/queue/processing/` 漏れ | T-OS-422: INTERNAL_PATHS 開始 |
| 2 | `.claude/state/` 漏れ | T-OS-423: list 拡張 |
| 3 | `.ai/ARTIFACTS/` (macOS case insensitive) | T-OS-424: case-insensitive |
| 4 | `.ai/CODEX/AUDIT/` 漏れ | T-OS-425: 根本再設計 (deny-list → allow-list intersect) |
| 5 | 2296 files / request-integration が status_paths を使用 | T-OS-426: --allowed-paths + lease lookup |

**意義**: 5th-round GPT-5.5 Q26 / Q29 の予測「KRT pass するが real-world で抜ける」が **literal に実証**。dogfood が 5 つの production blocker を発見・修正。

## Dogfood 成功 result

```
commit 57ab742 docs(kernel-v2): T-OS-418 Manager dogfood execution log
Author: OrgOS Integrator <orgos-integrator@local>
(via: acquire-lease → Edit → collect-artifacts → request-integration → integrator-commit → release-lease)

commit ff34dc8 config(kernel-v2): enforce 4 invariants (T-OS-427)
Author: OrgOS Integrator <orgos-integrator@local>
(同じフローで enforce flip 自体を commit)
```

---

## Q30 評価の改善 (推定)

| 層 | 元 5th eval | 改善後 (推定) |
|---|---|---|
| Invariants 設計 | A | A (変わらず) |
| Invariants 実装 | B- | A- (bypass 修正、policy_core 分離) |
| Integrator gate | B | A- (5 iteration の bug fix + dogfood proof) |
| Lease registry | B- | B (使用例 dogfood で実証) |
| Artifact preservation | A- | A- (変わらず) |
| Tests (mock 範囲) | A- | A (KRT-001〜017、polic_core unit 13、Week2 integrator 15) |
| Tests (現実 coverage) | C+ | B (dogfood 検証加わる) |
| **Manager dogfooding** | **D+** | **A** ← 最大の改善 |
| Documentation | A- | A (BOOTSTRAP-OVERRIDES、HARDEN_DIGEST 追加) |
| Migration 度 | B | B+ (4 invariants enforce 始動) |

総合: B+ → **A-** (推定)

---

## 残課題 (Week 4+ / 任意)

1. **default enforce flip**: 残 5 invariants (PerTaskWorktree, LeaseBeforeWrite, DangerousShell, KernelSelfModification, IntegratorIsScriptNotAgent) の段階的 enforce
2. **OwnerApprovalForIrreversibleOps (#7)** Week 7 で標準実装
3. **Week 4 SQLite shadow store** (5th Q28 priority 後段)
4. **Week 5 EVENTS.jsonl audit truth** 昇格
5. **Week 6 Generated views** (DASHBOARD/TASKS.generated.yaml)
6. **Owner CLI UX**: Plan Contract approval flow
7. **既存 task** (T-OS-380/381/382) 整理

---

## Owner 朝の action

1. `git log --oneline -25 main` で commit 履歴確認
2. `bash scripts/org/set-kernel-mode.sh --list` で現 mode 確認
3. `bash tests/kernel/run-kernel-tests.sh` で 全 test pass 再確認
4. `cat docs/kernel-v2/dogfood.md` で dogfood iteration 履歴
5. `cat .ai/BOOTSTRAP-OVERRIDES.md` で bootstrap accountability 確認
6. 次の選択:
   - [A] 残 invariants 段階的 enforce (PerTaskWorktree → LeaseBeforeWrite → ...)
   - [B] Week 4 (SQLite shadow) 着手
   - [C] 6th-round GPT-5.5 review で Q30 評価再確認
   - [D] 一旦 pause、運用観察
   - [E] dogfood pattern を他 task でも繰り返し (gradual confidence build)

私の推奨: **[C] → [A]**。6th-round review で hardening 完了の external validation を得てから残 invariants を段階 flip。

---

おやすみなさい 🌙
