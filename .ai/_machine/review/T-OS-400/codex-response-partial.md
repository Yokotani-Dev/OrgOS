# Codex 視点: OrgOS 理想形批評 — PARTIAL (T-OS-402)

> ⚠️ 復元注意: `scripts/codex/run-in-worktree.sh` の wrapper bug により、
> worktree 内に生成された codex-response.md は cleanup で削除された。
> 以下は streaming 出力から復元した tail 200 行 (セクション 4-E 以降 + Handoff Packet)。
> セクション 1-3 + セクション 4 A-D は失われた。
> 再生成タスクが T-OS-406 として登録され、`--keep-worktree` で再実行する。

---

## 復元できた内容 (raw stream)


Codex 視点では OPA より、まず Python の pure function + YAML rule table で十分。

### E. state machine

**提案**: Request Intake Loop と project phase を FSM として実装する。`KICKOFF -> REQUIREMENTS -> DESIGN -> IMPLEMENTATION -> INTEGRATION -> RELEASE` と、各 transition の required evidence を typed object として持つ。

- 実装難度: M
- 工数: 1-2 週
- 既存資産の流用度: 70%。`CONTROL.yaml` stage、request-intake-loop、journey/quality/domain schemas を利用。
- 期待効果: 「Step 1-10 をやったつもり」をなくし、missing evidence なら stop できる。
- リスク/反対意見: LLM の柔軟な割り込み処理と相性が悪い場合がある。FSM bypass の escape hatch 設計が必要。

これは typed core と同時に入れるべき。FSM 単体では状態がまた YAML drift する。

### F. simplest viable alternative

**提案**: OrgOS を半分捨て、`scripts/org-task` + `scripts/org-validate` + `CHECKLIST.md` に戻す。Manager は Markdown rule を大量に読むのではなく、validated task queue だけを見る。

- 実装難度: S-M
- 工数: 3-5 日
- 既存資産の流用度: 40%
- 期待効果: Owner/Manager の cognitive load を大きく下げる。事故面積が減る。
- リスク/反対意見: OrgOS の「自律エージェント OS」という野心は縮む。既存の eval/evolution 資産はかなり捨てる。

私は全面採用は推さないが、短期 stabilization としては強い。

## 5. Manager 責務分解

| 責務 | 分類 (a/b/c) | 機械化案 |
|---|---|---|
| TASKS/GOALS/DECISIONS の整合性確認 | (a) | `orgos validate-state` で projection/schema/drift を検査 |
| PLAN-UPDATE 番号採番 | (a) | append-only decision writer が採番し、手書き禁止 |
| allowed_paths 衝突判定 | (a) | path matcher を library 化し、task enqueue 時に deps 自動付与 |
| git branch / lock / push / main mutation guard | (a) | pretool + git coordinator に集約。Manager から除去 |
| Codex pre/post audit | (a) | wrapper 必須化を hook で enforce。直接 `codex exec` を deny |
| CAPABILITIES scan | (a) | Tick 開始時ではなく scheduled projection と cache |
| USER_PROFILE / memory secret lint | (a) | schema + secret scanner + CI |
| Journey / Quality Contract の required evidence 判定 | (b) | LLM が内容妥当性を見て、schema は機械が見る |
| risk / reversibility 分類 | (b) | LLM draft + policy engine validation |
| task 分解と deps 設計 | (b) | LLM が候補生成、機械が cycle/path conflict を検査 |
| Owner への質問文生成 | (b) | decision-card schema に沿って LLM が短文化 |
| architecture tradeoff の最終判断 | (c) | Manager/Architect の柔軟判断が必要 |
| Owner の暗黙要求・温度感の解釈 | (c) | 完全機械化しない |
| 例外時の escalation 判断 | (c) | policy で候補を出し、Manager が責任を持つ |

削るべきは (a) の全量。Manager がやるべきではない。Manager は「状態を読む」のではなく「validator の結果を受け取る」だけでよい。

## 6. 直接的反対意見

OrgOS は現状 overengineered である。ただし「全部捨てるべき」ではない。問題は、理想が大きすぎることではなく、理想を Markdown rule と YAML 台帳に分散させたまま runtime core を後追いで足していること。

