# Memory Lifecycle - Iron Law

> Memory の操作は以下 6 段階のみ。例外なし。

USER_PROFILE は `facts` / `secrets` / `preferences` を分離した fact registry として扱う。  
**Iron Law: secret 実体を YAML に置かない。保存するのは secret pointer のみ。**

## Iron Law

USER_PROFILE の各エントリは以下のライフサイクルを辿る:

1. **capture** - 新情報を fact / secret / preference として登録する
   - 必須フィールドを全て埋める
   - `source` と `source_ref` を必ず記録する
   - `valid_from` / `expires_at` / `last_verified_at` を初回登録時に与える
   - `transferability` は明示昇格が必要になるまで `none` にする
   - `confidence` が不明なら `0.5` 以下で開始する
   - secret 実体は保存せず、`storage` に URI pointer を登録する

2. **normalize** - 表記ゆれ・重複を統一する
   - 同一 semantic の fact は merge する
   - `id` は `fact_*` / `secret_*` / `pref_*` に正規化する
   - `scope` と `pii_level` を欠落させない
   - `source_ref` / `valid_from` / `expires_at` / `last_verified_at` / `transferability` を 3 セクションで揃える

3. **scope** - 適用範囲を限定する
   - `global` / `project:<id>` / `domain:<name>` のみ許可
   - 誤転移しそうな内容は広い scope に昇格しない
   - `transferability: none` は複製も昇格も禁止
   - `transferability: explicit_only` は Owner か明示 Decision があるときだけ昇格可
   - project 固有情報は `global` にしない

4. **retrieve** - 依頼処理時に参照する
   - Request Intake Loop の Step 2 で強制
   - `scope` / `expires_at` / `confidence` でフィルタする
   - Owner に質問する前に fact registry と secret pointer を確認する

5. **validate** - 定期または参照時に妥当性確認する
   - `expires_at` 超過なら再確認を要求する
   - `confidence < 0.5` は Owner 確認対象にする
   - secret pointer は `last_verified_at` を更新し、失効していれば rotate する

6. **retire / promote** - 失効させる or scope 昇格する
   - retire: `expires_at` 超過、Owner 否定、情報源消失
   - promote: `project` → `domain` → `global` の順でのみ昇格
   - promote 前に validate を再実施する
   - `transferability` が昇格先と整合しない entry は promote しない

## Operation Procedure

### 1. capture

- 新しい記憶を `facts` / `secrets` / `preferences` のどれに入れるか先に分類する
- `facts` は truth claim、`preferences` は振る舞い方針、`secrets` は実体を持たない参照先として扱う
- `pii_level: high` の値は平文保存しない。必要なら redacted value か pointer を使う
- `secret: true` の fact は、同じ semantic を表す `secret_*` entry を同時に作る
- `preferences` でも `source_ref` / `valid_from` / `expires_at` / `last_verified_at` を持ち、追跡可能にする
- `secrets` も fact と同じ provenance metadata を持ち、pointer の妥当性確認を残す

### 2. normalize

- `id` の semantic slug を統一し、同義語の乱立を防ぐ
- 同じ内容が `facts` と `preferences` に重複していたら役割に合わせてどちらかへ寄せる
- `source_ref` は追跡可能な形式にする
  - `past_qa:YYYY-MM-DD`
  - `file:path#L`
  - `owner_message:YYYY-MM-DD`
- normalize lint で検出した重複 semantic は放置しない

### 3. scope

- `global`: Owner 全体に効く長期的な情報
- `project:<id>`: そのプロジェクトだけで有効
- `domain:<name>`: GitHub、Supabase、billing など領域限定の知識
- `scope` が曖昧なまま保存してはならない
- `transferability` の基準
  - `none`: 他 scope へ複製・昇格しない
  - `project_to_domain`: `project:<id>` から `domain:<name>` まで
  - `domain_to_global`: `domain:<name>` から `global` まで
  - `explicit_only`: 明示判断があるときだけ個別昇格

### 4. retrieve

- 依頼受領時はまず `facts` と `preferences` を読み、必要なら `secrets` の pointer を参照する
- 参照時に以下を除外する
  - 期限切れの entry
  - 現在の依頼 scope と一致しない entry
  - 信頼度が低く、未検証の entry
- 取り出した情報を回答に使う前に、再質問を回避できるか確認する

### 5. validate

- 参照ごとに `expires_at` と `confidence` を見る
- `source: inferred` の情報は参照時 validate を基本とする
- pointer が壊れている secret は使わず、再 materialize ではなく再登録を行う
- `last_verified_at` は validate 実施日で更新する

### 6. retire / promote

- retire した entry は削除ではなく、別途失効扱いにできる形式で管理するのが望ましい
- promote は以下の順序のみ許可
  - `project:<id>` -> `domain:<name>`
  - `domain:<name>` -> `global`
