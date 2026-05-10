# Domain Constraint Sync Protocol — Iron Law

> Regulated domain では、DOMAIN_ANALYSIS が `sync_status=confirmed` になるまで DESIGN に進めない。Manager は法令・業界 policy・platform policy を独断で判断してはならない。例外なし。

## Purpose

OrgOS Manager は業界固有の法令、業界 policy、platform policy、競合制約を持たない。
Owner も全領域の専門家ではないため、広告、医療、金融、不動産などの regulated domain では、BRIEF の後に domain constraint を明示化して Owner と擦り合わせる必要がある。

Domain Constraint Sync は、個別法令の内容を OS に埋め込む rule ではない。
この rule は、project 側で「どの制約を確認し、何を禁止し、何を必須にし、未確認領域をどう解消するか」を記録して DESIGN gate に接続する protocol である。

## Iron Law

1. **Regulated domain では、DESIGN フェーズに進む前に DOMAIN_ANALYSIS が `sync_status=confirmed` でなければならない。**
2. Manager は法令、業界 policy、platform policy の適用有無を独断で確定してはならない。draft は作れるが、確定は Owner confirmation を必要とする。
3. `knowledge_gaps` に `status=open` が 1 件でもある場合、DESIGN または IMPLEMENTATION に進んではならない。
4. Codex Work Order は、対象 project が regulated domain の場合、confirmed DOMAIN_ANALYSIS の id と `prohibited_practices` / `required_practices` を必ず参照しなければならない。
5. DOMAIN_ANALYSIS の `expires_at` が過ぎている場合、その analysis は DESIGN gate でも IMPLEMENTATION gate でも無効である。
6. Platform を使う実装では、法令だけでなく platform policy も確認対象に含めなければならない。
7. Manager Quality Eval は、domain constraint 未確認のまま DESIGN/IMPLEMENTATION へ進んだ case を regression として記録できなければならない。
8. この rule は protocol であり、個別法令テキストの正解化、自動法令データベース連携、外部 LLM への法令確認依頼を行ってはならない。

## Required Data

Domain Constraint は `.claude/schemas/domain-constraint.yaml` に従い、実体は project の DOMAIN_ANALYSIS artifact として保存する。
Manager は lookup 時に `id` と `domain_category` を直接参照するため、gate check は O(1) の field lookup として実装できる。

必須:

- `id`: `DC-XXX-YYY` 形式
- `related_milestone` / `related_tasks`
- `domain_category`
- `regulations`: 法令・規則の id、name、summary、source_url、last_verified_at
- `platform_policies`: platform policy の id、name、provider、summary、source_url、last_verified_at
- `prohibited_practices`: 明示的にやってはいけないこと
- `required_practices`: 必ず実装・運用・表示・確認すべきこと
- `knowledge_gaps`: 未確認領域と recovery action
- `sync_status`: `draft | confirmed | superseded`
- `confirmed_at` / `confirmed_by` / `expires_at`
- `notes`

## Regulated Domain Trigger

以下のいずれかに該当する project / milestone / request は、この rule を起動する。

- `domain_category` が `advertising`, `medical`, `financial`, `real_estate`, `education`, `gaming`, `dating`, `crypto` のいずれか
- 広告配信、広告文言、比較・ランキング、成果保証、健康効果、診断、投資、融資、不動産、求人、年齢制限、本人確認、決済、暗号資産、出会い、ギャンブル、教育成果を扱う
- Meta、Google、Apple、Stripe、TikTok、LINE、X などの platform policy が成果物の公開・配信・決済可否を左右する
- Owner、Manager、Reviewer、Codex が「法令/規約に触れる可能性」を 1 件でも red flag として検出した
- `b2b_general`, `b2c_general`, `internal_tool`, `other` でも、個人情報、決済、広告、医療・金融・不動産に関連する claim を含む

## Domain Analysis Workshop Process

BRIEF 完了直後、Manager は REQUIREMENTS の機能リスト作成より前に以下の 5 step を実施する。

1. **Domain identification**: project が扱う業界、user、claim、distribution channel、platform、jurisdiction を列挙し、`domain_category` を選ぶ。
2. **Regulation discovery**: 関係しそうな法令・規則を Owner input、既存 project docs、必要に応じた WebSearch で洗い出す。summary は project impact に限定し、法令本文の再編集をしない。
3. **Platform policy check**: Meta HOUSING、Apple App Store、Google Play、Stripe TOS など、公開・広告・決済・審査に関わる policy を確認する。
4. **Prohibited/required mapping**: 見つかった制約を `prohibited_practices` と `required_practices` に変換する。実装者が判定できる粒度で書く。
5. **Owner confirm**: Owner が analysis を確認し、未確認領域が `open` で残っていない状態で `sync_status=confirmed` に昇格する。

## DESIGN Gate

REQUIREMENTS から DESIGN へ進む前に、Manager は次を満たすまで進行を停止する。

- 対象 milestone / project に DOMAIN_ANALYSIS が 1 件以上ある
- 現在の開発対象を覆う DOMAIN_ANALYSIS が `sync_status=confirmed`
- `confirmed_at`, `confirmed_by`, `expires_at` が non-null
- `expires_at` が現在時刻より後である
- `knowledge_gaps` に `status=open` がない
- `prohibited_practices` と `required_practices` が空でない、または「該当なし」の理由が `notes` に明示されている
- platform を使う場合、関連する `platform_policies` が記録されている

この gate は deterministic に判定する。
`sync_status != confirmed`、`expires_at` 超過、または open knowledge gap がある場合は DESIGN 進行禁止である。

## Knowledge Gap Handling

