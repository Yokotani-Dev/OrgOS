# Phase 2 First Batch — 完了サマリ (2026-05-08)

> Owner 不在中に Manager が自走で実施。全 4 タスク完了。

## 完了タスク一覧

| ID | Title | Status | 主成果物 |
|---|---|---|---|
| T-OS-310-cleanup | Deprecated agent 削除 + manifest 完全化 | ✅ DONE | `org-implementer.md` 物理削除、manifest 23 rule 完備 |
| T-OS-320 | Evolution Event Store + Detector v1 | ✅ DONE | 7 scripts、初回 81 events 検出 |
| T-OS-321 | OWNER_INBOX → Decision Table | ✅ DONE | format 転換、test 残滓 4 件 archive |
| T-OS-321b | OWNER_INBOX helper scripts | ✅ DONE | add/list/expire/archive 4 scripts |
| T-OS-322 | TASKS autonomy metadata backfill | ✅ DONE | 48 タスク 100% backfill |

## 実施タイムライン

- **2026-05-01**: 4 タスクを Codex で並列起動 → Owner PC 電池切れで network 断 → 3 タスク中断、1 タスク (cleanup) 完走
- **2026-05-08**: 中断分 (T-OS-320, 322) を再実行 + T-OS-321b (T-OS-321 残作業) を新設して並列実行 → 全完了

## 各タスクの達成内容

### T-OS-310-cleanup (2026-05-01 完了)

- `.claude/agents/org-implementer.md` 物理削除 (DEPRECATED で名指しされていた)
- `.orgos-manifest.yaml` の rules: を 23 件全部に更新 (旧: 9 件のみ列挙 → 14 件未配布だった)
- 副次発見: `.claude/rules/user-journey-sync.md` が untracked、24 番目 rule にすべきか要判断 (本タスク範囲外)

### T-OS-320 (2026-05-08 完了): Evolution Event Store + Detector v1

**作成ファイル**:
- `scripts/evolution/detect.sh` — 統合 entry point (--json / --stdout / --scanner)
- `scripts/evolution/scanners/eval-scanner.sh` — Manager Quality eval 結果から event 化
- `scripts/evolution/scanners/capability-scanner.sh` — CAPABILITIES.yaml の auth_status / verified_at 検査
- `scripts/evolution/scanners/oip-scanner.sh` — OIP の Draft 14 日経過検出
- `scripts/evolution/scanners/memory-scanner.sh` — memory lint からの正規化
- `scripts/evolution/scanners/intel-scanner.sh` — INTELLIGENCE/raw/ の最終更新検査
- `scripts/evolution/list-events.sh`, `dedupe-events.sh` — helper
- `.claude/schemas/evolution-event.yaml` — schema
- `.ai/EVOLUTION/events.jsonl` — event store (初回 81 events 蓄積)

**初回実行結果** (`bash scripts/evolution/detect.sh --json`):
```
event_types:
  eval_regression: 1     ← Phase 1 ISS-CLD-028 を再検出
  ux_drift: 1            ← daily-health-check 19 日停止
  capability_degraded: 68 ← verified_at 古い capability
  oip_stale: 2           ← OIP 3 ヶ月停止
  rule_stale: 8          ← Phase 1 ISS-CLD-022 等
  intel_stale: 1         ← INTELLIGENCE 空
```

**Phase 1 で予測した「自律進化があれば未然防止できた 13 課題」のうち、即座に 10+ 件を再検出**。Phase 2 ROI の根拠が早速立証されました。

### T-OS-321 + 321b (2026-05-08 完了): OWNER_INBOX Decision Console 化

**OWNER_INBOX.md** が Decision Table format に転換:
- 旧 4 件のテスト残滓 (T-TEST / T-TEST-NOWAIT / T-TEST-EXPIRE) を `## Archived` に移動 (status: expired)
- pending Card は **0 件** (test 残滓が全て resolve されたため)
- 各 Card は recommendation / risk / default_if_no_response / deadline 必須

