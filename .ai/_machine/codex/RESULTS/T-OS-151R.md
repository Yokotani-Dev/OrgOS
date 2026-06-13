# T-OS-151R Review Report

## 総合判定
- △ (要修正)

## 観点別評価
### R1: Pro 指摘対応
- 判定: △
- 確認内容:
  - secret 実体を置かず pointer のみを使う方針は明記されている。`storage` は URI pattern で定義され、テンプレートも pointer のみを案内している（`.claude/schemas/user-profile.yaml:151-158`, `.claude/rules/memory-lifecycle.md:5-6`, `.ai/USER_PROFILE.example.yaml:1-4`）。
  - `facts` / `secrets` / `preferences` の 3 分離は実装済み（`.claude/schemas/user-profile.yaml:36-208`, `.ai/USER_PROFILE.example.yaml:12-90`）。
  - 6 操作のライフサイクルは Iron Law として明記され、Red Flag と停止条件もある（`.claude/rules/memory-lifecycle.md:8-41`, `.claude/rules/memory-lifecycle.md:119-144`）。
- 問題点:
  - Pro SSOT が要求した `last_verified` が facts / preferences に存在せず、secrets 側も `last_verified_at` のみで非対称。検証時点の追跡が fact registry 全体で揃っていない（`.ai/DESIGN/CHATGPT_PRO_REVIEW_2026-04-18.md:26-33`, `.claude/schemas/user-profile.yaml:41-52`, `.claude/schemas/user-profile.yaml:133-140`, `.claude/schemas/user-profile.yaml:177-184`）。
  - Pro 指摘の「必須メタデータを揃える」という観点では、preferences と secrets に `source_ref` / `expires_at` / `pii_level` 相当が欠けており、fact だけが厳格で他セクションは追跡性が落ちる（`.claude/schemas/user-profile.yaml:133-170`, `.claude/schemas/user-profile.yaml:177-207`）。

### R2: schema 妥当性
- 判定: ○
- 確認内容:
  - YAML としては parseable。`ruby` で `.claude/schemas/user-profile.yaml` / `.ai/USER_PROFILE.example.yaml` / `.ai/USER_PROFILE.yaml` を読み込めた。
  - required / optional の区別は `required:` 配列で明示されている（`.claude/schemas/user-profile.yaml:5-9`, `.claude/schemas/user-profile.yaml:41-52`, `.claude/schemas/user-profile.yaml:133-140`, `.claude/schemas/user-profile.yaml:177-184`）。
  - scope の pattern は `global` / `project:<id>` / `domain:<name>` を許可している（`.claude/schemas/user-profile.yaml:68-70`, `.claude/schemas/user-profile.yaml:148-150`, `.claude/schemas/user-profile.yaml:192-194`）。
- 問題点:
  - `pii_level` enum はあるが判定基準が schema / lifecycle のどちらにも定義されていない。運用者ごとに `low` / `medium` / `high` が揺れる（`.claude/schemas/user-profile.yaml:92-99`, `.claude/rules/memory-lifecycle.md:47-50`）。
  - 将来の graph memory 移行を意識した relation / edge 用の拡張ポイントや versioning がなく、`type: any` の `value_ref` 以外に構造化拡張の導線が弱い（`.claude/schemas/user-profile.yaml:65-67`, `.claude/schemas/user-profile.yaml:102-126`）。

### R3: Iron Law 厳格性
- 判定: ○
- 確認内容:
  - 6 操作は「例外なし」と明記されている（`.claude/rules/memory-lifecycle.md:3`, `.claude/rules/memory-lifecycle.md:10-41`）。
  - Red Flag と違反時停止・merge 禁止も定義されている（`.claude/rules/memory-lifecycle.md:119-144`）。
- 問題点:
  - 操作ごとの違反検出方法は一部テキスト規約に留まり、機械検出条件が弱い。たとえば normalize / promote 違反をどう自動検知するかは未定義（`.claude/rules/memory-lifecycle.md:52-89`, `.claude/rules/memory-lifecycle.md:130-144`）。

