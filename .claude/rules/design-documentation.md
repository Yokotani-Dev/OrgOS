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
# 1. 技術リサーチ（最新情報の収集）
- id: T-DESIGN-RESEARCH
  title: "技術リサーチ: 最新ツール・ライブラリ・ベストプラクティス調査"
  status: queued
  deps: []
  owner_role: "org-architect"
  notes: "WebSearch で最新情報を収集し .ai/RESOURCES/ に保存"

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
| Web アプリ（フルスタック） | RESEARCH + ARCH + CONTRACT + UI |
| API / バックエンド | RESEARCH + ARCH + CONTRACT |
| CLI ツール | RESEARCH + ARCH |
| ライブラリ | RESEARCH + ARCH + CONTRACT（API設計） |
| リファクタリング | RESEARCH + ARCH |

プロジェクト種別は BRIEF.md の内容から自動判定する。

---

## ドキュメントの格納先

```
.ai/
  DESIGN/
    ARCHITECTURE.md     # アーキテクチャ概要
    API_CONTRACT.md     # API/データスキーマ定義
    UI_DESIGN.md        # 画面構成（UI がある場合）
    TECH_RESEARCH.md    # 技術リサーチ結果
```

---

## /org-tick での自動実行

DESIGN ステージの /org-tick で以下を自動実行:

1. **リサーチタスクが未実行なら最優先で実行**
   - WebSearch で最新技術情報を収集
   - 結果を .ai/RESOURCES/ および .ai/DESIGN/TECH_RESEARCH.md に保存
   - 収集した情報を後続の設計タスクのコンテキストとして使用

2. **設計ドキュメントタスクを順番に実行**
   - ARCH → CONTRACT → UI の順
   - 各ドキュメントは .ai/DESIGN/ に生成

3. **設計レビューを自動トリガー**
   - 全設計ドキュメント完了後、org-reviewer で設計レビューを実行

---

## リサーチの実行方法

技術リサーチタスク（T-DESIGN-RESEARCH）では以下を実行:

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
