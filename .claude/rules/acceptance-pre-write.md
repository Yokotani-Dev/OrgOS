# Acceptance Pre-Write Protocol - Iron Law

> セルフレビュー観点を実装後に発見する運用を止める。
> Manager は Codex 委任前に、Quality Contract と設計成果物から検証観点を acceptance criteria へ展開し、実装前制約として固定する。

## Purpose

Acceptance Pre-Write Protocol は、実装後レビューで新しい観点を順番に当て続けるループを構造的に止めるための IMPLEMENTATION gate である。

Quality Contract は「どこまで作るか」を 6 軸で定義する。Threat Model、Data Model、Authority Boundary、Domain Constraint、Journey は「何を壊してはいけないか」「どの流れを満たすか」を定義する。本 rule は、それらを task 単位の `acceptance` 配列へ実装前に展開する。

Codex は acceptance を満たすように実装する。セルフレビューは、実装後に新しい観点を探す作業ではなく、pre-written acceptance の漏れを確認する作業に限定する。

## Iron Law

1. 全 task の `acceptance` は、Codex が実装に着手する前に確定していなければならない。
2. `acceptance` が空、存在しない、または「いい感じに」「適切に」「必要に応じて」のように曖昧な task を Codex に委任してはならない。
3. 実装中に新しい確認観点が判明した場合、Manager は実装を止め、`acceptance` を更新してから Work Order を再発行しなければならない。
4. Codex の自己報告、Review Packet、テスト結果は、acceptance item と 1:1 で verify できなければならない。
5. セルフレビューは acceptance 漏れチェックに限定する。セルフレビューで新観点が発見された場合、それは task 定義の不備として扱う。
6. 新観点が発見された task は、acceptance 追加、必要なら設計成果物更新、再実装または修正 task 発行の順で復旧しなければならない。
7. Quality Contract の `definition_of_done` 6 軸のうち、対象 task に該当する軸が acceptance に展開されていない場合、IMPLEMENTATION gate を通してはならない。
8. `acceptance` は実装者への希望ではなく、完了判定の契約である。Manager は Codex への Work Order に最終 acceptance を必ず転記しなければならない。

## Acceptance Quality Standards

Acceptance criteria は以下を満たす必要がある。

1. **検証可能**: テスト、lint、ログ確認、差分確認、手動確認のいずれかで pass / fail を判定できる。
2. **観察可能**: 期待する成果、エラー表示、ログ field、権限拒否、ドキュメント更新など、外から確認できる状態を記述する。
3. **排他的**: 同じ観点を複数 item に重複させない。重複する場合は統合し、個別 item は別の検証対象に分離する。
4. **網羅的**: Quality Contract DoD の 6 軸と、対象 task に関係する risk / data / authority / domain / journey 観点を覆う。
5. **数値化可能なら数値化**: 件数、対象ファイル、response code、retry 回数、log field 名、threshold、line item 数などを具体化する。
6. **単一責務**: 1 item は 1 つの完了条件だけを表す。複数条件を `and` で束ねる場合は分割する。
7. **実装境界つき**: out_of_scope、禁止事項、触ってはいけない file / table / endpoint がある場合は acceptance または Work Order に明示する。
8. **証跡つき**: item ごとに、Quality Contract、Threat Model、Data Model、Authority Boundary、Domain Constraint、Journey のどれに由来するかを追跡できる。

## Acceptance Source Mapping

Manager は acceptance を書く前に、以下 6 sources を必ず確認する。該当なしの場合も `N/A` と理由を記録する。

| Source | Derive Into Acceptance |
|---|---|
| Quality Contract DoD | `functionality`, `error_handling`, `security`, `performance`, `observability`, `documentation` の各軸に対応する完了条件 |
| Threat Model | 8 threat categories の該当箇所、攻撃または失敗シナリオ、実装対策、検証方法 |
| Data Model | invariants、transaction boundaries、idempotency keys、状態遷移、削除戦略、partial failure handling |
| Authority Boundary | RLS、authz、authn、role matrix、owner / tenant scope、admin-only 操作、RPC / function 権限 |
| Domain Constraint | prohibited practices、required practices、platform policy、open knowledge gap がないこと、expires_at 有効性 |
| Journey | happy_path、error_paths、target_flow step、derived feature、Owner が成功とみなす業務フロー |

## Pre-Write Workflow

Manager は task 作成時に次の順序を守る。

1. Task を作成する前に、Quality Contract DoD、Threat Model、Data Model、Authority Boundary、Domain Constraint、Journey から該当観点を抽出する。
2. 抽出した観点を `.ai/TEMPLATES/ACCEPTANCE_CHECKLIST.md` に展開し、各 section に `該当あり` または `N/A` と理由を明示する。
3. 重複、曖昧語、検証不能 item を削り、最終 `acceptance` 配列へ転記可能な粒度に整える。
4. Codex へ渡す前に Manager 自身で、acceptance が Quality Contract DoD と設計成果物を覆っているかチェックする。
5. Codex Work Order に Quality Contract Reference、関連 design / domain / journey references、最終 acceptance 配列を必ず転記する。
6. Codex 実装中に新観点が判明した場合は、実装を止め、acceptance と必要な upstream artifact を更新してから Work Order を再発行する。
7. Codex 完了後、Manager は報告・Review Packet・テスト結果を acceptance item ごとに照合する。

## Self-Review Reframing

旧運用:

- 実装後に観点を当てる。
- CRITICAL / MAJOR が後から見つかる。
- 修正後に別観点を当て、別の CRITICAL / MAJOR が見つかる。
- レビューが「観点の発掘」になり、完了条件が動き続ける。

