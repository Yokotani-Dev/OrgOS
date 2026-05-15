# Morning Digest — 夜間 Autonomy 実行報告 (2026-05-15)

> Owner 着床時用。前夜 (2026-05-14) からの自律実行サマリ。
> 開始: Owner FB「全部進めて」+「5.5 pro のレビューが必要なものがあればまたプロンプト書いて」
> 終了: Week 0-3 kernel core ship 完了で自然停止
> 所要: 約 2 時間、Codex dispatch 5 回、commit 8 件

---

## TL;DR

**新 kernel の Constitutional Invariants #1〜#6 を全て runtime enforce で ship 完了 (mode=warn)。**
35/35 tests pass、SKIP ゼロ。

残課題:
1. **kernel mode を warn → enforce に flip するか** (Owner 判断)
2. **Week 4-8 (state migration + UX) を続けるか pause か** (Owner 判断)
3. **GPT-5.5 Pro レビュー必要か** — 設計レビューは不要、実装レビュー 1 件あり (後述)

---

## 実行サマリ

| Commit | 内容 |
|---|---|
| 3776855 | feat: Day 0 — cleanup_worktree() fail-closed (T-OS-410) |
| 4c19471 | feat: Day 1 — artifact manifest + capture + verification (T-OS-411) |
| eb3c503 | fix: YAML duplicate-key corruption (TASKS.yaml meta-cleanup) |
| 97bd4f1 | feat: Day 2-5 — pretool policy + KRT regression (T-OS-412) |
| b7f5847 | chore: register T-OS-413 |
| 3dfce93 | feat: Week 2 — Integrator gate + queue (T-OS-413) |
| 1a9e39d | chore: register T-OS-414 |
| 3397ff3 | feat: Week 3 — Lease registry + Invariant #4 (T-OS-414) |

---

## 7 Constitutional Invariants 実装状況

| # | 名前 | 状態 | enforcement |
|---|---|---|---|
| 1 | Integrator-Only Commit | ✅ Week 2 | pretool deny raw `git commit`/`push`、`ORGOS_INTEGRATOR=1` prefix bypass |
| 2 | Per-Task Worktree | ✅ Week 0 | pretool deny shared/root worktree write、`run-in-worktree.sh` 経由のみ |
| 3 | Protected Branch No-Touch | ✅ Week 0 | pretool deny `checkout/switch main/develop`, `reset --hard`, `branch -f` |
| 4 | Lease Before Write | ✅ Week 3 | pretool: active lease 不在で write/edit deny、`.ai/leases/` per-file registry |
| 5 | State Mutation via Org Tool | ✅ Week 0 | pretool deny direct edit of `.ai/EVENTS.jsonl` |
| 6 | Durable Artifact Before Cleanup/Done | ✅ Day 0/1 | wrapper fail-closed cleanup, artifact_manifest 検証必須 |
| 7 | Owner Approval for Irreversible Ops | ⏳ Week 7 | standing approval policy 未実装 |

**6/7 完了**。#7 は Plan Contract UX と一体のため Week 7 に集約。

---

## kernel mode (重要)

現在: **`mode = "warn"`** (`.claude/state/kernel-mode.json`)

| mode | 動作 |
|---|---|
| warn (現在) | 違反検出 → stderr `ORGOS_POLICY_WARN`、実行は許可 |
| enforce | 違反検出 → stderr `ORGOS_POLICY_DENY`、exit 2 (block) |
| disabled | invariant チェック skip |

### Owner review 後の推奨アクション

```bash
bash scripts/org/set-kernel-mode.sh enforce
```

これで raw `git commit` 等が物理的に block される。Manager (Claude) も例外なし。
Owner manual override は `ORGOS_INTEGRATOR=1 git commit ...` で可能。

---

## テスト状況

```
$ bash tests/kernel/run-kernel-tests.sh
day0 cleanup tests: 5 passed, 0 failed
day1 manifest tests: 6 passed, 0 failed
KRT day2 tests: 10 passed, 0 failed, 0 skipped
Week2 integrator tests: 6 passed, 0 failed
Week3 lease tests: 8 passed, 0 failed

合計 35 tests, 全 pass, SKIP ゼロ
```

KRT-001〜KRT-010 全 active (元々 KRT-007/008 が Week 2/3 待ちで SKIP)。

---

## 既知の問題

### 1. YAML duplicate-key corruption 発生 (修復済み、再発リスクあり)

私の Edit 操作 (TASKS.yaml への task 追加) が duplicate-key block を生成する pattern を 3 回発生させた。修復は適切に行ったが、根本対策が必要:

- 原因: Edit の `old_string` が task entry の境界を正確に matching せず、orphan field が残る
- 対策案 (Owner review):
  - (a) TASKS.yaml を Edit ではなく Write (全文置換) で更新
  - (b) `scripts/org/add-task.sh` 等の dedicated tool を作る (Week 6 generated view の前段)
  - (c) JSON Schema で TASKS.yaml を validate する CI

**影響範囲確認**: T-OS-405/408/409 (meta-review tasks) は完了済みで allowed_paths 欠落しても支障なし。本 commit 時点でのデータは consistent。

