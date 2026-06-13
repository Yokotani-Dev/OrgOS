# OrgOS 設計全体 Critical Review (T-OS-370)

> 実施: 2026-05-10 / Manager + 4 specialist subagents (org-threat-modeler / org-data-modeler / org-security-architect / org-domain-analyst の role を Explore agent で並列実行)
> 対象: M-PHASE-6, M-PHASE-7, Phase 2 全完了直後の OrgOS 全体

---

## Executive Summary

**結論**: OrgOS は **設計は完成度が高いが、設計と runtime 強制の間に CRITICAL gap が複数存在する**。

主要原因: ルール (Iron Law / authority-layer / parallel-session-policy 等) は document として完成しているが、それらを **enforce する hook / validator / gate が未実装または不完全**。

最も deeply CRITICAL: **Codex CLI は Claude Code の pretool hook を bypass する** (Codex は別プロセス、別 sandbox)。これは「Manager が hook で守られている」前提を根本から覆す。

**すべての specialist が独立に同じ結論に到達**: 「ルールは書かれているが、強制機構がない」。

---

## CRITICAL 発見一覧 (4 specialist の独立評価で重複/一致)

### CRIT-1: autonomy_level + allowed_paths が runtime 強制されていない
- **指摘**: threat-modeler + security-architect (独立に同じ指摘)
- **根拠**:
  - `authority-layer.md:320-326` が「T-OS-171/172/173 で実装」と書くが、これらは TASKS.yaml に **存在しない** (skip された)
  - `scripts/authority/os-mutation-check.sh` は OS mutation protocol のみチェック、autonomy_level の field lookup なし
  - Codex worker の `allowed_paths` は **honor system** (AGENTS.md 言及はあるが hard enforcement なし)
- **影響**: `autonomy_level: owner_only` の task が `allow_os_mutation=true` で silent 実行可能

### CRIT-2: pretool_policy.py が KERNEL_FILES + Iron Law files を保護していない
- **指摘**: security-architect
- **根拠**:
  - `.claude/evals/KERNEL_FILES` が 4 file のみ (security.md, review-criteria.md, project-flow.md, CONTROL.yaml)
  - **欠落**: rationalization-prevention.md, authority-layer.md, memory-lifecycle.md, manager.md, AGENTS.md, CLAUDE.md, parallel-session-policy.md
  - `pretool_policy.py:270-276` の Edit/Write チェックは hardcoded で `.claude/**` 一括だが、AGENTS.md (repo root) は対象外
- **影響**: `allow_os_mutation=true` で Manager が Iron Law file を編集可能

### CRIT-3: parallel-session-policy が runtime gate ではなく detection のみ
- **指摘**: threat-modeler + security-architect + domain-analyst (3 specialist)
- **根拠**:
  - `check-branch-consistency.sh` は `--report` で status 返すのみ、`--block-if-mismatch` なし
  - `acquire-lock.sh` (T-OS-363) は作成されたが `apply.sh` / Codex wrapper の **前提化されていない** (advisory)
  - `run-in-worktree.sh` (T-OS-362) wrapper は作成されたが、Manager が直接 `codex exec` を呼んでいる (まさに本セッション)
  - `pretool_policy.py:164-232` の branch check は switch target mismatch しか block しない
- **影響**: 並行実行で git mutation 衝突が依然発生可能

### CRIT-4: Codex --full-auto は Claude Code hook を bypass する
- **指摘**: security-architect (最も深刻な指摘)
- **根拠**:
  - `pretool_policy.py` は Claude Code hook、Codex プロセス内では効かない
  - Codex は別プロセスで filesystem に直接書き込む
  - Manager 経由の Edit/Write は hook で守られるが、**Codex 経由の実装は完全に hook 外**
  - allowed_paths が hard enforcement されない (CRIT-1 と相互強化)
- **影響**: Codex Worker が forbidden file を編集しても **何の防御もない**

### CRIT-5: Self-Evolution Engine の無限再帰リスク
- **指摘**: threat-modeler
- **根拠**:
  - `apply.sh` → 新 event 生成 → `detect.sh` 拾う → `synthesize.sh` 提案 → `apply.sh` のループに **iteration limit なし**
  - `synthetic-owner.sh` の bias で auto-approve に流れる可能性
  - `scheduler/run-detection.sh` に timeout / circuit breaker なし
- **影響**: 病的ケース: proposal が detection rule を変更 → 新 event → 新 proposal → 無限ループ

### CRIT-6: Codex 出力ファイルが secret 漏洩経路
- **指摘**: threat-modeler + security-architect
- **根拠**:
  - `.ai/CODEX/RESULTS/*` が **git tracked** (`.gitignore` 除外なし)
  - `check-no-plain-secrets.sh` (memory-lifecycle.md 参照) は **placeholder で未実装**
  - Codex 出力に API token / fixture credential が混入する可能性
