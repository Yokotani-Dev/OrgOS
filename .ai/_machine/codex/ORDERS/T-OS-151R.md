# Work Order: T-OS-151R (Review)

## Task
- ID: T-OS-151R
- Title: T-OS-151 (Safe Memory) 独立レビュー
- Role: reviewer
- Priority: P0

## Allowed Paths
- `.ai/CODEX/RESULTS/T-OS-151R.md` (結果記録用、書き込みはここだけ)

## Context

T-OS-151 で実装された Safe Memory (USER_PROFILE as fact registry) を独立レビューする。
**実装者の自己報告を信用しない** (Pro 指摘の Iron Law)。独立検証が役割。

### レビュー対象ファイル (read-only)
- `.ai/USER_PROFILE.yaml`
- `.ai/USER_PROFILE.example.yaml`
- `.claude/schemas/user-profile.yaml`
- `.claude/rules/memory-lifecycle.md`
- `.gitignore` (USER_PROFILE.yaml が gitignored か確認)

### 参照ドキュメント
- `.ai/CODEX/ORDERS/T-OS-151.md` (元 Work Order)
- `.ai/CODEX/RESULTS/T-OS-151.md` (実装者の自己報告)
- `.ai/DESIGN/CHATGPT_PRO_REVIEW_2026-04-18.md` (Pro 指摘の SSOT)

## レビュー観点

### R1: Pro 指摘への対応確認
以下の 4 点が実装されているか独立検証:
- secret 実体を YAML に置いていない (secret_ref URI 形式)
- facts / secrets / preferences が分離されている
- 必須フィールド: scope, confidence, source, source_ref, valid_from, expires_at, pii_level が全てに存在
- 「覚えていること」の修正・失効ルール (memory-lifecycle.md に 6 操作)

### R2: schema 妥当性
- `.claude/schemas/user-profile.yaml` が YAML として parseable か
- 必須フィールドと optional の区別が明確か
- enum の値が網羅的か (例: pii_level の粒度)
- 拡張余地が残されているか (将来の graph memory 移行に耐える schema か)

### R3: Iron Law 厳格性
`memory-lifecycle.md` で定義された 6 操作 (capture→normalize→scope→retrieve→validate→retire/promote) が:
- 本当に例外なし (Iron Law) として書かれているか
- 各操作に違反検出方法があるか
- Red Flag (Iron Law 違反兆候) が定義されているか

### R4: 誤転移防止
Pro 指摘: 誤転移リスク
- 全 fact に scope が必須か
- transferability フィールドがあるか (あれば確認、なければ指摘)
- Global / Domain / Project の 3 層スコープに対応しているか

### R5: gitignore 設定確認
- `.ai/USER_PROFILE.yaml` が gitignored されているか
- `.ai/USER_PROFILE.example.yaml` は commit 対象として残っているか
- secret 混入を防ぐ pre-commit hook への参照があるか

### R6: past_qa の統一管理
Work Order A5 で指示された「past_qa も fact として統一管理」が実装されているか。

### R7: Manager Quality Eval との連動
- run.sh を 1 回実行し、USER_PROFILE 参照のモックが suite を壊していないか
- metrics.yaml の repeated_question_rate / decision_trace_completeness が USER_PROFILE を参照する設計になっているか

### R8: 未解決リスクの発見
自己報告には書かれていない、以下の潜在問題を探索:
- 大規模化した時のパフォーマンス (facts が 1000 超えたら？)
- 複数プロセス同時書き込みの競合
- scope の命名規則 ("project:orgos" vs "project_orgos" の揺れ)
- pii_level の判定基準が曖昧でないか

## Instructions

1. 上記 R1〜R8 を順次独立検証
2. 実装者の自己報告 (`.ai/CODEX/RESULTS/T-OS-151.md`) を参照しつつ、**独立に事実確認**
3. 「自己報告で主張されているが実際に検証可能か」を各項目で確認
4. 発見した問題は重要度別に分類: CRITICAL / HIGH / MEDIUM / LOW
5. 修正提案を具体的に記載 (ファイル名・行番号・改善内容)
6. **重要**: ファイル編集は一切しない (書き込みは `.ai/CODEX/RESULTS/T-OS-151R.md` のみ)

## Report

`.ai/CODEX/RESULTS/T-OS-151R.md` に以下を記録:

```markdown
# T-OS-151R Review Report

## 総合判定
- ◎ (優秀・修正不要) / ○ (妥当・軽微な修正) / △ (要修正) / × (根本やり直し)

## 観点別評価
### R1: Pro 指摘対応
- 判定: ...
- 確認内容: ...
- 問題点: ...

### R2-R8: 各観点
(同様の形式)

## 発見した問題 (重要度別)
### CRITICAL
- [ファイル]:[行] - [内容] - [修正案]
### HIGH
...
### MEDIUM
...
### LOW
...

## 修正提案
- 修正タスク候補の提案 (T-OS-151 FIX-XXX 形式)

## ステータス
- APPROVED / APPROVED_WITH_MINOR_FIXES / CHANGES_REQUESTED / REJECTED
```

stdout 最終メッセージに上記の総合判定と CRITICAL/HIGH 発見事項のサマリーを記載。
