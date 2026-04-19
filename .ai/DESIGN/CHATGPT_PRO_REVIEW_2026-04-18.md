# ChatGPT Pro レビュー結果 — OrgOS ToBe v1 (2026-04-18)

> レビュー依頼元: .ai/DESIGN/ORGOS_TOBE_REVIEW_PROMPT.md
> 被レビュー: .ai/DESIGN/ORGOS_TOBE.md (v1)
> レビュワー: ChatGPT Pro
> 総合判定: **△ (要修正)**

---

## 総合判定: △

方向性は正しい（「作業実行能力不足」ではなく「記憶・文脈・能力認識・ヒアリング設計の欠落」と捉えた点は妥当）。
ただし、現 ToBe はまだ **"4 レイヤーを足す設計"** に留まっており、Manager を本当に Manager 化するための **状態機械、権限設計、記憶のライフサイクル、評価指標、委譲プロトコル** が足りない。

---

## 診断の再定義（Pro 提案）

> 根本原因は「Manager が Owner の代理人として意思決定するための、**永続状態・能力認識・文脈接続・ヒアリング・権限・評価の制御ループ** を持っていないこと」。

4 空白層に加えて、以下 3 つを **必須欠落** として追加すべき:

1. **Authority / Risk Layer** — 何を自律実行してよいか、何は承認が必要か、何は禁止か
2. **Evaluation Layer** — 「Owner に聞かずに済んだ率」「聞き直し率」「文脈逸脱率」「手戻り率」「Owner 負荷削減率」
3. **Execution State Machine** — 受付 → 文脈取得 → 能力探索 → リスク判定 → 実行/確認 → 検証 → 記録、の固定ループ

---

## MAOPA → MAOPAS-E に拡張

Safety と Evaluation を独立の柱として追加:

| 柱              | 内容                        |
| -------------- | ------------------------- |
| Memory         | 過去資産を保持・検索・更新・破棄する        |
| Awareness      | 現在のプロジェクト状態と依頼の位置づけを把握する  |
| Optionality    | Owner に頼る前に代替手段を探索する      |
| Partnership    | 必要な時だけ、良い問いで Owner を巻き込む  |
| Accountability | 実行・判断・根拠・結果を追跡可能にする       |
| Safety         | 秘密情報・権限・破壊的操作・課金操作を制御する   |
| Evaluation     | Manager らしさを継続評価し、退行を検知する |

**Chief of Staff + Workflow Controller** メタファーに更新。

---

## 設計の穴（各層別）

### USER_PROFILE.yaml の穴

v1 提案は危険。以下が必要:
- `credentials` に実体や推測可能な情報を置かない
- preference と fact と secret と decision を分離
- scope, confidence, source, expires_at, last_verified を必須フィールド化
- 「覚えていること」が間違っていた場合の修正・失効ルール

**改善案（fact registry 型）:**
```yaml
facts:
  - id: fact_supabase_project_ref_default
    type: project_resource
    value_ref: "project_abc123"
    scope: "project:orgos"
    source: "owner_confirmed"
    source_ref: "past_qa:2026-03-15"
    confidence: 1.0
    valid_from: "2026-03-15"
    expires_at: null
    pii_level: "low"
    secret: false

secrets:
  - id: secret_supabase_access
    service: "supabase"
    scope: "project:abc123"
    storage: "1password://OrgOS/Supabase abc123"
    materialized: false
    last_verified_at: "2026-04-18"
    rotation_policy: "manual"

preferences:
  - id: pref_cli_over_gui
    statement: "CLI > GUI"
    scope: "global"
    source: "owner_confirmed"
    confidence: 0.9
    overridable: true
```

**重要**: 秘密そのものではなく **secret pointer** を保存する。

### CAPABILITIES.yaml の穴

tool manifest に近づけるべき:
```yaml
capabilities:
  - id: cli_supabase
    kind: cli
    command: "supabase"
    status: "available"
    auth_status: "verified"
    verified_at: "2026-04-18"
    risk_level: "medium"
    supports_dry_run: false
    owner_approval_required_for:
      - "delete"
      - "db reset"
      - "billing"
    common_operations:
      - name: "get_project_api_keys"
        command_template: "supabase projects api-keys --project-ref ${project_ref}"
        required_inputs: ["project_ref"]
        input_resolution_order:
          - "USER_PROFILE.facts"
          - "ENV"
          - "Owner"
```

**MCP 互換の tool/resource manifest** として設計することで将来の相互運用性を確保。

