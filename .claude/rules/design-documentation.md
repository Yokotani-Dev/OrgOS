# 設計ドキュメント自動生成ルール

> DESIGN ステージで設計ドキュメントを主体的にバックログし、自動生成する

---

## 原則

**設計フェーズに入ったら、Manager が主体的に設計ドキュメント作成タスクをバックログする。**
Owner に「ドキュメントを作って」と言われる前に、自ら計画に組み込む。

---

## DESIGN ステージ遷移時の自動タスク生成

DESIGN ステージに遷移した時点で、以下のタスクを TASKS.yaml に自動追加する:

### 必須ドキュメントタスク

```yaml
# 0. 参照・競合調査（最優先・必須）
- id: T-DESIGN-REFS
  title: "参照・競合調査: 類似サービス/プロダクトのリサーチ"
  status: queued
  deps: []
  owner_role: "org-architect"
  notes: |
    BRIEF.md の「参照サイト・プロダクト」と「作りたいもの」を元に、
    類似サービスを WebSearch で調査。UI/UX、機能構成、技術スタックを分析。
    結果を .ai/DESIGN/REFERENCES.md に記録。

# 1. 技術リサーチ（最新情報の収集）
- id: T-DESIGN-RESEARCH
  title: "技術リサーチ: 最新ツール・ライブラリ・ベストプラクティス調査"
  status: queued
  deps: ["T-DESIGN-REFS"]
  owner_role: "org-architect"
  notes: "WebSearch で最新情報を収集し .ai/RESOURCES/ に保存。参照調査の結果を踏まえて技術選定。"

# 2. アーキテクチャ設計書
- id: T-DESIGN-ARCH
  title: "設計ドキュメント: アーキテクチャ概要"
  status: queued
  deps: ["T-DESIGN-RESEARCH"]
  owner_role: "org-architect"
  notes: "技術選定の根拠、全体構成図、コンポーネント間の関係"

# 3. API/データ設計
- id: T-DESIGN-CONTRACT
  title: "設計ドキュメント: API/データスキーマ定義"
  status: queued
  deps: ["T-DESIGN-ARCH"]
  owner_role: "org-architect"
  notes: "エンドポイント一覧、リクエスト/レスポンス形式、DB スキーマ"

# 4. 画面設計（UI がある場合）
- id: T-DESIGN-UI
  title: "設計ドキュメント: 画面構成・コンポーネント設計"
  status: queued
  deps: ["T-DESIGN-ARCH"]
  owner_role: "org-architect"
  notes: "画面一覧、コンポーネントツリー、状態管理方針"
```

### タスク生成の判断基準

| プロジェクト種別 | 生成するタスク |
|------------------|---------------|
| Web アプリ（フルスタック） | REFS + RESEARCH + ARCH + CONTRACT + UI |
| API / バックエンド | REFS + RESEARCH + ARCH + CONTRACT |
| CLI ツール | REFS + RESEARCH + ARCH |
| ライブラリ | REFS + RESEARCH + ARCH + CONTRACT（API設計） |
| リファクタリング | RESEARCH + ARCH（REFS は任意） |

プロジェクト種別は BRIEF.md の内容から自動判定する。

---

## ドキュメントの格納先

```
.ai/
  DESIGN/
    REFERENCES.md       # 参照・競合調査結果（必須）
    ARCHITECTURE.md     # アーキテクチャ概要
    API_CONTRACT.md     # API/データスキーマ定義
    UI_DESIGN.md        # 画面構成（UI がある場合）
    TECH_RESEARCH.md    # 技術リサーチ結果
```

---

## /org-tick での自動実行

DESIGN ステージの /org-tick で以下を自動実行:

1. **参照・競合調査が未実行なら最優先で実行**
   - BRIEF.md の「参照サイト・プロダクト」「作りたいもの」からキーワード抽出
   - WebSearch で類似サービスを調査（UI/UX、機能構成、技術スタック）
   - 結果を .ai/DESIGN/REFERENCES.md に保存
   - 「何を真似る / 何を変える」を明確にする

2. **技術リサーチタスクを実行**
   - 参照調査の結果を踏まえて技術選定の調査
   - 結果を .ai/RESOURCES/ および .ai/DESIGN/TECH_RESEARCH.md に保存

3. **設計ドキュメントタスクを順番に実行**
   - ARCH → CONTRACT → UI の順
   - 参照調査の「真似る/変える」を設計に反映
   - 各ドキュメントは .ai/DESIGN/ に生成

4. **設計レビューを自動トリガー**
   - 全設計ドキュメント完了後、org-reviewer で設計レビューを実行