Owner も Manager も未確認の領域は、推測で埋めてはならない。
Manager は gap を以下のいずれかの recovery path に変換する。

- WebSearch task: official source または authoritative source を確認する
- Expert consultation task: 弁護士、社労士、税理士、医師、金融・広告審査担当など適切な専門家へ確認する
- Owner input task: Owner が持つ契約書、審査結果、社内 policy、過去資料を確認する
- Scope exclusion: 未確認領域を今回 scope から明示的に外す

`knowledge_gaps.status=open` のまま DESIGN または IMPLEMENTATION に進むことは Iron Law violation である。
調査タスクを作っただけでは十分ではない。DESIGN に進むには `resolved`、または scope exclusion として `prohibited_practices` / `required_practices` / `notes` に反映されている必要がある。

## Codex Work Order Integration

Manager が Codex に Work Order を出す際、regulated domain では以下を必ず含める。

```markdown
## Domain Constraint Reference
- DC ID: DC-ADS-001
- domain_category: advertising
- expires_at: 2026-08-31T23:59:59+09:00
- prohibited_practices:
  - "効果を保証する広告文言を表示しない"
- required_practices:
  - "広告表示には provider と campaign source を structured log に残す"
- knowledge_gaps: none_open
```

Codex は Work Order の domain constraint を実装境界として扱う。
Work Order に必要項目がない場合、Codex は実装を止め、Manager に DOMAIN_ANALYSIS confirmation を要求する。

## Manager Quality Eval Observability

Manager Quality Eval は、少なくとも以下の structured fields を regression case として記録できる形にする。

```yaml
rule_id: domain-constraint-sync
domain_constraint_id: DC-ADS-001
domain_category: advertising
gate: DESIGN
sync_status: draft
expires_at: 2026-08-31T23:59:59+09:00
open_knowledge_gap_count: 1
violation_type: design_started_without_confirmed_domain_analysis
recovery_action: stop_and_request_owner_sync
```

## Red Flags

以下を検出したら作業を止める。

- 広告、医療、金融、不動産、教育、gaming、dating、crypto に関係するのに DOMAIN_ANALYSIS がない
- `sync_status=draft` のまま DESIGN または IMPLEMENTATION に進んでいる
- `knowledge_gaps.status=open` が残ったまま実装タスクに分解している
- `expires_at` が過ぎた DOMAIN_ANALYSIS を参照している
- 法令だけ確認し、platform policy を未確認のまま広告配信、app store 公開、決済導入を進めている
- 効果保証、No.1 表現、診断、投資助言、融資条件、不動産属性、年齢・健康・収入など sensitive claim を扱っている
- Owner が「多分大丈夫」と言っているが source_url、last_verified_at、禁止/必須 mapping がない
- Manager が外部 LLM に法令確認を依頼し、その回答を confirmed source として扱っている
- prohibited practice が自然言語の注意書きだけで、実装者が判定できる粒度になっていない
- required practice が UI、logging、review、approval、fallback などの実装可能な action に分解されていない
- Codex Work Order に Domain Constraint Reference がない
- confirmed DOMAIN_ANALYSIS の内容と新しい request の distribution channel または platform が一致していない

## Violation Detection

- `/org-tick` の DESIGN gate で DOMAIN_ANALYSIS `sync_status=confirmed`、`expires_at`、open knowledge gap count をチェックする
- Request Intake Loop Step 3 で request が regulated domain trigger に該当するか判定する
- Request Intake Loop Step 5 で法令・policy 未確認を risk として分類する
- Codex Work Order template に Domain Constraint Reference を追加し、regulated domain で欠落を検出する
- Manager Quality Eval に、domain constraint 未確認での DESIGN/IMPLEMENTATION 着手を regression case として追加する

## Violation Response

- DOMAIN_ANALYSIS なしで DESIGN に進んだ場合: DESIGN を即時停止し、BRIEF 直後に戻って Domain Analysis Workshop を実施する
- `sync_status=draft` または `expires_at` 超過の場合: Owner confirmation または再確認が完了するまで DESIGN/IMPLEMENTATION を defer する
- `knowledge_gaps.status=open` がある場合: WebSearch、専門家相談、Owner input、scope exclusion のいずれかの recovery task に変換する
- Codex Work Order に Domain Constraint Reference がない場合: Codex は実装を開始せず、Manager に不足情報を返す
- 実装後に prohibited practice 違反が見つかった場合: 該当実装を停止対象にし、rollback または feature flag disable を行い、Domain Constraint を更新して再設計する
- platform policy 違反の可能性が見つかった場合: 公開・広告配信・決済有効化を止め、policy source と Owner confirmation を取り直す

## Relationship To Other Rules

- `.claude/rules/quality-contract.md`: Quality Contract が「どこまで作る」を定め、Domain Constraint Sync が「何をしてはいけない/必ずする」を定める。どちらも Owner Touchpoint Type A で、confirmed なしに下流 gate へ進めない。
- `.claude/rules/user-journey-sync.md`: Journey が「どの業務フローで実現するか」を定め、Domain Constraint Sync がその flow 上の法令・policy 制約を定める。Journey step に規制 claim が含まれる場合は Domain Analysis Workshop を起動する。
- `.claude/rules/request-intake-loop.md`: Step 3 で regulated domain trigger を検出し、Step 5 で未確認法令・policy risk を分類し、Step 6 で confirmed analysis がなければ `ask` または `defer` を選ぶ。
- `.claude/rules/design-documentation.md`: DESIGN document は confirmed DOMAIN_ANALYSIS の prohibited/required mapping を設計制約として引用する。
- `.claude/rules/eval-loop.md`: Evaluation は prohibited practice 違反、required practice 欠落、expired analysis 参照を regression として扱う。
