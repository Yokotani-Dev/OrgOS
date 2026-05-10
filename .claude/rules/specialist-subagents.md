# Specialist Subagents Rule - DESIGN Phase Parallel Review

> DESIGN フェーズで専門家視点を並列投入し、IMPLEMENTATION 前に domain / threat / data / authority の漏れを可視化する。
> Manager は agent の自己報告ではなく、生成された output artifacts を検証して Owner Decision Brief に集約する。

## Purpose

Quality Contract が `quality_level >= mvp` の project / milestone では、DESIGN 完了前に専門観点の抜けを減らす。
Manager は必要な specialist subagents を同一メッセージで並列起動し、各 agent が独立に作った artifact を読んで Decision Brief を提示する。

この rule は dispatcher protocol であり、自動起動実装ではない。Manager 側の dispatcher 実装は別タスクとする。

## Specialist Agents

| Agent | Focus | Output Artifact | Source Rule / Template |
|---|---|---|---|
| `org-domain-analyst` | 法令、業界 policy、platform policy の references と knowledge gaps | `.ai/DOMAIN_ANALYSIS.md` | `.claude/rules/domain-constraint-sync.md`, `.ai/TEMPLATES/DOMAIN_ANALYSIS.md` |
| `org-threat-modeler` | 8 threat categories の該当箇所、scenario、対策観点 | `.ai/DESIGN/THREAT_MODEL.md` | `.claude/rules/pre-implementation-risk-profile.md`, `.ai/TEMPLATES/THREAT_MODEL.md` |
| `org-data-modeler` | ER、状態遷移、不変条件、transaction、idempotency、削除戦略 | `.ai/DESIGN/DATA_MODEL_FULL.md` | `.ai/TEMPLATES/DATA_MODEL_FULL.md` |
| `org-security-architect` | role x resource matrix、RLS、RPC、認証境界、session、audit | `.ai/DESIGN/AUTHORITY_BOUNDARY.md` | `.ai/TEMPLATES/AUTHORITY_BOUNDARY.md` |

## Launch Conditions

Manager MUST consider this rule when all conditions are true.

1. Current phase is `DESIGN`.
2. Quality Contract exists and `quality_level >= mvp`.
3. Work includes a project, milestone, feature, or subsystem that will enter IMPLEMENTATION.
4. Required DESIGN artifacts are missing, draft, stale, or need specialist confirmation.

Manager SHOULD NOT launch specialist agents for pure documentation copy edits, typo fixes, already-confirmed artifact formatting, or tasks explicitly scoped below `mvp`.

## Selection Logic

Select the smallest agent subset that covers project risk.

| Project Type | Trigger Signals | Agents To Launch |
|---|---|---|
| regulated domain | regulated category, platform policy dependency, payment, PII, sensitive claim, ads, app store, finance, medical, real estate, education, gaming, dating, crypto | all 4 agents |
| transactional system | create/update/delete workflows, payments, booking, inventory, state transitions, retryable jobs, webhooks, multi-table writes | `org-threat-modeler`, `org-data-modeler`, `org-security-architect` |
| read-only public site | public content, no login, no write path, no PII collection, no protected admin path in scope | `org-threat-modeler` only |
| internal tool | authenticated operators, admin workflows, private data, no regulated external distribution in scope | `org-security-architect` only |

If multiple rows match, use the broader set.
If the classification is uncertain, launch `org-threat-modeler` and record the uncertainty in the Decision Brief.

## Parallel Launch Procedure

Manager launches selected agents in one delegation step.
For the full regulated-domain set, the same Manager message MUST include four Task tool calls:

1. `org-domain-analyst`
2. `org-threat-modeler`
3. `org-data-modeler`
4. `org-security-architect`

Each Task prompt MUST include:

- project / milestone identifier
- Quality Contract reference
- relevant BRIEF / JOURNEYS / ARCHITECTURE / API_CONTRACT paths
- existing draft artifact paths, if any
- allowed output artifact for that agent
- explicit instruction that agents work independently and do not wait for each other

Agents may read existing drafts, but they must not depend on another concurrently running agent finishing first.

