# OrgOS 理想形 SYNTHESIS — 3視点集約と Build 移行方針 (T-OS-404)

> 作成日: 2026-05-14
> Inputs:
> - ① [manager-vision.md](manager-vision.md) — Manager (Claude Opus 4.7)
> - ② [codex-response-partial.md](codex-response-partial.md) — Codex (GPT-5.5/High) partial
> - ③ [external-ai-response.md](external-ai-response.md) — GPT-5.5 Pro 1st
> - ③-2 [external-ai-followup-response.md](external-ai-followup-response.md) — GPT-5.5 Pro follow-up
> - ③-3 [external-ai-3rd-response.md](external-ai-3rd-response.md) — GPT-5.5 Pro 3rd round
> - ③-4 [external-ai-4th-response.md](external-ai-4th-response.md) — GPT-5.5 Pro 4th round
>
> **判定: STOP DESIGN. START BUILD.** (GPT-5.5 Pro Q23, 4th round)

---

## TL;DR

- 3視点は **強く独立収束**: rule vs runtime gap、Manager 責務過剰、状態散逸、worker capability boundary、Owner intent→Plan、rule 単調増加抑制、観測可能性。設計の方向は確定。
- **patch-on-patch の根本原因** は「自然言語 policy を実行境界と誤認」。OrgOS は「願望を書いた運用マニュアル」だった。
- **新 kernel の最小集合**: 7 Constitutional Invariants + Python `policy_core.py` + pretool/posttool/git hook + integrator script。SQLite/event log は後段。
- **Manager の身分**: Control-plane Dispatcher。worker/integrator/Owner proxy ではない。**raw commit 禁止**。
- **Week 0 から開始**: artifact preservation (cleanup fail-closed) → Week 1 No Worker Commit + No Shared Worktree → Week 2-8 で event log / Plan Contract / Kill List。
- **既存 T-OS-390〜399** は撤回 / 統合。新 kernel の Week 0-8 に組み直す。
- **次の一手**: `cleanup_worktree()` を fail-closed に変更 (Day 0 patch)。実装 spec は [external-ai-4th-response.md Q16](external-ai-4th-response.md#q16-day-0-minimum-patch) に完備。

---

## Section 1 — 3視点の収束 (確定事項)

以下 7 項目は **全 3 視点が独立に同じ結論** に到達した。これらは Week 0 から実装の前提として固定する。

| # | 確定事項 | 出典 |
|---|---|---|
| 1 | 自然言語 rule は enforcement ではない。runtime check が必須 | Manager #1, Codex E/F, GPT all |
| 2 | Manager は dispatcher に降格。万能実行者をやめる | Manager #2/原則5, Codex §5, GPT Q6 |
| 3 | 状態は event log + projection。複数 SSOT は破綻 | Manager 原則3, Codex projection log, GPT Q3 |
| 4 | Worker は capability boundary に物理的に閉じ込める | Manager 原則4, Codex sandbox, GPT Q4 |
| 5 | Owner UX は intent → Plan Contract → approve/modify/reject | Manager 原則6, GPT Q7/Q21 |
| 6 | Rule 単調増加を止める consolidation 機構が必要 | Manager 原則7, Codex F, GPT Q5/Kill List |
| 7 | 観測可能性と証拠 (diff/test/artifact/event) が必要。Handoff Packet 単体では不可 | Manager 原則8, GPT Q14 |

---

## Section 2 — 対立点と仲裁結果

GPT-5.5 Pro が 3rd round で外部仲裁者として判定。

| # | 対立 | Manager 案 | Codex 案 | GPT 仲裁結果 |
|---|---|---|---|---|
| 1 | enforcement 層粒度 | 全 Iron Law に runtime check | Python pure function + YAML table | **統合**: 7 invariant に絞り `policy_core.py` 一本化 |
| 2 | 設計密度 | Phase A-E 段階移行 | simplest viable alternative (半分捨てる) | **8週 plan + Week 0 stabilization 追加** |
| 3 | 状態 store 権威 | `.ai/EVENTS.jsonl` SSOT | projection/event log | SQLite + jsonl | **EVENTS.jsonl が SSOT、SQLite は projection** (GPT 自己訂正) |
| 4 | FSM vs Plan Contract | Plan Contract 寄り | FSM 寄り | **両方必要**: Plan Contract は UX、FSM は runtime |

評価点: Manager A / Codex partial A- / GPT follow-up A- / **統合案 S-**

---

## Section 3 — 7 Constitutional Invariants (最終版)

GPT 3rd round で 6 番目を `Durable Artifact Before Cleanup/Done` に拡張。これが最終版。

| # | 名前 | 内容 | enforcement |
|---|---|---|---|
| 1 | **Integrator-Only Commit** | commit は integrator script のみ。Manager/Codex/subagent の raw `git commit` 禁止 | pretool + git hook + posttool HEAD auditor |
| 2 | **Per-Task Worktree** | 実装 worker は task 専用 worktree で動く | pretool + sessionstart |
| 3 | **Protected Branch No-Touch** | main/develop への checkout/reset/commit/force update は integrator のみ | pretool |
| 4 | **Lease Before Write** | write/edit は task lease + allowed_paths がある場合のみ | pretool + posttool diff scan |
| 5 | **State Mutation via Org Tool** | `.ai/` operational state は org tool 経由のみ。手編集禁止 | pretool + checksum |
| 6 | **Durable Artifact Before Cleanup/Done** | cleanup 前に artifact manifest 必須。manifest なし run は done 不可 | wrapper fail-closed + verify_manifest |
| 7 | **Owner Approval for Irreversible Ops** | production/secret/migration/destructive は approval event なしに実行不可 | pretool + standing approval policy |

### Manager × 7 invariant 適用 (GPT 3rd round Q12)

**全 invariant が Manager に適用される**。例外なし。唯一の緩和は #2 の read/planning は root でも可。

---

## Section 4 — Migration Sequence (Week 0 → Week 8)

| Week | Ship | Rollback Point |
|---|---|---|
| **Week 0 (Day 0-1)** | Artifact preservation + cleanup fail-closed | warning に戻せる |
| **Week 1 (Day 2-5)** | No Worker Commit + No Shared Worktree + KRT-001〜010 | 各 enforcement 個別に warn 化可。raw commit deny は維持 |
| **Week 2** | Integrator gate (`scripts/org/integrator-commit.sh`) + integration_queue | Owner manual commit 一時許可 |
| **Week 3** | Lease registry (`.ai/leases.yaml`) + allowed_paths runtime | YAML legacy fallback |
| **Week 4** | SQLite shadow store (TASKS import + dashboard generation) | SQLite 捨てて YAML に戻る |
| **Week 5** | EVENTS.jsonl audit truth 昇格 | TASKS.yaml source 一時復活 |
| **Week 6** | Generated views (DASHBOARD/TASKS.generated.yaml)、TASKS.yaml legacy 化 | EVENTS 残して YAML を SSOT に戻す |
| **Week 7** | Plan Contract UX (drafts/approved/CLI) | /org-tick 残存 |
| **Week 8** | Rule/Agent/Script kill week (30+→7 invariant, 18→4-5 subagent) | archive から復活可 |

詳細は [external-ai-followup-response.md Q2](external-ai-followup-response.md#q2-migration-plan-週次) と [external-ai-3rd-response.md Q14](external-ai-3rd-response.md#q14-wrapper-bug--week-1-精度) を参照。

---

## Section 5 — 既存タスクの再配置

### T-OS-390〜399 (M-PHASE-7 v2) の運命

GPT 3rd round Q13 / Q6 Kill List に基づき、**全 9 タスクを撤回し、新 kernel の Week 0-8 に再配置**。

| 旧 ID | 旧内容 | 新配置 |
|---|---|---|
| T-OS-390 | epic / 設計統合 | **完了相当**: 本 SYNTHESIS が役割を果たした |
| T-OS-391 | Codex 自動 commit 禁止 | **Week 1 Day 2** (`No Worker Commit`) に統合 |
| T-OS-392 | allowed_paths pre-flight | **Week 3** (Lease Registry) に統合 |
| T-OS-393 | main 直 commit 拒否 | **Week 1 Day 2** (`Protected Branch No-Touch`) に統合 |
| T-OS-394 | worker フィールド + heartbeat | **Week 3** (lease.heartbeat_at) に統合 |
| T-OS-395 | feature branch automation | **Week 1 Day 3** (per-task worktree branch) に統合 |
| T-OS-396 | .ai/LOCKS/T-XXX.lock | **撤回**: lease registry で代替 (file 増殖回避) |
| T-OS-398 | develop→main bot | **撤回**: trunk-based + integrator gate で不要 |
| T-OS-399 | parallel session 可視化 | **Week 6** (Generated DASHBOARD) に統合 |

### その他の影響

| ID | 旧内容 | 新運命 |
|---|---|---|
| T-OS-402 | Codex 視点批評 (blocked) | **cancelled**: 4th round で十分。partial は SYNTHESIS に取り込み済み |
| T-OS-407 | Codex 再実行 (--keep-worktree) | **cancelled**: GPT 4th round で代替可能と確認 |
| T-OS-406 | Wrapper bug 修正 | **Week 0 Day 0 に昇格・統合**: cleanup_worktree() fail-closed の根本対応 |
| T-OS-380〜382 | SELFREVIEW-002 follow-up | **継続**: Week 1 以降の subagent fleet 縮小と合わせて再評価 |

---

## Section 6 — Out of Scope (Week 0-8 でやらない)

GPT 4th round Q23 「これ以上の design は procrastination」を踏まえ、以下を**明示的に scope 外**にする。Build 中に必要性が出たら incident review で追加判断。

- OPA / Cedar 導入 (Python policy_core で十分)
- 独立 daemon プロセス (Claude Code substrate に合わない)
- 完全 sandbox (chroot / namespace) (Owner root + AI 制限 user の思想で十分)
- 全 subagent prompt 刷新 (Week 1 では 18 個維持、Week 8 で削減)
- Slack/Webhook 通知 infra (stderr + log で十分)
- Cross-project SSOT (per-repo EVENTS が真実、global は index)
- Common audit log (各 repo の EVENTS で十分)
- 完全 trunk-based 強制 (個 project の branch 戦略は project lease に委ねる)

---

## Section 7 — Day 0 第一手 (今すぐ実行可能)

GPT 4th round Q16 が **shell pseudo-code レベルで完備**。コピペ実装可能。

### 変更対象
- [scripts/codex/run-in-worktree.sh](../../../scripts/codex/run-in-worktree.sh) — `cleanup_worktree()` を fail-closed に書き換え

### 追加するもの
- `--cleanup-after-manifest` / `--artifact-manifest PATH` フラグ
- `verify_artifact_manifest_minimal()` 関数 (Python 3 line check + required key)
- `mark_worktree_quarantined()` 関数 (`.orgos-quarantine` marker + alert log)
- `notify_owner()` 関数 (stderr + `.ai/alerts/worktree-cleanup.log`)

### 変更デフォルト
- `keep_worktree=1` (preserve by default)
- `cleanup_after_manifest=0` (explicit opt-in only)

### Day 0 受入テスト (5 件)
1. default preserve → `cleanup_status=kept`
2. manifest なし `--cleanup-after-manifest` → quarantine
3. invalid manifest → quarantine
4. valid minimal manifest → `removed_after_manifest`
5. 既存 `--keep-worktree` flag 互換性維持

### この patch だけで防げる事故
- T-OS-402 で発生した literal な codex-response.md 消失
- 同型の「audit allowed と書いたのに成果物が消える」事故

---

## Section 8 — 次のアクション

1. **新 task T-OS-410 を作成**: `[Kernel-v2 Day 0] cleanup_worktree() fail-closed patch`
2. **T-OS-390〜399 / 402 / 407 / 408 / 409 / 406 を統廃合**: 上記 Section 5 に従う
3. **Day 0 patch を Codex に dispatch** (`--keep-worktree` 必須、artifact preservation を最初の commit から守る)
4. **Day 0 完了後 Day 1 (artifact manifest 実装) に進む**: GPT 4th round Q17 spec を Work Order に
5. **Owner 承認**: kernel maintenance lease として `.claude/hooks/` `scripts/codex/` の編集を Owner explicit approve

---

## Section 9 — リスクと早期検出メトリクス

GPT 4th round Q23 が直近リスク 3 つを特定。各リスクに早期検出メトリクスを設定する。

| リスク | 早期検出メトリクス | 中止ライン |
|---|---|---|
| hook false positive で作業停止 | Owner が 1 日 3 回以上 hook 無効化 | warn mode に戻す (raw commit deny は維持) |
| artifact collector 拾い漏らし | `artifact_survival_rate < 100%` | worktree cleanup 全面停止 |
| multi-project rollout で version drift | `.orgos-kernel-version` 不一致 project 数 > 2 | canary を 1 project に戻す |

---

## Appendix: 設計コストの自己観察

- 1st (Q1-Q10): 一般批評、5500字
- follow-up (Q1-Q8 改): 実装具体化、SQL schema + Plan Contract 例
- 3rd round (Q11-Q15): cross-view arbitration + Manager身分 + Week 0 追加
- 4th round (Q16-Q23): Day 0 patch pseudo-code + manifest schema + KRT-001-010 + STOP signal

合計約 30000 字以上の外部設計レビューを受け、Manager + Codex partial と統合。**これ以上の design round は procrastination** (GPT 自己判定)。

次は SYNTHESIS の通り Build に入る。