### Coherence Layer の 3 段階表示

| モード         | 条件               | 応答                |
| ----------- | ---------------- | ----------------- |
| Silent Bind | grep、format、単純確認 | 内部で文脈参照、表示しない     |
| Brief Bind  | 進行中タスクに関係あり      | 1 行だけ位置づけを書く      |
| Full Bind   | 方針・仕様・優先順位に影響    | 背景、影響、選択肢、推奨を明示   |

また **write-time** にも効かせる（単発依頼の結果が TASKS / DECISIONS に反映されるべきかを判定）。

### Inquiry Layer: 認知負荷予算モデル

質問数ではなく認知負荷予算で設計:
```yaml
inquiry_policy:
  max_questions_per_turn: 3
  max_cognitive_load: "low"
  ask_only_if:
    - "irreversible_action"
    - "security_or_billing_risk"
    - "owner_preference_unknown_and_material"
    - "multiple_valid_paths_with_high_downstream_cost"
  do_not_ask_if:
    - "answer_exists_in_memory"
    - "answer_can_be_discovered_by_cli_or_api"
    - "assumption_is_reversible_and_low_cost"
```

大規模要件定義は 4 フェーズ分割:
1. Goal framing — 成功状態だけ聞く
2. Constraint framing — 制約だけ聞く
3. Decision framing — 重要な分岐だけ聞く
4. Spec confirmation — Manager が仕様ドラフト → Owner は差分修正

---

## 6 盲点への Pro 回答（要約）

| # | 盲点 | Pro の回答 |
|---|------|-----------|
| 1 | PII | 平文 YAML に secret 不可。secret_ref + Keychain/1Password/SOPS。`.ai/` は原則 gitignore。pre-commit scanner。 |
| 2 | Coherence コスト | 毎回 bind、表示は 3 段階（Silent/Brief/Full） |
| 3 | 大規模ヒアリング | 仮仕様ドラフト + 差分確認方式 |
| 4 | 誤転移 | Global / Domain / Project の 3 層 + `transferability` フィールド |
| 5 | マルチ Owner | PMO + Chief of Staff。stakeholder registry + decision rights matrix |
| 6 | ChatGPT Pro 分担 | Pro = 外部戦略レビュー / 設計批評。Manager = 実行 OS / 台帳 / 継続運用。redacted context pack を作る |

---

## Manager が自覚していない最大の盲点（Pro 指摘）

### 1. 「Manager の評価関数」がない（最大の穴）

```yaml
manager_quality_metrics:
  repeated_question_rate:
    target: "< 5%"
  owner_delegation_burden:
    target: "downward trend"
  context_miss_rate:
    target: "< 3%"
  unnecessary_owner_question_rate:
    target: "< 10%"
  capability_reuse_rate:
    target: "> 80%"
  decision_trace_completeness:
    target: "> 95%"
```

特に `repeated_question_rate` と `context_miss_rate` は **P0**。

### 2. 「委譲プロトコル」がない

subagent 間の handoff 契約が弱い。症状 B の本質的原因。

各 subagent に Handoff Packet を返させる:
```yaml
handoff_packet:
  task_id: "T-OS-121"
  assumptions: ["..."]
  changed_files: ["..."]
  decisions_made: ["..."]
  unresolved_questions: ["..."]
  downstream_impacts: ["..."]
  memory_updates: ["..."]
```

### 3. 「記憶の失効・訂正・昇格」がない

必要な操作は CRUD ではなく:
```
capture → normalize → scope → retrieve → validate → retire/promote
```

---

## 修正版ロードマップ（Pro 提案）

| Phase | 内容 | 目安 | 目的 |
|-------|------|------|------|
| 0 | **Manager Quality Eval 作成** | 0.5〜1 日 | 改善前後を測る基盤 |
| 1 | Safe Memory 最小実装 | 2〜3 日 | past_qa / preference / resource を安全に再利用 |
| 2 | Capability Preflight | 1〜2 日 | Owner に聞く前に CLI/API/MCP を探索 |
| 3 | Request Intake State Machine | 2〜3 日 | 文脈 bind + risk 判定 + inquiry を一体化 |
| 4 | Handoff Packet + Trace | 2〜3 日 | subagent 間の文脈断絶を防ぐ |
| 5 | org-evolve への regression 統合 | 継続 | 退行防止 |

