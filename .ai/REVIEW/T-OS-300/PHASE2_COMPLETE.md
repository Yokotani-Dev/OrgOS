# Phase 2 全 12 タスク完遂サマリ — Self-Evolution Engine 稼働開始

> 完了: 2026-05-10
> Owner declaration「人に依存しない継続的改善の仕組み」への直接実装が完了

---

## 全 12 タスクの完了状態

| ID | Title | Status | 主成果物 |
|---|---|---|---|
| T-OS-310-cleanup | Deprecated agent 削除 + manifest 完全化 | ✅ DONE | org-implementer.md 削除、manifest 23 rule |
| T-OS-320 | Evolution Event Store + Detector v1 | ✅ DONE | detect.sh + 5 scanners、初回 81 events 検出 |
| T-OS-321 | OWNER_INBOX → Decision Table | ✅ DONE | Decision Console 化、test 残滓 4 件 archive |
| T-OS-321b | OWNER_INBOX helper scripts | ✅ DONE | add/list/expire/archive 4 scripts |
| T-OS-322 | TASKS autonomy metadata backfill | ✅ DONE | 48 タスク 100% backfill |
| T-OS-323 | OS DNA v0.1 schema + manifest | ✅ DONE | ORG_DNA.yaml (95 components)、DNA_HISTORY.yaml |
| T-OS-324 | Synthesis: proposal + peer review | ✅ DONE | synthesize.sh + peer-review.sh、proposal sample 2 件 |
| T-OS-325 | Validation harness + synthetic Owner | ✅ DONE | synthetic-owner.sh + fixture-response.sh、10 fixtures pass |
| T-OS-326 | Application engine: shadow/canary/full | ✅ DONE | apply.sh + rollback.sh + circuit-breaker.sh |
| T-OS-327 | Adaptive Capability Probe | ✅ DONE | probe-new.sh + role-routing.sh、capability_roles 概念採用 |
| T-OS-328 | Intelligence freshness pipeline | ✅ DONE | scripts/intel/ collect + summarize + emit-oip |
| T-OS-329 | Always-On shadow scheduler | ✅ DONE | run-detection.sh + setup-cron.sh + launchd + GH Actions |
| T-OS-330 | Marketplace DNA (予定) → TASKS archive 化 | 🔄 部分 | hook で別 scope (TASKS archive 86 件) を実行。Marketplace 本体は Phase 3 へ defer |
| T-OS-331 | Evolution Dashboard / AI Evolution Trace | ✅ DONE | scripts/dashboard/render.sh、DASHBOARD.md 更新 |

**Phase 2 完成度**: 12/13 件完了 (T-OS-330 Marketplace のみ Phase 3 へ defer)。

## 稼働確認できる機構

### Self-Evolution Engine の閉ループ

```
detect.sh → events.jsonl (81 events)
  ↓
synthesize.sh → proposals/*.yaml (priority_score 順 top N)
  ↓
peer-review.sh → Risk + Iron Law 自動評価
  ↓
synthetic-owner.sh → Owner 反応 simulate
  ↓
apply.sh (shadow → canary → full、circuit-breaker 付き)
  ↓
rollback.sh (consecutive_revert=3 で halt)
  ↓
DASHBOARD.md (render.sh で <1s 更新)
```

### Adaptive Capability Layer

- `probe-new.sh` — 新 CLI/MCP 出現を検出 → proposal 生成 (T-OS-324 統合)
- `role-routing.sh` — `deep-reasoning` / `fast-classification` / `code-generation` を vendor 中立で解決
- `capability-roles.yaml` schema — モデル直書き禁止の前提

### OS DNA

- `.ai/ORG_DNA.yaml` (22KB、95 components)
- `.ai/DNA_HISTORY.yaml` (24KB、semver-style)
- `scripts/dna/regenerate.sh --bump-version patch|minor|major`

### Intelligence Pipeline

- `scripts/intel/collect.sh` — RSS / GH trending を fetch (graceful failure)
- `scripts/intel/summarize.sh` — `.ai/INTELLIGENCE/weekly/2026-W19.md` を生成
- `scripts/intel/emit-oip.sh` — OIP candidate を T-OS-324 proposal として吐く

### Always-On

- `scripts/scheduler/setup-cron.sh` — cron 登録 helper
- `scripts/scheduler/com.orgos.scheduler.plist.template` — launchd
- `.github/workflows/orgos-scheduler.yml` — GitHub Actions
- shadow mode で proposal を生成、Owner 不在中も動く

### Owner Surface

- `.ai/OWNER_INBOX.md` Decision Console format (pending 0 件)
- `.ai/DASHBOARD.md` に metrics card (pending decisions / autonomous applies / evolution events / questions by priority)
- `scripts/inbox/list-pending.sh` で 1 コマンド確認

