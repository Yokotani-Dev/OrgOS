# Anthropic AUP Compliance Preflight — Iron Law

> Anthropic / Claude を使う autonomous agent operation は、Anthropic Usage Policy (AUP) と agentic use guidance への適合確認が終わるまで DESIGN / IMPLEMENTATION / external action に進めない。自動監視や法務判断は行わず、preflight checklist と audit trail で逸脱を早期検出する。

## Purpose

OrgOS は Manager / Planner / Codex worker による autonomous agent operation を前提にしている。
Agentic execution は browsing、code execution、file edit、external tool call、handoff を組み合わせるため、通常のチャット利用よりも AUP violation の影響範囲が広い。

この rule は、Anthropic の Usage Policy と agentic use guidance を OS に全文埋め込むものではない。
公式 URL を参照しながら、OrgOS 側で実装可能な preflight、human oversight、audit trail、violation response を定義する protocol である。

## Scope

対象:

- Claude / Anthropic API / Anthropic-powered tool を使う OrgOS workflow
- browsing、code execution、file edit、external API、account operation、messaging、publication、handoff を伴う agentic task
- Anthropic 以外の model を使う場合でも、Claude と同等の autonomous-agent risk がある workflow

Out of scope:

- 自動 AUP 監視システムの実装
- 法務レビュー、契約解釈、弁護士判断の代替
- Anthropic policy 本文の再掲、再編集、またはローカル正本化
- Anthropic への violation report 自動送信

## Source References

Manager は preflight 時に以下の公式 URL を参照し、`last_verified_at` を audit trail に残す。

- Anthropic Usage Policy: `https://www.anthropic.com/legal/aup`
- Anthropic Help Center, agentic use guidance: `https://support.claude.com/en/articles/12005017-using-agents-according-to-our-usage-policy`
- Anthropic Help Center, API launch safety guidance: `https://support.claude.com/en/articles/8241216-i-m-planning-to-launch-a-product-using-the-claude-api-what-steps-should-i-take-to-ensure-i-m-not-violating-anthropic-s-usage-policy`

As of 2026-05-10, these sources include references to Universal Usage Standards, High-Risk Use Case Requirements, Additional Use Case Guidelines, and agentic-use examples covering surveillance / unauthorized data collection, harmful content, scaled abuse, and unauthorized system access or manipulation.

## Iron Law

1. **Anthropic-powered autonomous agent operation は、AUP preflight が `passed` または `not_applicable_with_reason` になるまで DESIGN / IMPLEMENTATION / external action に進めない。**
2. Manager / Codex は Anthropic policy の適法性や契約上の最終判断を行ってはならない。疑義がある場合は Owner / legal review に escalate する。
3. AUP 公式 URL、agentic use guidance URL、`last_verified_at`、確認した risk category を audit trail に残さなければならない。
4. Agent が実世界または外部 system に影響する action を取る場合、reversibility と human oversight checkpoint を明示しなければならない。
5. High-risk consumer-facing use case、法的 / 医療 / 金融 / 雇用 / 住宅 / 教育評価 / 外部公開メディアに関わる task は、qualified human review と AI involvement disclosure の要否を preflight で判定しなければならない。
6. Surveillance、unauthorized data collection、phishing / fraud、scaled abuse、unauthorized access、platform guardrail circumvention の可能性を 1 件でも検出した場合、該当 task は停止し、scope exclusion または Owner escalation に切り替えなければならない。
7. Policy source の確認日が 30 日を超えて古い場合、AUP preflight は expired として扱い、再確認するまで次フェーズに進めない。
8. この rule を理由に自動 AUP 監視、法務判断、規約本文埋め込みを実装してはならない。

## Required Data

AUP preflight は task / design / handoff のいずれかに、最低限以下を残す。

```yaml
anthropic_aup_preflight:
  status: passed | blocked | not_applicable_with_reason | needs_owner_or_legal_review
  source_urls:
    - https://www.anthropic.com/legal/aup
    - https://support.claude.com/en/articles/12005017-using-agents-according-to-our-usage-policy
  last_verified_at: "YYYY-MM-DD"
  model_or_provider: "anthropic | claude | other"
  agentic_actions:
    - "browse_web"
    - "execute_code"
    - "edit_files"
    - "call_external_api"
  prohibited_use_check:
    illegal_activity: clear | flagged | unknown
    privacy_or_identity: clear | flagged | unknown
    surveillance_or_tracking: clear | flagged | unknown
    harmful_content_or_fraud: clear | flagged | unknown
    scaled_abuse: clear | flagged | unknown
    unauthorized_system_access: clear | flagged | unknown
    democratic_process_or_targeted_campaign: clear | flagged | unknown
    high_risk_consumer_decision: clear | flagged | unknown
  autonomous_decision_check:
    legal_impact: none | possible | direct
    ethical_impact: none | possible | direct
    reversibility: reversible | partially_reversible | irreversible
    human_oversight_required: true | false
    oversight_owner: "owner | qualified_professional | legal | none"
  decision:
    proceed: true | false
    reason: "short reason"
    scope_exclusions: []
```

## Preflight Checklist

Manager は Anthropic-powered task を開始する前に、以下を確認する。

### AUP Violation Check