### Request Intake Loop（10 ステップ）
```
1. Intake
2. Load relevant memory
3. Bind active work graph
4. Discover capabilities
5. Classify risk / reversibility
6. Decide: act / ask / defer / refuse
7. Execute with trace
8. Verify
9. Update TASKS / DECISIONS / MEMORY
10. Report with minimal cognitive load
```

---

## 代替アプローチ（Pro 提案 3 つ）

### 1. Context Engineering OS
OrgOS の本質を「agent の人格設計」ではなく、**LLM に渡す文脈を構造化・選別・検証・更新する OS** として捉える。

### 2. Work Graph + Autonomy Boundary Model
各タスクに **自律可能度** と **承認境界** を持たせる:
```yaml
task:
  id: "T-OS-121"
  autonomy_level: "execute_with_report"
  approval_required_for: ["production deploy", "schema migration", "billing change"]
  owner_input_needed: ["business priority only"]
```

### 3. Memory Graph / Temporal Knowledge Graph
USER_PROFILE.yaml や DECISIONS.md を時間・人物・プロジェクト・決定・リソースを結ぶ **knowledge graph** として扱う。
Zep の temporal knowledge graph architecture 参考。

---

## 優先度付き推奨アクション

### [P0] 今週中
1. **Safe Memory 方針を先に確定** — secret pointer / scope / source / confidence / expires_at / pii_level を必須化
2. **Manager Quality Eval を作る** — Owner の不満を 20 ケースの regression suite 化
3. **Request Intake Loop を 1 枚に定義** — Iron Law 化

### [P1] 2 週間以内
4. **Capability Preflight 実装** — tool manifest (auth_status, dry-run, risk)
5. **Handoff Packet を全 subagent に強制** — 成果 + 仮定 + 未解決 + 下流影響 + memory update

### [P2] 1 ヶ月以内
6. **Context Pack Builder** — ChatGPT Pro/Codex/subagent 用 redacted export
7. **Temporal Memory / Graph Memory 移行検討** — project 数が増えるなら

---

## 最終コメント（Pro 原文）

> この ToBe 提案は、**方向はかなり良い**。特に「自律 ≠ 独断」と言語化した点は重要。
>
> ただし、今のまま実装すると、おそらく次の失敗になる:
>
> **"よく覚えているふりをするが、記憶の信頼性・権限・スコープ・失効を管理できない Manager"**
>
> 次の設計原則に置き換えるべき:
>
> **OrgOS Manager は、Owner の認知負荷を最小化しながら、検証可能な文脈・能力・権限・記憶に基づいてプロジェクトを前進させる制御システムである。**
>
> そのための最優先は、Chief of Staff の人格づくりではなく、**Safe Memory、Capability Preflight、Request Intake State Machine、Manager Quality Eval**。

---

## 参照文献（Pro 提示）

1. [TheAgentCompany](https://arxiv.org/html/2412.14161v2) — 実務環境 agent benchmark
2. [Mem0: Scalable Long-Term Memory](https://arxiv.org/abs/2504.19413) — memory-centric architecture
3. [A-MEM: Agentic Memory for LLM Agents](https://arxiv.org/abs/2502.12110) — Zettelkasten 的記憶進化
4. [Model Context Protocol](https://modelcontextprotocol.io/specification/2025-11-25) — Resources/Prompts/Tools/Elicitation 標準
5. [LangGraph Durable Execution](https://docs.langchain.com/oss/python/langgraph/durable-execution) — 状態機械 + checkpointer
6. [OpenAI Agents SDK Tracing](https://openai.github.io/openai-agents-python/tracing/) — LLM 生成/tool call/handoff/guardrail 記録
7. [Zep: Temporal Knowledge Graph for Agent Memory](https://arxiv.org/abs/2501.13956) — cross-session synthesis
8. [Memory Management Empirical Study](https://arxiv.org/abs/2505.16067) — 選択的追加・削除の重要性
9. [How Well Does Agent Development Reflect Real-World Work?](https://arxiv.org/html/2603.01203v1) — タスク複雑度別自律境界

---

## Manager の受容メモ

Pro が指摘した以下 3 点は、Manager (Claude Opus 4.7) が完全に見逃していた本質的盲点:

1. **評価関数の不在** — 「Manager らしさ」を測る指標を作っていなかった
2. **委譲プロトコルの弱さ** — subagent 間の handoff packet を標準化していなかった
3. **記憶ライフサイクルの欠如** — capture しか設計しておらず、retire/promote/validate が未考慮

この 3 点は TASKS.yaml の新規タスク（T-OS-150〜154）として P0/P1 登録する。