一番まずいのは、Manager の認知に安全性を依存している点である。`.claude/hooks/pretool_policy.py` はあるが、守れる範囲は Bash/git/Write/Edit の一部に限られる。`CLAUDE.md:11` の最高位 Iron Law と、実際に停止できる runtime boundary の差が大きすぎる。

Owner の「暫定対応が続く」という感覚は正しい。T-OS-371〜378 は必要だったが、設計としては patch set であって kernel ではない。理想形は「rule を増やす」ではなく、「state transition と policy decision を typed core に閉じ込める」こと。

社外 reviewer としての結論:

- Markdown rule は instruction であり control plane ではない。
- YAML ledger は projection であり source of truth ではない。
- Manager は state reconciler ではなく planner であるべき。
- 状態管理は LLM から外し、typed validator / projection / policy engine に寄せるべき。

## 7. アクション提案 (優先順)

1. **typed state validator を作る**
   - 目的: TASKS/GOALS/DECISIONS/CAPABILITIES/USER_PROFILE の drift を stop する。
   - 実装方針: `scripts/state/validate.py` を作り、PyYAML + Pydantic で全 ledger を validate。CI と Tick bootstrap で non-zero exit。
   - 工数: 2-3 日
   - 期待効果: 現在見つかった drift の 70% 以上を自動検出。

2. **`pretool_policy.py` の YAML regex parser を廃止**
   - 目的: CONTROL 読み取りの brittle behavior をなくす。
   - 実装方針: `yaml.safe_load` で CONTROL を読み、top-level/nested flag を typed access。
   - 工数: 0.5-1 日
   - 期待効果: flag 読み落としと comment 制約を除去。

3. **policy decision を pure function 化**
   - 目的: push/main/OS mutation/destructive op の bypass を table-driven test 可能にする。
   - 実装方針: `scripts/policy/core.py` に `decide(command, tool, target, control, branch_state)` を実装し、pretool は thin wrapper にする。
   - 工数: 2-4 日
   - 期待効果: rule vs runtime gap の主要 bypass を閉じる。

4. **Codex direct exec deny を入れる**
   - 目的: wrapper bypass を防ぐ。
   - 実装方針: pretool Bash guard で `codex exec` を検出し、`scripts/codex/run-in-worktree.sh` 経由以外を block。
   - 工数: 0.5 日
   - 期待効果: T-OS-372/373 の wrapper enforcement が実効化。

5. **TASKS/GOALS を projection に寄せる**
   - 目的: active/done/archive/status mismatch をなくす。
   - 実装方針: まず `task_events.jsonl` を追加し、archive/done/status update は event writer からのみ実行。既存 YAML は当面 projection として更新。
   - 工数: 1 週
   - 期待効果: done task 残存、GOALS active vs archive done、missing task refs を消せる。

6. **PLAN-UPDATE writer を作る**
   - 目的: 番号重複と欠番混乱をなくす。
   - 実装方針: `scripts/decisions/add-plan-update.sh` が次番号採番、timestamp、task refs を生成。手書き見出しを CI で禁止。
   - 工数: 1 日
   - 期待効果: DECISIONS の traceability が上がる。

7. **shell script quality gate を CI に入れる**
   - 目的: `set -euo pipefail` 漏れ、shellcheck 未実行をなくす。
   - 実装方針: shellcheck 導入、POSIX script 例外リスト化、10 本の missing を修正。
   - 工数: 1-2 日
   - 期待効果: runtime scripts の failure mode が明確化。

8. **unit tests を最低 30 cases 入れる**
   - 目的: policy/path/state の regressions を防ぐ。
   - 実装方針: pytest で command bypass cases、allowed_paths matcher、TASKS/GOALS drift、PLAN-UPDATE uniqueness をテスト。
   - 工数: 2-3 日
   - 期待効果: 現在の CI の「manifest check」偏重を脱却。

9. **Manager から (a) 責務を削除**
   - 目的: LLM 認知に依存する安全性を減らす。
   - 実装方針: manager.md の Tick flow を「validator 結果を読む」形に置換。Manager が ledger diff を直接推理しない。
   - 工数: 2-3 日
   - 期待効果: Owner が感じる暫定運用感を減らす。