### R4: 誤転移防止
- 判定: △
- 確認内容:
  - 全 fact に `scope` は必須で、3 層スコープにも対応している（`.claude/schemas/user-profile.yaml:45-46`, `.claude/schemas/user-profile.yaml:68-70`, `.claude/rules/memory-lifecycle.md:23-31`, `.claude/rules/memory-lifecycle.md:61-66`）。
- 問題点:
  - Pro が明示要求した `transferability` フィールドは schema / template / lifecycle のどこにもない。誤転移リスクの評価が `scope` だけに依存している（`.ai/DESIGN/CHATGPT_PRO_REVIEW_2026-04-18.md:111-118`, `.claude/schemas/user-profile.yaml:41-101`, `.ai/USER_PROFILE.example.yaml:12-63`）。

### R5: gitignore 設定確認
- 判定: △
- 確認内容:
  - `.ai/USER_PROFILE.yaml` は gitignore 済み（`.gitignore:8-9`）。
  - `.ai/USER_PROFILE.example.yaml` は ignore されておらず commit 対象に残っている（`.gitignore:1-9`）。
- 問題点:
  - Pro SSOT が求めた pre-commit scanner への参照が実装物内にない。repo 内検索でも `pre-commit` / `gitleaks` / `detect-secrets` の Safe Memory 向け参照は見つからなかった。gitignore 以外の混入防止線が未整備。

### R6: past_qa の統一管理
- 判定: ○
- 確認内容:
  - schema に `past_qa_fact` variant があり、独立配列にしない方針も lifecycle に明記されている（`.claude/schemas/user-profile.yaml:102-126`, `.claude/rules/memory-lifecycle.md:91-117`）。
  - example / working copy にも `fact_qa_supabase_project_ref` が fact として入っている（`.ai/USER_PROFILE.example.yaml:49-63`, `.ai/USER_PROFILE.yaml:48-62`）。
- 問題点:
  - `answer` を string で保持しており、secret pointer が必要な回答を誤って平文で格納できる。ルール文では禁止しているが schema では抑止できていない（`.claude/schemas/user-profile.yaml:121-122`, `.claude/rules/memory-lifecycle.md:115-117`）。

### R7: Manager Quality Eval との連動
- 判定: ×
- 確認内容:
  - `./.claude/evals/manager-quality/run.sh` を 1 回実行し、`2026-04-18.jsonl` は 60 行から 80 行へ増えた。suite 自体は実行可能。
- 問題点:
  - 実行結果は exit code `1`。README でも report 実装でも、現在の judge は `USER_PROFILE/CAPABILITIES/active work graph integration is absent` と決め打ちで全件 fail させる mock のまま（`.claude/evals/manager-quality/README.md:14-16`, `.claude/evals/manager-quality/report.py:65-82`）。
  - `metrics.yaml` の `repeated_question_rate` は `past_qa` ベースの式、`decision_trace_completeness` は一般的 trace 指標で、`USER_PROFILE` 参照を評価ロジックに直接結びつけていない。case 期待値には `USER_PROFILE` が出るが、judge がその内容を使っていない（`.claude/evals/manager-quality/metrics.yaml:2-5`, `.claude/evals/manager-quality/metrics.yaml:38-40`, `.claude/evals/manager-quality/cases/01-repeated-question.yaml:14-21`, `.claude/evals/manager-quality/report.py:65-82`）。

### R8: 未解決リスクの発見
- 判定: △
- 確認内容:
  - scope pattern は `project:orgos` のような名前を許可し、現サンプルもその形式で統一されている（`.claude/schemas/user-profile.yaml:68-70`, `.ai/USER_PROFILE.example.yaml:40`, `.ai/USER_PROFILE.example.yaml:56`）。
