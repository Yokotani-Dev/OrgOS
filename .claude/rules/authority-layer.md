# Authority Layer

> Authority / Risk Layer は OrgOS Manager の Step 5-6 を機械的に閉じるための解釈補則である。既存の禁止条項を破らず、自律実行の境界を定義する。

## Purpose

- Request Intake Loop Step 5 (Classify Risk / Reversibility) の出力を Step 6 (Decide) の実行権限に還元する
- `allow_os_mutation=true` と `AGENTS.md` の OS 保護条項の矛盾を、既存ファイル非改変で解消する
- Work Graph に `autonomy_level` と `approval boundary` を持ち込み、Pro 提案の Work Graph + Autonomy Boundary Model を反映する

## Positioning

- 本ファイルは `AGENTS.md` の趣旨を上書きしない
- 本ファイルは `AGENTS.md` の「OS 中核ファイル保護」を具体化する解釈補則として機能する
- 既存の binary gate (`allow_*`) は最上位の safety gate として維持する
- `autonomy_level` は binary gate を通過した後の execution boundary として扱う

## Core Model

### Autonomy Levels

```yaml
autonomy_levels:
  - id: silent_execute
    description: Manager 完全自律実行、Owner 通知不要
    applicable_to:
      - reversibility: reversible
      - cost: low
      - security: none
      - scope: local
    examples:
      - grep
      - format
      - lint

  - id: execute_with_report
    description: Manager 自律実行、完了時に簡潔報告
    applicable_to:
      - reversibility: reversible
      - cost: low
      - security: low
    examples:
      - new_file_creation
      - scripts_memory_edit
      - local_rule_extension_in_allowed_boundary

  - id: ask_before_execute
    description: Owner に推奨付きで問い合わせ、承認後実行
    applicable_to:
      - reversibility: irreversible
      - security: medium_or_higher
      - cost: medium_or_higher
    examples:
      - db_migration
      - external_api_call
      - production_like_push

  - id: owner_only
    description: Owner のみが実行可能。Manager は提案・準備のみ行う
    applicable_to:
      - destructiveness: external
      - security: high
      - legal_billing_compliance: true
    examples:
      - production_deploy
      - data_deletion
      - contract_approval
```

### OS Mutation Protocol

`allow_os_mutation=true` は OS 改修の blanket permit ではない。以下の protocol に一致する場合のみ、Manager は OS 領域の変更を計画できる。

```yaml
os_mutation_protocol:
  control_flag: allow_os_mutation

  allowed_when_os_mutation_true:
    - new_file_in_claude_rules
    - new_file_in_claude_schemas
    - new_script_in_scripts
    - edit_existing_claude_rules_new_since_epoch
    - update_gitignore_add_only

  requires_owner_approval:
    - edit_claude_md
    - edit_manager_md
    - edit_agents_md
    - edit_control_yaml_non_runtime_fields
    - delete_existing_rule

  always_forbidden:
    - edit_kernel_files
    - bypass_eval
    - disable_rationalization_prevention

  preflight:
    - dry_run: diff 内容を確認
    - approval: ask_before_execute level 以上なら review task を生成
    - backup: 変更前を .ai/BACKUPS/ に保存

  postflight:
    - verify: eval で変更内容を検証
    - record: DECISIONS.md に OS-MUTATION-XXX として記録
    - rollback_ready: git commit で rollback 可能な状態にする
```

### Role Matrix

```yaml
role_matrix:
  owner:
    can_edit:
      - all
    approvals_required: none

  manager:
    can_edit:
      - .ai/*
      - os_mutation_protocol.allowed_when_os_mutation_true when allow_os_mutation=true
    approvals_required:
      - os_mutation_protocol.requires_owner_approval

  codex_implementer:
    can_edit:
      - allowed_paths_only
    approvals_required:
      - edits_outside_allowed_paths_forbidden
    read_only:
      - .env
      - .ai/DECISIONS.md
      - .ai/TASKS.yaml
      - .ai/CONTROL.yaml

  codex_reviewer:
    can_edit:
      - .ai/CODEX/RESULTS/*R.md
    approvals_required:
      - code_edit_forbidden
    read_only:
      - review_target_files

  subagent_org_reviewer:
    can_edit:
      - .ai/REVIEW/
    read_only:
      - source_files
```