- 1 回の観測だけで promote しない
- promote 条件
  - `transferability: project_to_domain` のとき `project:<id>` -> `domain:<name>` のみ許可
  - `transferability: domain_to_global` のとき `domain:<name>` -> `global` のみ許可
  - `transferability: explicit_only` は Owner 確認または明示 Decision を `source_ref` に残した場合のみ許可
  - `transferability: none` は promote 不可

## pii_level 判定 rubric

- **none**: 公開情報。例: OSS ライブラリ名、技術スタック、公開 API URL
- **low**: 識別できるが公開済み。例: Owner 名、`project_ref`、公開リポジトリ URL
- **medium**: 業務情報、部分的識別性。例: tenant ID、内部 URL、スケジュール
- **high**: 直接 PII・財務。例: 住所、電話、クレカ番号、salary
- 迷ったら 1 段階上を選ぶ
- 判定時に `source_ref` に判定根拠を残す

## past_qa Handling

`past_qa` は独立配列にしない。必ず fact として統一管理する。

```yaml
- id: fact_qa_supabase_project_ref
  type: project_resource
  value_ref:
    question: "Supabase project_ref は？"
    answer: "abc123"
    asked_at: "2026-03-15"
    context: "初期セットアップ時"
  scope: "project:orgos"
  source: owner_confirmed
  source_ref: "past_qa:2026-03-15"
  confidence: 1.0
  valid_from: "2026-03-15"
  expires_at: null
  pii_level: low
  last_verified_at: "2026-03-15"
  transferability: "project_to_domain"
  secret: false
```

ルール:

- Q/A から再利用価値のある事実だけを fact 化する
- `question` と `answer` を対で残し、由来を失わない
- `answer` を使うのは `pii_level: none|low` の非機密回答に限る
- 認証情報そのものは `answer` に入れない。必要なら `answer_redacted` か `secret_ref` に分離する

## Lintable Conditions

- **normalize lint**: 同一 semantic の fact が複数存在する場合に失敗とする
  - 例: `fact_supabase_ref` と `fact_supabase_project_ref`
- **promote lint**: `transferability: none` の fact が `project:x` から `project:y` へ複製されていたら失敗とする
- **scope lint**: 未登録の `scope` 値を持つ entry があれば失敗とする
  - 例: `project:<unlisted>`
- 上記は `scripts/memory/` 配下の lint script 候補として扱う
- lint 実装は別タスクでもよいが、違反条件の定義はこの文書を SSOT にする

## Git Hygiene

- `.ai/USER_PROFILE.yaml` は gitignore で保護する
- それだけでは不十分なので pre-commit で secret scanner を走らせる
- `.pre-commit-config.yaml` では `gitleaks` と `USER_PROFILE` 向け local hook を管理する
- `scripts/memory/check-no-plain-secrets.sh` が未実装でも、hook の entry は placeholder として維持してよい

## Red Flags

以下を検出したら作業を止める:

- secret 実体を `USER_PROFILE.yaml` に書こうとしている
- `scope` なしで記憶を保存しようとしている
- `source` / `source_ref` なしで登録しようとしている
- `expires_at` 超過の fact を無検証で再利用しようとしている
- `confidence < 0.5` の情報を Owner 確認なしで断定しようとしている
- `past_qa` を独立配列で増やし始めている
- `transferability: none` の entry を別 scope へ複製しようとしている

## Manager Enforcement

Manager は以下を強制する:

1. Request Intake Loop Step 2 で USER_PROFILE を読む
2. Owner へ質問する前に fact registry を検索する
3. secret が必要でも、取得先は pointer で管理されているか確認する
4. 回答後、再利用価値のある新情報だけを capture 候補にする
5. Iron Law 違反を検知したら処理を停止し、Red Flag として扱う

## Violation Response

- Iron Law 違反を検知した変更は merge しない
- secret 実体混入は即時除去し、pointer 方式へ修正する
- `scope` / `source` / `confidence` 欠落の entry は無効扱いにする

## Lint Operations

- pre-commit / pre-push では `.pre-commit-config.yaml` 経由で memory lint を自動実行する
- secret scanner:
  - `bash scripts/memory/check-no-plain-secrets.sh`
  - `.ai/**/*.yaml` / `.ai/**/*.md` を走査し、平文 secret 候補を検出したら `exit 1` する
- normalize lint:
  - `bash scripts/memory/normalize-lint.sh`
  - `bash scripts/memory/normalize-lint.sh --json`
  - `facts` の類似 semantic / 重複候補を warning として出力する。`--json` は機械処理用
- promote lint:
  - `bash scripts/memory/promote-lint.sh`
  - `project` 間複製や `transferability: none` の scope 越えを warning として列挙する

## CI/CD Guidance

- CI では `pre-commit run --all-files` を最低ラインにし、memory lint と `gitleaks` を一括実行する
- `normalize-lint.sh --json` の出力は review bot や nightly audit に取り込みやすい形式として扱う
- `promote-lint.sh` は fail-fast ではなく drift 可視化用の warning として運用し、昇格判断は review で止める
- 依存が未導入のローカル環境では lint は graceful skip を許容するが、CI では `python3` と `PyYAML` を前提にする