### 2. wrapper bug 1 件残存 (sandbox)

Codex が wrapper の `--output-last-message` で main repo 側 `.ai/CODEX/RESULTS/<task>.txt` に書こうとした際、sandbox policy が `operation not permitted` で拒否。

- T-OS-412 (1st run) / T-OS-413 / T-OS-414 で発生
- Codex は fallback として `/private/tmp/OrgOS-<task>-handoff.txt` に書き、stdout で報告
- Wrapper は streaming output から拾えているので致命的ではないが、改善余地あり
- 修正候補: wrapper が `mkdir -p` してから渡す / sandbox の workdir に allowed_paths を追加 / Handoff Packet を別経路に

これは Week 0-3 では blocker ではなかった。Week 5 (event log) で artifact source として重要になる可能性あり。

---

## Week 4-8 残作業 (停止理由)

| Week | 内容 | 性質 | 推奨判断 |
|---|---|---|---|
| Week 4 | SQLite shadow store + TASKS.yaml import | shadow mode、非破壊 | Owner approve で進行可 |
| Week 5 | EVENTS.jsonl audit truth 昇格 | state authority 移行、破壊的潜在 | Week 4 が shadow 1 週間 stable 確認後 |
| Week 6 | Generated views (DASHBOARD/TASKS.generated.yaml) | 既存 manual edit workflow 廃止 | Week 5 完了が前提 |
| Week 7 | Plan Contract UX + Invariant #7 | Owner との対話 UX 変更 | UX 変更は Owner と慎重に擦り合わせるべき |
| Week 8 | Rule/Agent/Script kill week | 30+ rules → 7 invariants、18 subagents → 4-5 | UX 影響大、Week 7 後段で実施 |

**停止根拠** (GPT-5.5 Pro Q23 procrastination ライン参考):

1. Week 0-3 は「**何を作るか明確、リスク低**」
2. Week 4 以降は「**既存 workflow を変える、リスク中-高**」
3. 各 migration には GPT Q15 の中止ライン (例「shadow mode で 2 回 zere → SQLite 延期」) があり、Owner が中止判断する場面が出やすい
4. Owner morning review は健全な区切り

---

## GPT-5.5 Pro レビューが必要なもの (該当 1 件)

設計レビューは**不要** (4 round 分の spec で Week 4-8 までカバー済み)。
ただし以下 1 件のみ実装レビュー価値あり:

### Q24 (任意): YAML 編集の構造的問題

「Manager (Claude) の Edit 操作が TASKS.yaml に duplicate-key corruption を繰り返し生成した。
Week 6 (Generated views) で TASKS.yaml を `.ai/TASKS.legacy.yaml` 化する前に、interim
mitigation として何を勧めるか? (a) Write 全置換、(b) `scripts/org/edit-task.sh` dedicated tool、
(c) pre-commit YAML validator、(d) これは Week 6 まで放置で OK。」

Owner が必要と判断したら prompt 化可能。本 digest 単独では prompt 未作成。

---

## Owner Decision Points (朝の選択肢)

### A. kernel mode 切替

**[A-1] warn のまま維持** (推奨、観察期間 1 日程度)
**[A-2] enforce に flip** — `bash scripts/org/set-kernel-mode.sh enforce`
**[A-3] disabled に flip** — kernel off (戻り operation 自由、ただし事故再発リスク)

### B. Week 4 進行

**[B-1] Week 4 SQLite shadow 着手** — 私 (or 次セッション) が dispatch
**[B-2] pause、運用観察** — 数日 warn mode 観察してから判断
**[B-3] Week 4 設計再考** — GPT-5.5 Pro レビュー追加

### C. 既存 task の扱い

T-OS-380/381/382 (SELFREVIEW-002 follow-up) と T-OS-330 (TASKS_ARCHIVE 自動化) などの旧 task が queued のまま残存。Week 4-8 と並走するか、まず処理するか。

---

## 推奨

**朝のフロー**:

1. `git log --oneline -10` で commit 履歴を確認
2. [SYNTHESIS.md](SYNTHESIS.md) を眺めて全体方針を再確認
3. `bash tests/kernel/run-kernel-tests.sh` で動作確認 (35/35 pass のはず)
4. 何か一つ簡単な作業を warn mode で試行 (ファイル編集、cp など) して warning 内容を確認
5. 上記 A/B/C を判断
6. 私 (次セッション) に指示

---

## ファイル参照

- 7 Invariants 設計: `.ai/REVIEW/T-OS-400/SYNTHESIS.md` Section 3
- 各 Week spec: `.ai/REVIEW/T-OS-400/external-ai-4th-response.md`
- Manager 視点: `.ai/REVIEW/T-OS-400/manager-vision.md`
- 全 task 一覧: `.ai/TASKS.yaml` (T-OS-410〜414 が done)
- 実装本体: `.claude/hooks/pretool_policy.py`, `scripts/org/*.sh`, `scripts/codex/run-in-worktree.sh`
- テスト: `tests/kernel/`

おやすみなさい 🌙