## Failure Handling

Agent failure is `log_only` for `quality_level=mvp`.
Manager records the failed agent, reason, and missing artifact in the Decision Brief, then falls back to Manager-authored draft for the missing artifact or blocks DESIGN if the missing artifact is gate-critical.

Suggested structured log:

```yaml
event: "specialist_subagent_run"
phase: "DESIGN"
quality_level: "mvp"
project_id: "TODO"
milestone_id: "TODO"
selected_agents:
  - "org-domain-analyst"
  - "org-threat-modeler"
  - "org-data-modeler"
  - "org-security-architect"
agent_results:
  org-domain-analyst: "success|failed|skipped"
  org-threat-modeler: "success|failed|skipped"
  org-data-modeler: "success|failed|skipped"
  org-security-architect: "success|failed|skipped"
specialist_coverage:
  selected_count: 4
  succeeded_count: 0
  required_artifacts_present: false
  missing_artifacts: []
decision: "continue|fallback|block_design"
```

## Aggregation Protocol

After all selected agents return or fail, Manager MUST read the output artifacts directly.

1. Verify each selected agent's expected output artifact exists.
2. Verify artifact status, coverage fields, and required sections.
3. Compare cross-artifact consistency:
   - DOMAIN_ANALYSIS prohibited / required practices appear in downstream DESIGN constraints.
   - THREAT_MODEL covers all 8 categories.
   - DATA_MODEL_FULL includes ER, invariants, transaction boundaries, idempotency keys, and delete strategy.
   - AUTHORITY_BOUNDARY includes role matrix, RLS / alternative enforcement, RPC permissions, auth boundaries, session management, and audit logs.
4. Prepare Owner Decision Brief with decisions needed, open risks, open knowledge gaps, and blocked gates.
5. Do not advance to IMPLEMENTATION until required gates from `domain-constraint-sync.md`, `pre-implementation-risk-profile.md`, and `quality-contract.md` pass.

## Decision Brief Requirements

Owner Decision Brief MUST include:

- selected specialist agents and why they were selected
- artifact status summary
- unresolved knowledge gaps
- open threats / consistency risks
- authority contradictions
- required Owner decisions
- whether DESIGN can proceed, needs fallback drafting, or must block

Manager MAY include this structured metric for Quality Eval:

```yaml
specialist_coverage:
  launch_condition_met: true
  selection_reason: "regulated_domain|transactional_system|read_only_public_site|internal_tool|manual"
  selected_agents: []
  succeeded_agents: []
  failed_agents: []
  artifacts_verified:
    domain_analysis: "confirmed|draft|missing|not_selected"
    threat_model: "confirmed|draft|missing|not_selected"
    data_model_full: "confirmed|draft|missing|not_selected"
    authority_boundary: "confirmed|draft|missing|not_selected"
  coverage_complete: false
```

## Iron Law

1. **Agent 自己報告を信用しない** - Manager は completion message ではなく output artifacts を読む。
2. **4 output artifacts を verify する** - full regulated-domain launch では `.ai/DOMAIN_ANALYSIS.md`、`.ai/DESIGN/THREAT_MODEL.md`、`.ai/DESIGN/DATA_MODEL_FULL.md`、`.ai/DESIGN/AUTHORITY_BOUNDARY.md` を直接確認する。
3. **専門 agent を chain しない** - 各 agent は独立に起動し、他 agent の未生成 output を待たない。
4. **自動起動をここに実装しない** - この file は dispatcher rule であり、Task tool 呼び出し実装や model hardcode を含めない。
5. **DESIGN gate を緩めない** - agent failure を log_only にしても、gate-critical artifact の欠落は Manager fallback または DESIGN block で処理する。
6. **selection を記録する** - 起動した agent と起動しなかった agent の理由を Decision Brief に残す。

## Out Of Scope

- Manager dispatcher の自動起動実装
- 業界別 specialized agent の追加
- model name の hardcode または agent alias 以外の選定固定
- agent 間の chain-of-thought 共有
- IMPLEMENTATION の開始判断を agent に委譲すること