### Approval Workflow

```yaml
approval_workflow:
  manager_initiated:
    steps:
      1: Manager が Work Order と予想影響を作成
      2: Owner Inbox に review request を記載
      3: Owner が OWNER_COMMENTS.md で approve, reject, modify を返す
      4: Manager が Owner 判断を反映して実行
    timeout: Owner 不在 24 時間で silent_execute 以下に downgrade

  emergency:
    condition: P0 障害かつ Owner 不在
    action: allow_os_mutation=true と auto-recovery script を前提に最小復旧のみ許可
    log: DECISIONS.md に EMERGENCY-XXX として必ず記録
```

### Risk To Autonomy Mapping

Step 5 の risk/reversibility は、Step 6 で次の autonomy level に還元する。

| Risk | Reversibility | Autonomy Level |
|---|---|---|
| low | reversible | `silent_execute` |
| low | irreversible | `execute_with_report` |
| medium | reversible | `execute_with_report` |
| medium | irreversible | `ask_before_execute` |
| high | reversible | `ask_before_execute` |
| high | irreversible | `owner_only` |
| critical | `*` | `owner_only` |
| os_mutation_in_core | `*` | `owner_only` |
| os_mutation_in_new | reversible | `execute_with_report` |

#### Mapping Rules

```yaml
risk_to_autonomy_rules:
  - condition: risk == critical
    autonomy_level: owner_only

  - condition: operation == os_mutation_in_core
    autonomy_level: owner_only

  - condition: operation == os_mutation_in_new AND reversibility == reversible
    autonomy_level: execute_with_report

  - condition: risk == high AND reversibility == irreversible
    autonomy_level: owner_only

  - condition: risk == high AND reversibility == reversible
    autonomy_level: ask_before_execute

  - condition: risk == medium AND reversibility == irreversible
    autonomy_level: ask_before_execute

  - condition: risk == medium AND reversibility == reversible
    autonomy_level: execute_with_report

  - condition: risk == low AND reversibility == irreversible
    autonomy_level: execute_with_report

  - default:
      autonomy_level: silent_execute
```

## ISSUE-OS-001 Resolution Policy

ISSUE-OS-001 の解消方針は次の通り。

1. `AGENTS.md` の「`.claude/** 編集禁止`」は OS 中核ファイル保護を目的とする
2. `allow_os_mutation=true` かつ `os_mutation_protocol.allowed_when_os_mutation_true` に一致する操作は、OS 進化のための限定例外として扱う
3. それ以外の `.claude/**` 編集は禁止のまま維持する
4. `CLAUDE.md`、`.claude/agents/manager.md`、`AGENTS.md`、`.ai/CONTROL.yaml` の非 runtime 項目、既存ルール削除は approval boundary を超えるため Owner 承認が必要
5. `KERNEL_FILES`、eval bypass、合理化防止の無効化は常時禁止である

この解釈により、既存禁止条項を維持したまま「OS 自己進化のための新規追加」と「中核の保護」を両立させる。

## Integration With Request Intake Loop

`request-intake-loop.md` は本タスクでは編集しない。統合方法のみ本ファイルで規定する。

### Step 5 Integration

- Step 5 で `risk`, `reversibility`, `security`, `destructiveness`, `cost` を分類する
- OS mutation の場合は通常リスクに加え `mutation_scope = core | new` を付与する
- `CONTROL.yaml` の `allow_*` を先に評価し、flag が false の場合は autonomy 判定前に `refuse` 候補とする

### Step 6 Integration