新運用:

- 実装前に観点を acceptance に書く。
- Codex は acceptance を満たすように実装する。
- セルフレビューは acceptance の漏れ、未検証、証跡不足を確認する。
- 新観点が見つかった場合、それは reviewer の発見ではなく task の不備として扱う。

新観点発見時の扱い:

1. 該当観点の source を特定する。
2. 必要なら Quality Contract、Threat Model、Data Model、Authority Boundary、Domain Constraint、Journey を更新する。
3. `acceptance` に item を追加する。
4. Codex Work Order を再発行し、再実装または修正 task として扱う。
5. Manager Quality Eval に `acceptance_late_addition` として記録する。

## Red Flags

以下を検出したら Codex 委任または実装継続を止める。

1. Work Order に `acceptance` がない。
2. `acceptance` が 1 行の抽象文だけで、pass / fail が判定できない。
3. Quality Contract Reference はあるが、DoD 6 軸が acceptance に展開されていない。
4. Threat Model の該当カテゴリが acceptance に出ていない。
5. Data Model の invariant、transaction boundary、idempotency が write 系 task の acceptance にない。
6. Authority Boundary が必要な task なのに RLS / authz / authn の acceptance がない。
7. Regulated domain なのに prohibited / required practices が acceptance に反映されていない。
8. Journey の happy_path / error_paths と acceptance の対応が追跡できない。
9. 「適切に」「十分に」「考慮する」「必要に応じて」など検証不能な語が acceptance に残っている。
10. Codex の完了報告が acceptance item 単位で照合できない。
11. 実装後セルフレビューで初めて CRITICAL / MAJOR 観点が出ている。
12. 新観点発見後に acceptance を更新せず、そのままパッチ修正だけで進めている。

## Violation Detection

Manager は以下の gate / eval で違反を検出する。

- Work Order 発行時に `acceptance` の存在、item 数、曖昧語、source mapping の有無を確認する。
- IMPLEMENTATION 開始前に Quality Contract DoD 6 軸と final acceptance の対応を確認する。
- DESIGN-derived sources について、Threat Model 8 カテゴリ、Data Model、Authority Boundary、Domain Constraint、Journey の該当 / N/A が記録されているか確認する。
- Codex 完了時に、報告・Review Packet・テスト結果が acceptance item と 1:1 対応しているか確認する。
- Manager Quality Eval に `acceptance_late_addition_rate` を記録できるよう、後出し追加件数を structured field として残す。

推奨 structured log:

```yaml
event: "acceptance_pre_write_gate"
task_id: "T-..."
milestone_id: "M-..."
quality_contract_id: "QC-..."
acceptance_items_count: 0
source_mapping:
  quality_contract_dod: "covered|partial|missing"
  threat_model: "covered|n_a|missing"
  data_model: "covered|n_a|missing"
  authority_boundary: "covered|n_a|missing"
  domain_constraint: "covered|n_a|missing"
  journey: "covered|n_a|missing"
late_additions:
  count: 0
  severity_max: "none|suggestion|minor|major|critical"
acceptance_late_addition_rate_input:
  tasks_checked: 1
  tasks_with_late_acceptance_additions: 0
decision: "allow|block|reissue_work_order"
```

## Violation Response

Manager は違反を分類し、復旧手順を明示する。

| Violation | Classification | Manager Response | Recovery |
|---|---|---|---|
| Acceptance missing / empty | gate_blocker | Codex 委任を開始しない | Checklist から final acceptance を作成し、Work Order を再発行する |
| Acceptance ambiguous | acceptance_quality_failure | 実装開始を止める | 検証可能な pass / fail 条件へ書き換える |
| DoD 6 軸の未展開 | contract_mapping_gap | Work Order を差し戻す | Quality Contract DoD を task 粒度に分解する |
| Threat / data / authority source missing | design_mapping_gap | 関連する実装領域を止める | upstream artifact を確認し、該当 / N/A と acceptance を追加する |
| Domain constraint missing | policy_mapping_gap | regulated domain task を defer する | DOMAIN_ANALYSIS を confirmed にし、禁止 / 必須事項を acceptance に反映する |
| Journey mapping missing | journey_mapping_gap | feature 実装を止める | happy_path / error_paths との対応を acceptance に追加する |
| Implementation-time new viewpoint | acceptance_late_addition | 実装を一時停止する | acceptance 更新、Work Order 再発行、必要なら再実装する |
| Post-review CRITICAL / MAJOR first discovery | design_escape | 修正だけで済ませない | source artifact と acceptance を更新し、Manager Quality Eval に記録する |

## Relationship To Other Rules

- `.claude/rules/quality-contract.md`: Quality Contract の `definition_of_done` 6 軸を task-level acceptance へ展開する接続点。
- `.claude/rules/pre-implementation-risk-profile.md`: Threat Model、Data Model、Authority Boundary の事前固定観点を acceptance に落とす。
- `.claude/rules/design-documentation.md`: DESIGN 成果物から実装前に task acceptance を derive する。
- `.claude/rules/user-journey-sync.md`: Journey の happy_path / error_paths を functionality と error handling の acceptance に変換する。
- `.claude/rules/domain-constraint-sync.md`: prohibited / required practices を acceptance に変換し、regulated domain の後出し policy 違反を防ぐ。
- `.claude/rules/eval-loop.md`: `acceptance_late_addition_rate` を Manager Quality Eval の regression input として扱う。
- `.claude/rules/request-intake-loop.md`: 新規 request を task 化する前に source mapping と acceptance pre-write を実施する。