---

## リサーチの実行方法

### 参照・競合調査（T-DESIGN-REFS）

参照調査タスクでは以下を実行:

```
1. BRIEF.md から調査対象を抽出
   - 「参照サイト・プロダクト」に記載された具体名
   - 「作りたいもの」の類似カテゴリ
   - 「ペルソナ」が現在使っている代替手段

2. WebSearch で類似サービスを調査
   - "[サービス名] features review"
   - "[カテゴリ] best apps/tools 2026"
   - "[カテゴリ] UI design patterns"

3. 各参照の分析（REFERENCES.md に記録）
   - サービス名・URL
   - 主要機能の一覧
   - UI/UX の特徴
   - 技術スタック（判明する範囲）
   - ユーザー評価・レビュー

4. 「真似る / 変える」の判断
   - 真似る: 各参照の良い点（UI パターン、機能フロー）
   - 変える: 差別化ポイント、BRIEF の要件と合わない部分
   - この判断を DECISIONS.md に記録
```

### 技術リサーチ（T-DESIGN-RESEARCH）

技術リサーチタスクでは以下を実行:

```
1. BRIEF.md から技術キーワードを抽出
   - 使用予定の技術スタック
   - 解決すべき技術課題
   - 類似プロジェクト・競合

2. WebSearch で最新情報を検索
   - "[技術名] best practices 2026"
   - "[技術名] alternatives comparison 2026"
   - "[課題] solution architecture 2026"

3. 結果を構造化して保存
   - .ai/DESIGN/TECH_RESEARCH.md に整理
   - 各技術の最新バージョン、推奨パターン、注意点を記録

4. 設計判断の根拠として活用
   - DECISIONS.md に技術選定の根拠を記録
   - 最新情報に基づいた推奨を提示
```

---

## 設計ドキュメントのテンプレート

### REFERENCES.md

```markdown
# 参照・競合調査

## 調査概要
[BRIEF.md の「作りたいもの」に基づく調査の背景]

## 参照サービス一覧

### 1. [サービス名]
- **URL**: [URL]
- **概要**: [1-2文で説明]
- **主要機能**: [箇条書き]
- **UI/UX の特徴**: [注目すべきパターン]
- **技術スタック**: [判明する範囲]
- **ユーザー評価**: [良い点/悪い点]

### 2. [サービス名]
...

## 真似る / 変える

### 真似る（取り入れるべき良いパターン）
- [参照元] → [何を真似るか、なぜ]

### 変える（差別化 or BRIEF の要件に合わない部分）
- [参照元の何を] → [どう変えるか、なぜ]

## 設計への反映
[この調査結果を設計にどう活かすかの方針]
```

### ARCHITECTURE.md

```markdown
# アーキテクチャ設計書

## 概要
[プロジェクトの技術的な全体像]

## 技術スタック
| レイヤー | 技術 | バージョン | 選定理由 |
|----------|------|-----------|----------|
| フロントエンド | | | |
| バックエンド | | | |
| データベース | | | |
| インフラ | | | |

## システム構成図
[コンポーネント間の関係を記述]

## データフロー
[主要なデータの流れを記述]

## 非機能要件
- パフォーマンス: [目標値]
- セキュリティ: [方針]
- スケーラビリティ: [方針]

## 技術的判断の根拠
[TECH_RESEARCH.md の結果に基づく判断を記載]
```

---

## 参考資料

- [.claude/skills/research-skill.md](../skills/research-skill.md) - 最新情報取得スキル
- [.claude/rules/plan-sync.md](plan-sync.md) - 計画の継続的更新
- [.ai/DESIGN/](../../.ai/DESIGN/) - 設計ドキュメント格納先

---

## Pre-Implementation Risk Profile 追加ルール

`.claude/rules/pre-implementation-risk-profile.md` に従い、DESIGN フェーズでは実装前リスクを固定する 3 文書を必須成果物として扱う。

### 追加必須ドキュメントタスク

DESIGN ステージに遷移した時点で、既存の必須ドキュメントタスクに加えて以下を TASKS.yaml に自動追加する:

```yaml
# 5. 脅威モデル
- id: T-DESIGN-THREAT
  title: "設計ドキュメント: 脅威モデル"
  status: queued
  deps: ["T-DESIGN-CONTRACT"]
  owner_role: "org-architect"
  notes: |
    Race condition、重複、権限漏れ、認証回避、データ漏洩、暴走、
    入力検証欠落、エラー隠蔽の 8 カテゴリを全て評価する。
    結果を .ai/DESIGN/THREAT_MODEL.md に記録し、該当なしの場合も理由を書く。

# 6. データモデル全体図
- id: T-DESIGN-DATAMODEL-FULL
  title: "設計ドキュメント: データモデル全体図"
  status: queued
  deps: ["T-DESIGN-CONTRACT"]
  owner_role: "org-architect"
  notes: |
    全テーブル、ER 図、主要 entity の状態遷移、不変条件、
    トランザクション境界、冪等性 key、削除戦略を .ai/DESIGN/DATA_MODEL_FULL.md に記録する。

# 7. 権限境界マップ
- id: T-DESIGN-AUTHORITY
  title: "設計ドキュメント: 権限境界マップ"
  status: queued
  deps: ["T-DESIGN-THREAT", "T-DESIGN-DATAMODEL-FULL"]
  owner_role: "org-architect"
  notes: |
    ロール一覧、CRUD x role の権限マトリクス、RLS policy、RPC / Function 権限、
    認証境界、セッション管理、監査ログ要件を .ai/DESIGN/AUTHORITY_BOUNDARY.md に記録する。
```

### プロジェクト種別判定ルールの更新

既存の種別判定に加えて、以下に該当する project / milestone では 3 文書を必須生成する:

| 判定 | 条件 | 追加で必須になる文書 |
|---|---|---|
| regulated | PII、契約、金銭、法務、監査、広告表現、権限付き操作を扱う | THREAT_MODEL + DATA_MODEL_FULL + AUTHORITY_BOUNDARY |
| transactional | create / update / delete、決済類似処理、予約、申請、状態遷移、webhook、retryable job がある | THREAT_MODEL + DATA_MODEL_FULL + AUTHORITY_BOUNDARY |
| multi-user | anonymous / authenticated / admin / tenant / owner など複数 actor が同じ resource に触る | THREAT_MODEL + DATA_MODEL_FULL + AUTHORITY_BOUNDARY |

判定は OR 条件である。1 つでも該当したら 3 文書は必須であり、`mvp` でも省略してはならない。

### ドキュメント格納先の追加

```
.ai/
  DESIGN/
    THREAT_MODEL.md        # 脅威モデル（8 カテゴリ必須）
    DATA_MODEL_FULL.md     # 全テーブル + ER + 状態遷移 + 不変条件 + transaction / idempotency
    AUTHORITY_BOUNDARY.md  # role / CRUD / RLS / RPC / authn / session / audit
```

テンプレートは以下を使用する:

- `.ai/TEMPLATES/THREAT_MODEL.md`
- `.ai/TEMPLATES/DATA_MODEL_FULL.md`
- `.ai/TEMPLATES/AUTHORITY_BOUNDARY.md`

### /org-tick での自動実行の追加

DESIGN ステージの `/org-tick` は、既存の参照調査、技術リサーチ、ARCH / CONTRACT / UI 生成に加えて以下を実行する:

1. **THREAT_MODEL.md を生成**
   - Journey の happy_path / error_paths と API / data contract から該当箇所を抽出
   - 8 Threat Categories を全て評価
   - 対策と検証方法を実装可能な粒度で記録

2. **DATA_MODEL_FULL.md を生成**
   - API / data contract から全テーブル、ER 図、状態遷移、不変条件を整理
   - write 系操作の transaction boundary を固定
   - retry / webhook / double-submit が起きる操作の idempotency key を固定

3. **AUTHORITY_BOUNDARY.md を生成**
   - actor / role を列挙
   - resource ごとに CRUD x role の権限マトリクスを作成
   - RLS、RPC / Function、認証境界、session、audit log を明示

4. **DESIGN Gate を評価**
   - 3 文書が confirmed でなければ IMPLEMENTATION へ進めない
   - 不足があれば `blocked_by_design_gate` とし、Manager は不足文書と未決論点だけを Owner に提示する

### IMPLEMENTATION Gate への接続

IMPLEMENTATION Work Order には以下を必ず含める:

```markdown
## Pre-Implementation Risk Profile Reference
- THREAT_MODEL: .ai/DESIGN/THREAT_MODEL.md (confirmed)
- DATA_MODEL_FULL: .ai/DESIGN/DATA_MODEL_FULL.md (confirmed)
- AUTHORITY_BOUNDARY: .ai/DESIGN/AUTHORITY_BOUNDARY.md (confirmed)
- transaction_boundaries: confirmed
- idempotency_strategy: confirmed
```

この参照が欠けている Work Order は受理せず、DESIGN gate violation として扱う。
