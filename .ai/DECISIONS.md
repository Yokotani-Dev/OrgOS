# DECISIONS

> 意思決定の記録。Manager が更新する。
> Owner は OWNER_COMMENTS.md 経由で決定を伝える。

---

## Decision Types

- **B1 (info-gap)**: 情報不足で決められない → 調査タスクで解決
- **B2 (tradeoff)**: トレードオフがあり Owner 判断が必要

---

## Pending (Owner Review)

(なし)

<!--
決定待ちの例：
- ID: D-001
  Title: 認証方式の選択
  Type: B2 (tradeoff)
  Context: ユーザー認証の実装方式を決める必要がある
  Options:
    1. JWT + Cookie（シンプル、既存実装あり）
    2. OAuth2（拡張性高い、実装コスト高）
    3. Firebase Auth（マネージド、ベンダーロック）
  Recommendation: Option 1（既存資産活用）
  Blocked tasks: T-003, T-004
  Owner decision: (待ち)
-->

---

## Decided

- ID: D-001
  Title: 成果物格納ディレクトリの標準化
  Decision: `.ai/ARTIFACTS/` を新設し、サブディレクトリで分類
  Decided by: Owner
  Date: 2026-01-20
  Rationale: 入力(RESOURCES)と出力(ARTIFACTS)を明確に分離し、成果物の配置場所を標準化

<!--
決定済みの例：
- ID: D-001
  Title: 認証方式の選択
  Decision: Option 1 (JWT + Cookie)
  Decided by: Owner
  Date: 2026-01-18
  Rationale: 既存実装を活用し、開発速度を優先
-->

---

## RELEASE-001: v0.11.0 公開 (2026-01-23)

### 決定内容
- OrgOS v0.11.0 を公開リポジトリにリリース

### 公開内容
- AI ドリブン開発ルール追加
  - `.claude/rules/ai-driven-development.md`
  - Manager が技術判断を主導、Owner はビジネス判断のみ
- 評価ループルール追加
  - `.claude/rules/eval-loop.md`
- manifest 更新（上記2ファイルを追加）

### 技術的判断
- HTTPS を使用（gh CLI の認証情報を利用）
  - 理由: SSH 接続がサンドボックスで制限される可能性があるため
- `public` リモートを HTTPS に変更

### 公開先
- リポジトリ: https://github.com/Yokotani-Dev/OrgOS
- コミット: 394f24e
- タグ: v0.11.0
- ファイル数: 52