**`.claude/schemas/decision-card.yaml`**: 新規作成、決済 Card の SSOT schema

**scripts/inbox/** (4 + 1):
- `add-decision.sh` — 新規 Card 作成 (自動 ID 発番)
- `list-pending.sh` — 表形式表示 (`--json` 対応)
- `expire-old.sh` — deadline 超過の自動処理 (default_if_no_response に基づく)
- `archive.sh` — resolved/expired を Archived へ移動
- `inbox.py` — shared lib (YAML parse + schema validation)

### T-OS-322 (2026-05-08 完了): TASKS autonomy metadata backfill

- **48 active tasks 100% backfill** (Rule 1=10 / Rule 2=9 / Rule 3=5 / Rule 5=1 / Rule 6=23)
- `.claude/schemas/autonomy.yaml`: schema 拡張
- `scripts/authority/check-autonomy-coverage.sh`: coverage 検査スクリプト (`--json` 対応)
- coverage check **PASS** (missing_count: 0)

これで Manager は task ごとに `autonomy_level` を deterministic に判定可能。Phase 2 の application engine (T-OS-326) が autonomy に従って silent_execute / canary / Owner approval を分岐する基盤が整備されました。

## Owner 体験への効果 (1 回目時点)

1. **OWNER_INBOX が Decision Table 化** — pending 0 件 (テスト残滓を排除済)
2. **検出機構が稼働** — 81 events を毎日生成可能、daily-health 19 日停止も即検出
3. **Authority Layer の runtime 接続** — Manager が「Owner に聞きすぎ」を構造的に解消する基盤
4. **Self-Evolution Engine の入口開通** — 次の T-OS-323 (DNA) と T-OS-324 (Auto-OIP) が着手可能

## 次の P0 タスク (Phase 2 残り)

| ID | Title | 想定工数 | Dep |
|---|---|---|---|
| T-OS-323 | DNA v0.1 schema + manifest generation | 2 weeks | なし |
| T-OS-324 | Synthesis: proposal format + peer review | 2 weeks | T-OS-320 ✅ |
| T-OS-325 | Validation harness: synthetic Owner + fixture-response eval | 3 weeks | Manager Quality Eval |
| T-OS-326 | Application engine: shadow/canary/full rollout | 3 weeks | Authority + T-OS-325 |
| T-OS-327 | Adaptive Capability Probe | 2 weeks | T-OS-323 |
| T-OS-328 | Intelligence freshness pipeline | 2 weeks | INTELLIGENCE/config.yaml |
| T-OS-329 | Always-On shadow scheduler | 1 week | T-OS-326 |
| T-OS-330 | Marketplace DNA import/export | 4 weeks | T-OS-323 |
| T-OS-331 | Evolution Dashboard / AI Evolution Trace | 2 weeks | T-OS-320 ✅ + T-OS-326 |

T-OS-323 と T-OS-324 は **依存解消済**で即着手可能です。

## 副次発見

- `.claude/rules/user-journey-sync.md` が untracked。24 番目 rule にすべきか Owner 判断 (T-OS-310-cleanup の handoff_packet で escalate)
- daily-health-check が 19 日停止中 (T-OS-320 が即検出)。`scripts/evolve/daily-health-check.sh` を schedule する必要あり (T-OS-329 候補)
- capability_degraded 68 件 = verified_at 19 日経過。`scripts/capabilities/scan.sh` の cron 化が必要 (T-OS-327 候補)

## 検証済みコマンド (Owner 確認用)

```bash
# Self-Evolution Engine の動作確認
bash scripts/evolution/detect.sh --json
bash scripts/evolution/list-events.sh 10

# Decision Table 動作確認
bash scripts/inbox/list-pending.sh

# Autonomy coverage 確認
bash scripts/authority/check-autonomy-coverage.sh
```

## Owner Action 不要

本サマリは記録目的。次は Owner 承認後に T-OS-323〜331 へ進みます。承認なら `/org-tick` で次タスクを起動します。