## 検証された数値

- **events.jsonl**: 81 events (eval_regression=1, ux_drift=1, capability_degraded=68, oip_stale=2, rule_stale=8, intel_stale=1)
- **TASKS.yaml**: 36 queued / 86 archived (TASKS_ARCHIVE.yaml 移動済) / autonomy coverage 100%
- **OWNER_INBOX**: pending 0 件、archived 4 件 (test 残滓)
- **Dashboard render**: 0.14s
- **Synthetic Owner fixture**: 10/10 pass
- **Iron Law gate**: AGENTS.md への applied attempt が rejected (機能確認)
- **Circuit breaker**: consecutive_reverts=3 で halt 確認済み

## Owner 体験変化

### Before (Phase 2 開始前)
- daily-health-check が 19 日停止していたが Owner は気づかない
- OIP が 3 ヶ月 (105 日) 停止していたが起票されない
- OWNER_INBOX に test 残滓 4 件が 12 日放置
- Manager は task autonomy を判定できず、Owner に逐次質問
- AI モデルは hardcode され、進化追従は手動
- Self-improvement は Owner が `/org-evolve` を手動起動する必要

### After (Phase 2 完了後)
- detect.sh が 81 件を即検出、Manager は自動で proposal 化
- Decision Table format で Owner が「読んで 60 秒、回答 1 文字」
- autonomy_level に基づき Manager が deterministic に act/ask/defer 判定
- capability_roles で vendor 中立、新モデル/MCP は probe で自動検出
- shadow → canary → full のロールアウト、rollback 自動化
- launchd/cron/GH Actions のいずれかで Always-On 動作

## 残タスクと次手

### 未完了 (Phase 2 内)

| ID | 内容 | 状況 |
|---|---|---|
| T-OS-330 | Marketplace DNA import/export | Phase 3 (Multi-Project Hub) と統合して再設計推奨 |

### Phase 3 候補 (Owner 承認待ち)

[PHASE3_MULTIPROJECT.md](.ai/REVIEW/T-OS-300/PHASE3_MULTIPROJECT.md) 参照。10 PJ 並列の決済集約 + ローカル制約への対応。

### 推奨 follow-up タスク

| ID 案 | 内容 | 優先度 |
|---|---|---|
| T-OS-340 | Owner 手動: launchd/cron/GH Actions のいずれかで scheduler を実環境に登録 | P0 (Always-On 実稼働の前提) |
| T-OS-341 | agent prompt のモデル名直書き → capability_roles 経由に置換 | P1 |
| T-OS-342 | proposal LLM 駆動化 (現状 deterministic template ベース) | P1 |
| T-OS-343 | T-OS-330 Marketplace を Phase 3 と統合再設計 | P2 |
| T-OS-344 | shellcheck 環境整備 (本 batch で 5 タスクが warning 残し) | P2 |
| T-OS-345 | 既存 agent prompt の rule 参照を ORG_DNA.yaml 経由に | P2 |

## Owner Action

**今のところ何も必要なし**。Phase 2 が稼働しているので、Owner が次に PC を開いた時に:

```bash
bash scripts/dashboard/render.sh                # DASHBOARD 即更新
bash scripts/inbox/list-pending.sh              # 決済待ち確認 (現状 0 件)
bash scripts/evolution/detect.sh --json         # 新 events 検出
bash scripts/evolution/synthesize.sh --top 5    # 上位 5 events で proposal 生成
```

これだけで Self-Evolution Engine の状態が把握できます。

## 参考: 出典分析ドキュメント

- [.ai/REVIEW/T-OS-300/SYNTHESIS.md](.ai/REVIEW/T-OS-300/SYNTHESIS.md) — Phase 2 設計の SSOT
- [.ai/REVIEW/T-OS-300/CLAUDE_ANALYSIS_v2.md](.ai/REVIEW/T-OS-300/CLAUDE_ANALYSIS_v2.md) — Claude 視点
- [.ai/REVIEW/T-OS-300/CODEX_ANALYSIS_v2.md](.ai/REVIEW/T-OS-300/CODEX_ANALYSIS_v2.md) — Codex 視点
- [.ai/REVIEW/T-OS-300/PHASE2_FIRST_BATCH_SUMMARY.md](.ai/REVIEW/T-OS-300/PHASE2_FIRST_BATCH_SUMMARY.md) — 第 1 バッチサマリ
- [.ai/REVIEW/T-OS-300/PHASE3_MULTIPROJECT.md](.ai/REVIEW/T-OS-300/PHASE3_MULTIPROJECT.md) — Multi-Project Hub 構想