- **影響**: secret が git history に永続漏洩

### CRIT-7: JOURNEYS ledger が存在しない (M-PHASE-6 の前提が崩れる)
- **指摘**: data-modeler
- **根拠**:
  - `.ai/JOURNEYS.example.yaml` (template) はあるが `.ai/JOURNEYS.yaml` (実体) **なし**
  - `user-journey-sync.md` の Iron Law「sync_status=confirmed 必須」が enforce 不可
  - M-PHASE-6 で Journey-First を強化したが、ledger 自体がない
- **影響**: Journey-First protocol が空回り

### CRIT-8: Iron Law 自己改修 / Manager 大権の組合せ脆弱性
- **指摘**: 全 specialist (組合せ脆弱性)
- **根拠**: CRIT-1 + CRIT-2 + CRIT-4 が組合さると、以下のシナリオが成立する:
  1. Manager が `allow_os_mutation=true` で `rationalization-prevention.md` を編集 (CRIT-2)
  2. Codex が `apply.sh` 経由で Iron Law file に write (CRIT-1, CRIT-4)
  3. Self-Evolution Engine が peer-review なしで auto-apply (CRIT-5)
- **影響**: **OrgOS 自身が安全境界を溶かす**

---

## HIGH 発見

- **HIGH-1**: 台帳 simultaneous 更新の transaction model なし (TOCTOU リスク)
- **HIGH-2**: Codex Work Order が plaintext で persist (`.ai/CODEX/ORDERS/*.md`)
- **HIGH-3**: MCP server の auth boundary 未文書化
- **HIGH-4**: USER_PROFILE secret pointer の参照経路に schema 強制なし
- **HIGH-5**: Stale OIP 105 日 + capability_degraded 55 events 未対応
- **HIGH-6**: アプリケーションレコードに `confirmed_at` / `confirmed_by` 欠落
- **HIGH-7**: i18n なし (Owner は日本語必須)
- **HIGH-8**: Anthropic AUP compliance が monitored されていない

## MEDIUM 発見 (省略 — SELFREVIEW.md にて全文)

---

## 対策タスク

| ID | Title | 対応 CRIT | Priority |
|---|---|---|---|
| T-OS-371 | pretool_policy.py に KERNEL_FILES 拡張 + Iron Law file 保護 | CRIT-2, CRIT-8 | P0 |
| T-OS-372 | Codex Worker enforcement layer (allowed_paths runtime + autonomy_level gate) | CRIT-1, CRIT-4 | P0 |
| T-OS-373 | parallel-session runtime gate (check-branch --block + git.lock 必須化 + worktree wrapper 必須化) | CRIT-3 | P0 |
| T-OS-374 | Self-Evolution Engine iteration limit + circuit breaker | CRIT-5 | P0 |
| T-OS-375 | Codex output secret scanner (pre-commit hook) + .gitignore 整理 | CRIT-6 | P1 |
| T-OS-376 | JOURNEYS.yaml ledger 実装 + 整合性 validator | CRIT-7 | P1 |
| T-OS-377 | Stale OIP / capability_degraded 解消 + 整合性スキャン | HIGH-5 | P1 |
| T-OS-378 | Anthropic AUP compliance preflight | HIGH-8 | P2 |

---

## 構造的提言

OrgOS は次の根本転換が必要:

1. **「document → enforcement」へのフェーズ移行**: ルールを書く Phase は完了。次は全 Iron Law を deterministic に enforce する hook / validator / gate に変換する。

2. **Codex を「外部 worker」として扱う**: Codex は Claude Code の hook ecosystem 外。Codex 起動前後の `wrapper enforcement layer` を必須化し、Codex 実行結果も Manager 側で post-validate する。

3. **Self-Evolution Engine に「自己制限」を組み込む**: iteration limit + circuit breaker + Iron Law file は apply 永久禁止。

4. **「設計の整合性」を継続検証する**: T-OS-377 で 1 回スキャンするだけでは不十分。整合性 validator を毎 Tick / 毎日実行する仕組みが必要 (T-OS-373 / T-OS-374 と統合可能)。

---

## Owner Decision Brief

**最も deeply 重要**: CRIT-4 (Codex hook bypass) と CRIT-8 (組合せ脆弱性)。これらが残る限り、OrgOS の安全境界は **書面上の約束** に過ぎない。

**推奨**: T-OS-371/372/373 を P0 として最優先実装 (3 タスク並列実行可)。完了で CRIT-1/2/3/4/8 が解消する。