- Step 5 の reduction result を `risk_to_autonomy_rules` に通す
- 各 task / work order frontmatter に `autonomy_level` を保持できるようにする
- Work Graph node は少なくとも以下を持つ

```yaml
task_execution_boundary:
  autonomy_level: execute_with_report
  approval_required_for:
    - production_deploy
    - schema_migration
    - billing_change
  owner_input_needed:
    - business_priority_only
```

- Step 6 の `act / ask / defer / refuse` は autonomy level から次のように導出する

| Autonomy Level | Step 6 Outcome |
|---|---|
| `silent_execute` | `act (silent)` |
| `execute_with_report` | `act (report)` |
| `ask_before_execute` | `ask` |
| `owner_only` | `ask + defer` または `refuse` |

### Decision Precedence

```yaml
decision_precedence:
  - always_forbidden
  - control_flags
  - risk_reduction
  - risk_to_autonomy_rules
  - approval_workflow
```

`autonomy_level` は gate bypass 手段ではない。常に `always_forbidden` と `allow_*` 判定の後段で評価する。

## Retrofit Strategy For Existing Tasks

### Scope

T-OS-110 から T-OS-170 までの既存タスクに対し、後付けで `autonomy_level` を付与する。

### Retrofit Rules

```yaml
retrofit_strategy:
  classification_order:
    - inspect_changed_paths
    - inspect_operation_type
    - inspect_existing_allow_flags
    - derive_risk_and_reversibility
    - assign_autonomy_level

  default_policy:
    docs_and_local_rules_new_file: execute_with_report
    schema_addition_under_claude_schemas: execute_with_report
    eval_or_lint_readonly: silent_execute
    shared_ledger_edit: owner_only
    existing_core_rule_edit: ask_before_execute
    deploy_or_push_main: owner_only
```

### Priority

1. T-OS-150〜170 を先に付与する
2. T-OS-121 / 122 / 123 / 130-155 系の runtime wiring タスクを次に付与する
3. superseded 済みタスクは archival metadata として付与する
4. T-OS-100〜103 のような低優先 legacy タスクは最後にまとめて付与する

### Estimated Retrofit

| Range | Primary Pattern | Expected Autonomy |
|---|---|---|
| T-OS-150〜155F | 新規 schema/rule 追加、局所実装 | `execute_with_report` |
| T-OS-158〜164 | eval/runtime wiring、既存コード更新含む | `ask_before_execute` が中心 |
| T-OS-170 | Authority Layer 設計、新規 rule/schema のみ | `execute_with_report` |

既存 Work Order への後付けは frontmatter 追加ではなく、まず Manager 側の task registry で sidecar metadata として保持する。既存 Markdown を一斉改変しない。

## Implementation Roadmap

- `T-OS-170`: 設計のみ。`authority-layer.md` と 3 schema を定義する
- `T-OS-171`: `scripts/authority/` に autonomy level 機械判定エンジンを実装する
- `T-OS-172`: Role-Based Access Control の runtime check を実装する
- `T-OS-173`: Approval Workflow engine を `OWNER_INBOX` 連携付きで実装する

## Self-Check Against Existing Rules

- `AGENTS.md` の禁止条項は維持される。許容されるのは `allow_os_mutation=true` 配下の限定的新規追加だけである
- `CONTROL.yaml` の binary gate と競合しない。むしろ binary gate 後段の精密化として働く
- `request-intake-loop.md` Step 5-6 の reduction / decision matrix を置換せず、autonomy 還元を 1 段追加するだけである
- `handoff-protocol.md` の `approval_required_for` / downstream impact の表現と整合する

## Expected Outcome

Authority Layer の成熟度を、binary gate only の状態から以下の設計要素を持つ状態へ引き上げる。

- autonomy level
- os mutation protocol
- role matrix
- approval workflow
- risk-to-autonomy mapping
- retrofit strategy

これにより SELFREVIEW-001 の「Authority Layer 12%」に対する設計上の欠落は解消され、後続タスクで実行系を実装できる状態になる。