10. **micro-kernel boundary を定義し直す**
    - 目的: OS 自己改修の blast radius を固定する。
    - 実装方針: kernel を `pretool_policy.py`、policy core、state validator、projection writer、git coordinator に限定。rules/agents/templates は userspace。
    - 工数: 1-2 週
    - 期待効果: OS 改修事故の影響範囲を小さくする。

## Handoff Packet

```yaml
handoff_packet:
  schema_version: "1.0"
  task_id: "T-OS-402"
  agent: "codex-implementer"
  status: "DONE_WITH_CONCERNS"
  completed_at: "2026-05-14T10:27:17+09:00"
  trace:
    request_trace_id: "T-OS-402-codex-response"
    span_id: "T-OS-402-codex-response-1"
    attempt: 1
    parent_span_id: null
    resume_of: null
  changed_files:
    - path: ".ai/REVIEW/T-OS-400/codex-response.md"
      summary: "Codex independent critique, inventory, architecture alternatives, action plan, and handoff packet."
  assumptions:
    - statement: "runtime check count は strict/partial を含む conservative count とした。Markdown rule に対応する script/schema があっても、毎 Tick 強制されないものは partial と分類した。"
      confidence: 0.78
      source: "file:.claude/hooks/pretool_policy.py#L540; file:scripts/session/bootstrap.sh#L9"
    - statement: "Work Order が要求した PLAN-UPDATE-022 は .ai/DECISIONS.md に見出しとして存在しなかったため、最新 2026-05-10 decisions と PLAN-UPDATE-021 までを根拠にした。"
      confidence: 0.95
      source: "file:.ai/DECISIONS.md#L32; file:.ai/DECISIONS.md#L1531"
    - statement: "dead code は削除可能断定ではなく orphaned artifact / stale reference として扱った。"
      confidence: 0.82
      source: "file:.claude/agents/manager.md#L170; file:.ai/TASKS.yaml#L904"
  decisions_made:
    - "理想形の最優先は typed core + policy pure function + projection/event log と判断した。"
    - "全面 micro-kernel 化は長期、短期は state validator と pretool parser 改修を優先すべきと判断した。"
  unresolved_questions:
    - "`.ai/CAPABILITIES.yaml` と `.ai/USER_PROFILE.yaml` がこの worktree に存在しないのが意図的な未生成状態か、事故後の欠落かは不明。"
    - "PLAN-UPDATE-022 が別 branch/worktree にある可能性は未確認。manager-vision.md は指示通り読んでいない。"
    - "runtime check count はルールの意味論まで完全に formal verification したものではない。"
  downstream_impacts:
    - task_id: "T-OS-400"
      impact: "SYNTHESIS 時に Manager vision と比較するための独立 Codex critique input。"
    - task_id: "T-OS-380"
      impact: "Tick 統合前に state validator / policy core の導入を検討すべき。"
  memory_updates: []
  verification:
    tests_run: true
    tests_passed: true
    commands:
      - "find .claude/rules -maxdepth 1 -type f | wc -l"
      - "python3 inventory/count script for rules/tasks/archive/PLAN-UPDATE/scripts"
      - "git rev-list --count --since='2026-04-14T00:00:00+09:00' HEAD"
      - "git log --follow --format='%h %ad %s' --date=short -- .claude/hooks/pretool_policy.py"
      - "rg -n 'PLAN-UPDATE-022|add/add|cherry-pick|parallel|並列|2026-05-10' .ai/DECISIONS.md .ai"
      - "nl -ba selected evidence files"
    self_check:
      seven_sections_filled: true
      evidence_file_line_count_at_least_20: true
      manager_vision_read: false
      only_allowed_output_file_changed: true
```

tokens used
202,506
完了しました。指定どおり作成・変更したのは [.ai/REVIEW/T-OS-400/codex-response.md](/Users/youyokotani/Dev/Private/OrgOS/.worktrees/T-OS-402/.ai/REVIEW/T-OS-400/codex-response.md) のみです。

検証結果:
- 7 セクション + Handoff Packet あり
- file:line 根拠 105 件
- `manager-vision.md` は読んでいません
- `git add` / `git commit` / `git push` は未実行
- `git status --short`: `?? .ai/REVIEW/T-OS-400/` のみ
