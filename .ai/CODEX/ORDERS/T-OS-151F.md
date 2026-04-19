# Work Order: T-OS-151F (Fix from T-OS-151R review)

## Task
- ID: T-OS-151F
- Title: T-OS-151 Safe Memory レビュー指摘の修正 (HIGH + MEDIUM)
- Role: implementer
- Priority: P0

## Allowed Paths
- `.claude/schemas/user-profile.yaml` (編集)
- `.claude/rules/memory-lifecycle.md` (編集)
- `.ai/USER_PROFILE.example.yaml` (編集)
- `.ai/USER_PROFILE.yaml` (編集)
- `.claude/evals/manager-quality/report.py` (編集)
- `.claude/evals/manager-quality/metrics.yaml` (編集可)
- `.pre-commit-config.yaml` (新規)
- `.ai/CODEX/RESULTS/T-OS-151F.md` (結果記録)

## Dependencies
- T-OS-151: done
- T-OS-151R: CHANGES_REQUESTED (review 完了)

## Context

T-OS-151R (Safe Memory 独立レビュー) で △ 判定。以下の HIGH/MEDIUM 指摘を修正する。
LOW 指摘 3 件 (graph memory 拡張・大規模化・canonical naming) は別タスク T-OS-151G として先送り。

レビュー原文: `.ai/CODEX/RESULTS/T-OS-151R.md`

## Acceptance Criteria

### F1 [HIGH]: 共通 memory metadata の 3 セクション適用
問題: secrets / preferences に `source_ref`, `valid_from`, `expires_at`, `pii_level`, `last_verified_at` が欠落。
修正:
- `.claude/schemas/user-profile.yaml` に共通 base metadata を定義
- secrets, preferences にも同じ必須フィールドを適用
- 例: secrets: source_ref, valid_from, expires_at, pii_level, last_verified_at
- 例: preferences: source_ref, valid_from, expires_at, last_verified_at (pii_level は optional)

### F2 [HIGH]: transferability フィールド追加
問題: 誤転移対策が `scope` のみで `transferability` なし。
修正:
- schema に追加: `transferability: enum[none, project_to_domain, domain_to_global, explicit_only]`
- デフォルト: `none` (明示的に昇格を許可しない限り転移しない)
- `.claude/rules/memory-lifecycle.md` の promote 操作で transferability を判定条件に組み込む

### F3 [HIGH]: Manager Quality Eval mock judge 置換
問題: `report.py:65-82` が固定文言で全件 fail する mock のまま。USER_PROFILE を実際に参照していない。
修正:
- repeated-question 系 4 ケースと trace 系 2 ケースで、実際に USER_PROFILE.facts を読んで判定する
- `past_qa` fact variant から question/answer を参照し、case の current_request と照合
- pass 条件: 「該当する past_qa が USER_PROFILE.facts に存在する + 期待される behavior が anti_pattern と一致しない」
- 他のカテゴリ (cli_over_gui, context_miss 等) はまだ runtime wiring がないので mock のままで OK
- 移行方針を `.claude/evals/manager-quality/README.md` に追記 (既存読み込み/書き込みは OK)

### F4 [MEDIUM]: pii_level 判定 rubric
問題: `pii_level` の判定基準が未定義。
修正: `.claude/rules/memory-lifecycle.md` に具体例付き rubric を追加。
```markdown
## pii_level 判定 rubric
- **none**: 公開情報 (OSS ライブラリ名、技術スタック、公開 API URL)
- **low**: 識別できるが公開済み (Owner 名、project_ref、公開リポジトリ URL)
- **medium**: 業務情報、部分的識別性 (tenant ID、内部 URL、スケジュール)
- **high**: 直接 PII・財務 (住所、電話、クレカ番号、salary)
- 迷ったら 1 段階上を選ぶ
- 判定時に source_ref に判定根拠を残す
```

### F5 [MEDIUM]: past_qa answer の secret 防御
問題: `answer: string` で平文 secret を誤格納できる。
修正: schema に排他的 variant を追加:
```yaml
past_qa_fact:
  value_ref:
    question: string
    # 以下はいずれか1つ（oneOf）
    answer: string           # 非機密のみ
    answer_redacted: string  # "[redacted: see secrets.<id>]"
    secret_ref: string       # secrets セクションの id 参照
    asked_at: date
    context: string
```
- `memory-lifecycle.md` で「answer 使用時は pii_level=low 以下限定」ルール追加

### F6 [MEDIUM]: normalize / promote の自動検出条件
問題: 違反検出が手動運用前提。
修正: `.claude/rules/memory-lifecycle.md` に lint 可能な条件を明文化:
- **normalize lint**: 同一 semantic の fact が複数存在 (例: fact_supabase_ref と fact_supabase_project_ref)
- **promote lint**: transferability=none の fact が project:x から project:y に複製されている
- **scope lint**: 未登録の scope 値を持つ fact (例: project:<unlisted>)
- これらを scripts/memory/ 配下の lint script として提案 (実装は別タスク T-OS-151G でも OK、本タスクでは仕様のみ)

### F7 [MEDIUM]: pre-commit scanner 導入
問題: Safe Memory の混入防止が gitignore のみ。
修正: `.pre-commit-config.yaml` を新規作成:
```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.x.x
    hooks:
      - id: gitleaks
  - repo: local
    hooks:
      - id: user-profile-no-secrets
        name: USER_PROFILE に secret 実体が混入していないか検査
        entry: scripts/memory/check-no-plain-secrets.sh  # 未実装なら comment out で OK
        language: script
        files: '\.ai/USER_PROFILE.*\.yaml$'
```
- `.claude/rules/memory-lifecycle.md` の gitignore セクションに pre-commit 運用を追記

## Instructions

1. レビュー原文 `.ai/CODEX/RESULTS/T-OS-151R.md` を精読
2. F1〜F7 を順次実装 (最小 diff)
3. 既存 example/yaml の整合性を保つ (schema 変更 → example も更新)
4. mock judge 置換 (F3) は repeated-question 系のみ。他は mock のまま残す
5. 実装後に `bash .claude/evals/manager-quality/run.sh` を実行し、repeated-question 系の一部が pass するか確認
6. **重要**: `.ai/DECISIONS.md`, `.ai/TASKS.yaml` は編集禁止

### 設計方針
- 最小差分で対応 (Major refactor は避ける)
- 後方互換: 既存の fact に新フィールドを必須化する場合は default 値を与える
- F3 の mock judge 置換では、assertion が強すぎないように (false positive を避ける)

## Reference (必読)
- `.ai/CODEX/RESULTS/T-OS-151R.md` - レビュー指摘原文 (SSOT)
- `.ai/DESIGN/CHATGPT_PRO_REVIEW_2026-04-18.md` - Pro 指摘の原典
- 既存: `.claude/schemas/user-profile.yaml`, `.claude/rules/memory-lifecycle.md`, `.claude/evals/manager-quality/report.py`

## Report

`.ai/CODEX/RESULTS/T-OS-151F.md` + stdout:
1. 変更ファイル一覧
2. F1〜F7 対応表
3. Manager Quality Eval 再実行結果 (repeated-question 系で pass する件数)
4. 残課題 (LOW 指摘 3 件の T-OS-151G 提案)
5. ステータス: DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
