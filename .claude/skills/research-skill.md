# 最新情報取得スキル（Research Skill）

> 設計フェーズで最新の技術情報を自動収集し、設計判断の根拠とする

---

## 概要

このスキルは設計フェーズで自動的に起動され、以下を実行する:

1. BRIEF.md / PROJECT.md から技術キーワードを抽出
2. WebSearch で最新情報を検索
3. 結果を構造化して .ai/DESIGN/TECH_RESEARCH.md に保存
4. 設計判断の根拠として提供

---

## 起動タイミング

| タイミング | トリガー | 説明 |
|-----------|---------|------|
| DESIGN ステージ遷移時 | 自動 | T-DESIGN-RESEARCH タスクとして実行 |
| 技術選定時 | 自動 | org-architect が技術選定を行う際 |
| Owner の要求時 | 手動 | 「最新情報を調べて」等の依頼 |

---

## 実行手順

### Step 1: キーワード抽出

BRIEF.md / PROJECT.md から以下を抽出:

```
- 使用予定の技術（フレームワーク、言語、ライブラリ）
- 解決すべき技術課題（認証、決済、リアルタイム通信など）
- 対象プラットフォーム（Web、モバイル、デスクトップ）
- 非機能要件（パフォーマンス、セキュリティ、スケーラビリティ）
```

### Step 2: 検索クエリの生成

キーワードごとに以下のクエリパターンで検索:

```
# 技術の最新動向
"[技術名] latest version features [現在の年]"
"[技術名] best practices [現在の年]"

# 代替技術の比較
"[技術名] vs alternatives comparison [現在の年]"
"[技術名] vs [競合技術] benchmark [現在の年]"

# 課題の解決策
"[課題] solution architecture [現在の年]"
"[課題] best approach [フレームワーク名] [現在の年]"

# セキュリティ
"[技術名] security best practices [現在の年]"
"[技術名] known vulnerabilities [現在の年]"
```

**重要:** 検索クエリには必ず現在の年（CONTROL.yaml の date-awareness ルール参照）を含める。

### Step 3: 情報の構造化

収集した情報を以下の形式で整理:

```markdown
# 技術リサーチ結果

## 調査日: [YYYY-MM-DD]

## 1. [技術名/課題名]

### 最新状況
- 最新バージョン: [バージョン]
- リリース日: [日付]
- 主な変更点: [概要]

### 推奨パターン
- [パターン1]: [説明]
- [パターン2]: [説明]

### 注意点・既知の問題
- [注意点1]
- [注意点2]

### 代替技術
| 技術 | メリット | デメリット | 推奨度 |
|------|---------|-----------|--------|
| [技術A] | | | ★★★ |
| [技術B] | | | ★★☆ |

### 参考URL
- [タイトル](URL)
```

### Step 4: 設計への反映

リサーチ結果を設計ドキュメントに反映:

1. **ARCHITECTURE.md** の「技術スタック」セクションに選定理由を記載
2. **DECISIONS.md** に技術選定の根拠を記録
3. **RISKS.md** に技術リスク（EOL、セキュリティ脆弱性等）を記録

---

## モデル選定リサーチ（特別ケース）

AI モデルの選定が必要な場合、以下の追加リサーチを実行:

```
# モデルベンチマーク
"LLM benchmark comparison [現在の年]"
"[用途] best AI model [現在の年]"

# コスト比較
"[モデル名] pricing API cost [現在の年]"

# 実績・レビュー
"[モデル名] production experience [現在の年]"
```

### モデル比較テンプレート

```markdown
## AI モデル比較

| モデル | 用途適性 | 速度 | コスト | 精度 | 推奨 |
|--------|---------|------|--------|------|------|
| [モデルA] | | | | | |
| [モデルB] | | | | | |

### 用途別推奨
- コード生成: [推奨モデル]
- テキスト分析: [推奨モデル]
- 画像処理: [推奨モデル]
```

---

## 保存先

```
.ai/
  DESIGN/
    TECH_RESEARCH.md    # メインのリサーチ結果
  RESOURCES/
    research/           # 詳細な調査資料（必要に応じて）
      [topic]-research.md
```

---

## org-tick での統合

org-tick の診断チェック（Step 7）で以下を追加:

```python
# DESIGN ステージの場合
if stage == "DESIGN":
    # リサーチタスクが未実行なら最優先で実行
    if not research_completed():
        agents_to_run.insert(0, "research")  # 最優先

    # 設計ドキュメントが未作成なら自動生成
    if not design_docs_completed():
        agents_to_run.append("org-architect")
```

---

## 参考資料

- [.claude/rules/design-documentation.md](../rules/design-documentation.md) - 設計ドキュメントルール
- [.claude/rules/date-awareness.md](../rules/date-awareness.md) - 日付認識ルール