- 問題点:
  - 1000 facts 超の検索戦略、index、並行書き込み制御は定義なし。単一 YAML append/update 前提で race condition と性能劣化が未解決。
  - scope の命名規則は regex 許可だけで、canonical naming rule がない。`project:orgos` と `project:OrgOS` や `domain:github` / `domain:gh` の揺れを運用で防げない。
  - `pii_level` の判定基準がないため、レビューや自動検査の再現性がない。

## 発見した問題 (重要度別)
### CRITICAL
- なし

### HIGH
- `.claude/evals/manager-quality/report.py:65-82` - judge が `USER_PROFILE/CAPABILITIES/active work graph integration is absent` を固定文言で返す mock のままで、R7 の「USER_PROFILE を参照する設計になっているか」を満たしていない - mock judge を段階的に置換し、少なくとも repeated-question 系ケースでは `USER_PROFILE.facts` / fact 化された `past_qa` を読んで pass/fail を決める実装にする。
- `.claude/schemas/user-profile.yaml:133-170` と `.claude/schemas/user-profile.yaml:177-207` - secrets / preferences に `source_ref`、`expires_at`、`pii_level`、`valid_from`、`last_verified` 相当が揃っておらず、Pro SSOT が要求した記憶の追跡性・失効性が fact 以外で担保されていない - metadata の共通基底を導入し、3 セクションすべてで provenance / validity / privacy を追えるようにする。
- `.claude/schemas/user-profile.yaml:41-101` - 誤転移対策が `scope` のみで、Pro 指摘の `transferability` フィールドが存在しない - `transferability: enum[none, project_to_domain, domain_to_global, explicit_only]` などを追加し、promote 条件と整合させる。

### MEDIUM
- `.claude/schemas/user-profile.yaml:92-99` - `pii_level` enum はあるが判定基準が文書化されていない - `.claude/rules/memory-lifecycle.md` か schema コメントに具体例付き rubric を追加する。
- `.claude/schemas/user-profile.yaml:121-122` - `past_qa` の `answer` は string 固定で、secret を平文で入れても schema 上は通ってしまう - `answer_redacted` / `secret_ref` の排他的 variant を追加する。
- `.claude/rules/memory-lifecycle.md:52-89` - normalize / promote の違反検出が手動運用前提で、自動検出条件が不足 - lint 可能な naming / duplicate / invalid promotion rule を明文化する。
- `.gitignore:8-9` - Safe Memory の混入防止が gitignore のみで、pre-commit scanner 参照がない - pre-commit hook か secret scanner の runbook 参照を追加する。

### LOW
- `.claude/schemas/user-profile.yaml:68-70` - scope pattern はあるが canonical naming rule がなく、`domain:github` と `domain:gh` のような揺れを防げない - allowed registry か naming convention を別紙で固定する。
- `.claude/schemas/user-profile.yaml:65-67` - graph memory への移行余地はあるが relation/version の設計が弱い - `schema_version` と relation-aware metadata の追加を将来タスクに切り出す。
- `.ai/USER_PROFILE.example.yaml:12-63` - facts 数が増えた場合の検索・更新方針が未定義 - 1000+ facts を想定した index / sharding / migration 方針を設計 backlog に積む。

## 修正提案
- `T-OS-151 FIX-001`: `transferability` と共通 memory metadata (`source_ref`, `valid_from`, `expires_at`, `pii_level`, `last_verified_at`) を 3 セクションへ拡張
- `T-OS-151 FIX-002`: `manager-quality` mock judge を repeated-question / trace ケースから実データ参照へ置換
- `T-OS-151 FIX-003`: `pii_level` rubric と scope canonical naming rule を `memory-lifecycle.md` に追加
- `T-OS-151 FIX-004`: `past_qa` の secret-safe schema variant (`answer_redacted` or `secret_ref`) を導入
- `T-OS-151 FIX-005`: Safe Memory 用 pre-commit secret scanner 参照を runbook か hook 設定に追加
- `T-OS-151 FIX-006`: YAML fact registry の競合制御・大規模化方針を設計メモ化

## ステータス
- CHANGES_REQUESTED
