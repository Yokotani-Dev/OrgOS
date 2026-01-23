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

## PLAN-UPDATE-001: タスク追加（上司レビューモード + 引き継ぎ機能）(2026-01-23)

### 変更内容
- 追加: T-OS-004（上司レビューモード機能）
- 追加: T-OS-005（プロジェクト引き継ぎ機能）

### 理由
- 部下がOrgOSを使う際の課題に対応
  - 判断能力が低く、何でもYesYesと言ってブラックボックス化
  - やりたいことと計画がずれる
- 上司が進捗・判断をレビューしやすくする
- 上司が途中まで進めて部下に引き継ぐパターンに対応

### 機能概要（T-OS-004: 上司レビューモード）
1. /org-start 時に「作業者」「上司レビュー要否」を質問
2. 重要な判断時に上司レビュー用ドキュメント自動生成
3. 計画乖離（BRIEF.mdとのずれ）を自動検知
4. 上司承認待ち状態で停止

### 3つのモード
- 自分 + レビューあり: 重要な判断で上司レビューをリマインド
- 自分のみ: 上司レビューなし
- 部下 + スーパーバイザー: 部下が作業、上司レビュー必須

### 機能概要（T-OS-005: 引き継ぎ機能）
1. 引き継ぎ情報を CONTROL.yaml に記録（誰から誰へ、どこまで完了）
2. 引き継ぎドキュメント（.ai/HANDOFF.md）自動生成
3. git pull 後の SessionStart で引き継ぎを検知
4. 引き継ぎ時の注意事項を表示

### 依存関係
- T-OS-005 は T-OS-004 完了後に実装（CONTROL.yaml の supervisor_review を活用）

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