- 用途が Anthropic Usage Policy の Universal Usage Standards に反していないか。
- agentic use guidance の禁止例に該当する surveillance、unauthorized data collection、harmful content、fraud、scaled abuse、unauthorized access がないか。
- 他 platform の guardrail、ban、rate limit、account restriction を回避する目的がないか。
- 個人情報、protected attributes、sensitive characteristics、private account data を無断で収集・分析・操作しないか。
- output が phishing、social engineering、fake review、deceptive impersonation、misinformation、harassment、political manipulation に使われないか。
- code execution / tool call が malware、privilege escalation、unauthorized scanning、critical infrastructure impact に接続しないか。

### Autonomous Decision Check

- Agent が人の権利、法的地位、雇用、金融、医療、住宅、教育評価、保険、報道公開に影響する decision / recommendation / ranking を行わないか。
- Legal / ethical impact が `possible` 以上の場合、Owner または qualified professional の review checkpoint があるか。
- Irreversible action、external publication、financial transaction、account mutation、third-party notification は human approval 前提になっているか。
- Agent が「判断材料の整理」を超えて、専門家判断や契約判断を final decision として出していないか。

### Human Oversight Check

- High-risk consumer-facing use case では qualified human review が finalization 前に入るか。
- Consumer-facing chatbot / external interactive agent では AI disclosure の設計があるか。
- Agent action は最小権限、最小データ保持、reversible-first の順序で設計されているか。
- Owner / reviewer が停止できる rollback path、feature flag、manual handoff のいずれかがあるか。

## Audit Trail Requirements

### DECISIONS.md

Manager は shared ledger を更新できる権限を持つ場合、次を decision record として残す。
Codex worker は直接編集せず、handoff_packet の `memory_updates` または `downstream_impacts` に Manager 反映候補として渡す。

- `decision_id`: `AUP-YYYYMMDD-XXX`
- source URLs と `last_verified_at`
- task / project / milestone
- preflight status
- risk categories checked
- human oversight requirement
- scope exclusions
- Owner / legal escalation の要否
- rollback / stop condition

### Handoff Packet

Codex worker / subagent は `handoff_packet` に以下を残す。

- `assumptions`: AUP 適用範囲、Anthropic usage の有無、external action の有無
- `decisions_made`: preflight 結果、scope exclusion、human oversight 判定
- `unresolved_questions`: legal / ethical / policy ambiguity
- `downstream_impacts`: Manager が DECISIONS.md に記録すべき audit item
- `verification`: source URL 確認日、checklist self-check、実装対象外である自動監視の未実施理由

## Observability

Preflight / violation candidate は log-only で structured log に残す。
自動 remediation は行わない。

```yaml
event: anthropic_aup_preflight
task_id: T-OS-XXX
status: passed | blocked | needs_owner_or_legal_review
source_last_verified_at: "YYYY-MM-DD"
risk_categories:
  surveillance_or_tracking: clear
  harmful_content_or_fraud: clear
  scaled_abuse: clear
  unauthorized_system_access: clear
human_oversight_required: true
decision: stop | proceed | escalate
```

## Red Flags

以下を検出したら作業を止める。

- AUP source URL または `last_verified_at` がないまま Anthropic-powered agentic task に進んでいる
- Agent が user consent なしに online activity、location、private account、sensitive personal data を監視・収集・プロファイリングする
- Agent が phishing、fraud、impersonation、fake domain、fake review、deceptive content を生成・配布する
- Agent が spam、mass reporting、poll manipulation、artificial engagement、multi-account abuse、coordinated inauthentic behavior を自動化する
- Agent が unauthorized access、privilege escalation、malware、credential misuse、critical infrastructure impact を伴う action を取る
- Agent が legal / healthcare / finance / employment / housing / academic testing などの high-risk consumer-facing decision を human review なしに finalization する
- Consumer-facing AI interaction なのに AI disclosure の設計がない
- 「内部利用だから大丈夫」として policy / platform / consent check を省略している
- AUP 判断を外部 LLM の回答だけで confirmed として扱っている
- Policy source の確認日が 30 日を超えている

## Violation Response

- Preflight 未実施: task を停止し、AUP preflight を作成してから再開可否を判断する。
- Prohibited use の可能性あり: 実装・外部 action・publication を止め、scope exclusion または Owner / legal escalation に切り替える。
- Human oversight 不足: finalization を defer し、qualified professional / Owner approval checkpoint を設計に追加する。
- Audit trail 不足: Manager に DECISIONS.md 記録候補を返し、handoff_packet を補完する。
- Source expired: official URL を再確認し、`last_verified_at` を更新するまで downstream gate を停止する。
- Post-implementation violation candidate: feature flag disable、rollback、credential revocation、external action pause のいずれかを実施対象として Manager に escalate する。

## Relationship To Other Rules

- `.claude/rules/domain-constraint-sync.md`: AUP / platform policy は domain constraint の一種だが、本 rule は Anthropic-powered autonomous agent operation に特化した preflight である。
- `.claude/rules/quality-contract.md`: Quality Contract が「どこまで作る」を定め、本 rule が「Anthropic AUP 上進めてよいか」を gate する。
- `.claude/rules/authority-layer.md`: irreversible / legal_billing_compliance / high-risk decision は `ask_before_execute` または `owner_only` に還元する。
- `.claude/rules/handoff-protocol.md`: AUP preflight 結果、assumptions、unresolved questions、downstream impacts は handoff_packet に残す。
- `.claude/rules/capability-preflight.md`: Agent capability の可否判定に AUP risk category を入力として追加する。
