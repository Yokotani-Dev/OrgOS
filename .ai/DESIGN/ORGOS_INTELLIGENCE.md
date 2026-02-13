# OrgOS Intelligence — 全体設計書

> AI 技術トレンドを日次で収集・分析し、Owner への情報提供と OrgOS 自己進化を駆動する仕組み

**ステータス**: 要件確定（全未決事項を解消済み）
**作成日**: 2026-01-30
**最終更新**: 2026-01-30

---

## 1. 目的

### 解決する課題

AI の進化は日進月歩であり、Owner が手動でキャッチアップし、OrgOS への改善を指示する運用では最新技術をフルに活用できない。

### OrgOS Intelligence が実現すること

1. **Owner への日次インプット**: AI 界隈で何が起きているかを毎日 Slack で届ける
2. **OrgOS への自己進化提案**: 収集した情報から OS 改善を提言（OIP-AUTO）し、Owner が Slack で承認後に適用する

### スコープ

- OrgOS 自体の開発・改善に特化（個別プロジェクトの文脈には対応しない）
- Slack Bot はインテリジェンスレポート配信 + その内容の対話に限定
- OrgOS の外部器官として**別リポジトリ** `orgos-intelligence` に構築

### スコープ外

- 個別プロジェクトへの技術適用判断
- OrgOS 以外のシステムへの変更
- L4（モデル再学習・蒸留）

---

## 2. 決定済み要件一覧

| # | 項目 | 決定内容 |
|---|------|---------|
| 1 | 配信先 | Slack（既存 Workspace に Bot 追加） |
| 2 | チャンネル | `#orgos-intelligence` |
| 3 | 配信時刻 | 毎朝 9:00 JST |
| 4 | 配信頻度 | 毎日（土日含む）、週次ダイジェストは月曜 |
| 5 | レポート言語 | 日本語（原文リンクは英語のまま） |
| 6 | AI（収集・フィルタ） | Gemini Flash（低コスト大量処理） |
| 7 | AI（深掘り調査） | Gemini Deep Research API（HIGH トピックのみ） |
| 8 | AI（分析・OIP生成） | Claude Sonnet（OrgOS 文脈理解） |
| 9 | AI（Slack 対話） | Claude Sonnet（OrgOS 親和性） |
| 10 | Web 検索 | Google Custom Search API |
| 21 | 収集方式 | 差分ベース（前回収集以降の新着を全取得。件数固定ではない） |
| 11 | ホスティング | Cloudflare Workers Paid ($5/月)（新規アカウント作成） |
| 12 | Bot 範囲 | レポート専用（OrgOS タスク管理等は VSCode/ターミナル） |
| 13 | 対話コンテキスト | 過去7日分のレポートを参照可能 |
| 14 | 承認 UI | Slack ボタン + テキスト返信の両方対応 |
| 15 | OIP 承認期限 | 7日無応答で自動保留（3日目にリマインド） |
| 16 | 初期の承認レベル | 全提案 Owner 承認必須（Level 1 自動承認は Evals 整備後に解禁） |
| 17 | エラー時 | 取得できた分だけで配信（失敗ソースを明記） |
| 18 | 空の日 | 件数より質優先。LOW まで下げて1件しかなければそれで配信 |
| 19 | ソース追加 | Slack で「このURL監視して」と依頼可能 |
| 20 | コスト上限 | $50/月以内 |
| 22 | リポジトリ | 別リポジトリ `orgos-intelligence` |
| 23 | トピック内容 | 純粋な AI ニュース（OrgOS 固有の文脈はトピックに含めない。OrgOS 分析は OIP-AUTO セクションのみ） |
| 24 | ニュース日付 | 各トピック見出しにソースの日付を明記（例: `### タイトル（2026-01-26）`）。「1月」のような月単位は不可、必ず日まで特定する |
| 25 | トピック数 | 最低10件。質を保てる範囲で多く収録 |
| 26 | トピック種別 | 技術トピックのみ（M&A・資金調達等のビジネスニュースは除外） |
| 27 | 鮮度フィルタ | 直近1週間以内のニュースのみ採用 |
| 28 | 選定主体 | Manager が自律的に選定（Owner に候補提示して選ばせない） |
| 29 | 選定基準 | 具体的なリリース・発表であること。一般論・浅いリスト・まとめ記事は不可。「だから何？」に答えられるもの |
| 30 | レポート構成 | 冒頭にトピック目次（タイトル+要点+日付の箇条書き）→ 詳細セクション → OIP-AUTO |
| 31 | OIP-AUTO 粒度 | 各提案に「現状の課題」「具体的にやること（手順）」「変更対象ファイル」「工数」「リスク」を明記。Owner が承認可否を判断できる粒度 |

---

## 3. 全体アーキテクチャ

```
orgos-intelligence (別リポジトリ)          OrgOS (既存リポジトリ)
┌─────────────────────────────────┐      ┌──────────────────────┐
│                                 │      │                      │
│  Cloudflare Workers             │      │  .ai/INTELLIGENCE/   │
│  ┌───────────────────────────┐  │      │    reports/           │
│  │ Cron Trigger (9:00 JST)  │  │      │    raw/               │
│  │                           │  │      │    config.yaml        │
│  │  1. 情報収集              │  │      │                      │
│  │     RSS/API/Google Search │  │      │  .claude/             │
│  │                           │  │      │    agents/            │
│  │  2. フィルタ・要約        │  │      │    rules/             │
│  │     Gemini Flash          │  │      │    skills/            │
│  │                           │  │      │                      │
│  │  3. 分析・OIP生成         │  │      └──────────┬───────────┘
│  │     Claude Sonnet         │  │                 │
│  │                           │  │                 │
│  │  4. Slack 投稿            │──┼──→ Slack        │
│  │     Block Kit + ボタン    │  │   #orgos-intel  │
│  │                           │  │                 │
│  │  5. リポジトリ保存        │──┼──→ commit/push ─┘
│  └───────────────────────────┘  │
│                                 │
│  Slack Events Handler           │
│  ┌───────────────────────────┐  │
│  │ スレッド対話              │  │
│  │   Claude Sonnet           │  │
│  │   過去7日分コンテキスト   │  │
│  │                           │  │
│  │ 承認処理                  │  │
│  │   ボタン or テキスト検知  │──┼──→ OrgOS に PR
│  │   → DECISIONS.md 更新     │  │
│  │   → OIP ステータス更新    │  │
│  │                           │  │
│  │ ソース追加                │  │
│  │   「このURL監視して」     │──┼──→ config.yaml 更新
│  └───────────────────────────┘  │
│                                 │
└─────────────────────────────────┘
```

### リポジトリ間の関係

```
orgos-intelligence
  ├─ src/                    # Worker + Bot コード
  │   ├─ collector/          # 情報収集
  │   ├─ analyzer/           # 分析・OIP生成
  │   ├─ reporter/           # レポート生成
  │   ├─ slack/              # Slack Bot
  │   └─ github/             # OrgOS リポジトリ連携
  ├─ wrangler.toml           # Cloudflare Workers 設定
  └─ package.json

OrgOS（既存）
  ├─ .ai/INTELLIGENCE/       # レポート蓄積（Intelligence が commit）
  │   ├─ config.yaml         # 監視設定
  │   ├─ raw/                # 生データ
  │   ├─ reports/            # 日次レポート
  │   └─ weekly/             # 週次ダイジェスト
  ├─ .claude/                # ← Intelligence が承認済み OIP を PR
  └─ .ai/DECISIONS.md        # ← OIP 承認/却下を記録
```

---

## 4. 情報収集

### 4.1 ソース階層

| Tier | 信頼度 | ソース | 取り扱い |
|------|--------|--------|---------|
| **Tier 1** | 公式 | Anthropic Blog/Changelog, OpenAI Blog/Changelog, Google DeepMind Blog, GitHub Releases（主要SDK）, Claude Code Release Notes | 事実として扱う |
| **Tier 2** | コミュニティ | Hacker News（上位）, GitHub Trending（AI/LLM）, arXiv（注目論文） | 検証付きで扱う |
| **Tier 3** | 実践知 | Latent Space, AI Engineer, Simon Willison's Blog, 主要エンジニアブログ | 参考情報として扱う |

### 4.2 収集方法

| ソース種別 | 技術手段 |
|-----------|---------|
| ブログ / Changelog | RSS/Atom フィード解析 |
| GitHub Releases | GitHub API (`/repos/{owner}/{repo}/releases`) |
| GitHub Trending | GitHub API or スクレイピング |
| Hacker News | HN API (`/v0/topstories`) |
| arXiv | arXiv API（AI/ML カテゴリ） |
| その他 | Google Custom Search API（特定キーワード） |

### 4.3 フィルタリング設定

```yaml
# .ai/INTELLIGENCE/config.yaml
watch_topics:
  # AI エージェント
  - AI agents / agentic patterns
  - multi-agent systems
  - agent evaluation / benchmarks

  # Claude / Anthropic
  - Claude Code / Claude API changes
  - MCP (Model Context Protocol)
  - Anthropic SDK updates

  # LLM 全般
  - prompt engineering
  - LLM evaluation / evals
  - coding assistants
  - AI safety / alignment

  # 開発手法
  - AI-driven development
  - AI code review
  - AI testing

sources:
  tier1:
    - url: "https://www.anthropic.com/blog/rss"
      name: "Anthropic Blog"
    - url: "https://openai.com/blog/rss"
      name: "OpenAI Blog"
    # ... 他のソース

  tier2:
    - url: "https://hacker-news.firebaseio.com/v0/topstories.json"
      name: "Hacker News"
    # ...

  tier3:
    - url: "https://simonwillison.net/atom/everything/"
      name: "Simon Willison"
    # ...

# ソース追加: Slack で「このURL監視して」と依頼すると
# Bot が tier と name を聞いてここに追加する
```

### 4.4 関連性スコアリング（Gemini Flash）

```
入力: 記事タイトル + 要約 + watch_topics
出力:
  - relevance: high / medium / low / none
  - category: model_update / tool_change / workflow / security / knowledge
  - orgos_impact: あり / なし / 要調査
```

- `none` は除外
- 通常は `medium` 以上をレポートに含める
- HIGH がない日は LOW まで閾値を下げる（ただし件数より質優先、水増ししない）

---

## 5. レポート設計

### 5.1 日次レポート

配信: 毎朝 9:00 JST、Slack Block Kit でメッセージ直接投稿

```markdown
# AI Intelligence Report — 2026-01-30

## Summary
今日の注目: [1行で最重要トピックを要約]
OrgOS への影響: [あり / なし / 要検討]

---

## Topics

### [HIGH] Anthropic: Claude API に Tool Use の新仕様が追加
- ソース: https://... (Tier 1)
- 概要: ...
- OrgOS への影響: エージェント定義の Tool 指定方法を更新すべき

### [MEDIUM] GitHub Trending: LangGraph が v0.3 をリリース
- ソース: https://... (Tier 2)
- 概要: ...
- OrgOS への影響: 直接的な影響なし。マルチエージェント設計の参考になる

### [LOW] Simon Willison: プロンプトキャッシュの実践レポート
- ソース: https://... (Tier 3)
- 概要: ...
- OrgOS への影響: コスト最適化の参考

---

## OrgOS Update Proposals

### [OIP-AUTO-012] Tool Use 仕様の更新対応
- トリガー: Claude API の Tool Use 仕様変更（本日の Tier 1 情報）
- 変更対象: .claude/agents/*.md の Tool 定義
- 影響範囲: Userland（エージェント定義）
- リスク: 低
- 提案: 新仕様に合わせてエージェント定義を更新
- [承認] [却下] [詳しく]  ← Slack ボタン

---

## Noise（除外した情報）
- [記事タイトル] — 除外理由: OrgOS に関連なし

---
⚠️ 収集失敗: OpenAI Blog（タイムアウト）
```

### 5.2 週次ダイジェスト（毎週月曜 9:00 JST）

```markdown
# Weekly AI Digest — 2026-W05 (01/27 - 02/02)

## 今週のハイライト
1. ...
2. ...
3. ...

## トレンド分析
- 上昇トレンド: ...
- 注目すべき変化: ...

## OrgOS 更新サマリー
- 承認・適用済み: OIP-AUTO-012, OIP-AUTO-014
- 保留中: OIP-AUTO-013
- 却下: なし

## 来週の注目ポイント
- [予定されているリリース、カンファレンス等]
```

### 5.3 ファイル蓄積（OrgOS リポジトリ側）

```
.ai/INTELLIGENCE/
  config.yaml              # 監視設定（ソース、トピック）
  raw/                     # 生データ（日付別 JSON）
    2026-01-30.json
  reports/                 # 日次レポート
    2026-01-30.md
  weekly/                  # 週次ダイジェスト
    2026-W05.md
```

---

## 6. Slack Bot 設計

### 6.1 機能一覧

| 機能 | 説明 |
|------|------|
| **日次レポート投稿** | 毎朝 9:00 JST、`#orgos-intelligence` に Block Kit で投稿 |
| **週次ダイジェスト投稿** | 毎週月曜 9:00 JST に投稿 |
| **スレッド対話** | レポートのスレッドで Owner と対話（過去7日分のコンテキスト参照） |
| **OIP 承認処理** | ボタン or テキスト（「OK」「却下」）を検知し、OrgOS リポジトリに PR |
| **ソース追加** | 「このURL監視して」→ config.yaml に追加 |
| **OIP リマインド** | 承認待ち3日目にリマインド、7日で自動保留 |

### 6.2 対話パターン

```
Owner: 「これもう少し詳しく」
Bot:   [該当トピックの詳細説明。ソース記事の要約、
        技術的な解説、OrgOS への具体的な影響を説明]
       （過去7日分のレポートも文脈として参照可能）

Owner: [承認ボタンをクリック] or 「OIP-AUTO-012 OK」
Bot:   「OIP-AUTO-012 を承認しました。
        OrgOS リポジトリに PR を作成します。
        DECISIONS.md に記録しました。」

Owner: [却下ボタンをクリック] or 「OIP-AUTO-013 却下」
Bot:   「OIP-AUTO-013 を却下しました。
        理由を教えていただけますか？（任意）
        DECISIONS.md に記録しました。」

Owner: 「https://example.com/blog も監視して」
Bot:   「追加します。Tier はどれにしますか？
        [Tier 1: 公式] [Tier 2: コミュニティ] [Tier 3: 実践知]」
Owner: [Tier 3 ボタンをクリック]
Bot:   「config.yaml に Tier 3 として追加しました。
        明日のレポートから反映されます。」

Owner: 「先週の Claude API の変更ってどうなった？」
Bot:   [過去7日分のレポートを検索して回答]
```

### 6.3 Slack Block Kit 構成

レポート投稿時の Block Kit 構造:

```
┌─────────────────────────────────────┐
│ 📊 AI Intelligence Report           │
│ 2026-01-30                          │
├─────────────────────────────────────┤
│                                     │
│ Summary                             │
│ 今日の注目: ...                      │
│                                     │
│ ─────────────────────               │
│                                     │
│ 🔴 [HIGH] Anthropic: ...            │
│ 概要: ...                           │
│ OrgOS影響: ...                      │
│                                     │
│ 🟡 [MEDIUM] GitHub: ...             │
│ 概要: ...                           │
│ OrgOS影響: ...                      │
│                                     │
│ ─────────────────────               │
│                                     │
│ OrgOS Update Proposals              │
│                                     │
│ OIP-AUTO-012: Tool Use 仕様更新     │
│ リスク: 低 | 影響: Userland         │
│ [✅ 承認] [❌ 却下] [💬 詳しく]      │
│                                     │
│ OIP-AUTO-013: 並列実行改善          │
│ リスク: 中 | 影響: Userland         │
│ [✅ 承認] [❌ 却下] [💬 詳しく]      │
│                                     │
└─────────────────────────────────────┘
```

### 6.4 技術選定

| 要素 | 選定 | 理由 |
|------|------|------|
| Web フレームワーク | **Hono** | Cloudflare Workers ネイティブ。リクエストルーティング、署名検証 |
| Slack API | **@slack/web-api** | メッセージ投稿・Block Kit 構築。Workers 上で動作（HTTP クライアントのみ） |
| Slack Events 受信 | **Hono エンドポイント** | Events API / Interactive Components を直接受信。Bolt 不使用 |
| ホスティング | **Cloudflare Workers Paid** ($5/月) | CPU 30秒、cron 内蔵。無料プランでは AI API 呼び出し不可 |
| 状態管理 | **Cloudflare KV** | レポートキャッシュ、OIP 採番・ステータス、config キャッシュ |
| AI（収集・フィルタ・要約） | Gemini Flash | $0.10/M input、大量記事の関連性判定・要約に最適 |
| AI（深掘り調査） | Gemini Deep Research API | HIGH トピックのみ。背景・ベストプラクティス・実装パターンまで自動調査 |
| AI（分析・OIP生成） | Claude Sonnet | Deep Research 結果を入力に、OrgOS 文脈で OIP を生成 |
| AI（Slack 対話） | Claude Sonnet | OrgOS 文脈での対話 |
| Web 検索 | Google Custom Search API | 無料枠 100回/日（日次使用回数を監視、80回で警告） |
| OrgOS 連携 | **GitHub App** | 最小権限（`contents: write`）。レポートは main 直接 push、OIP は PR 経由 |

#### Slack Bolt を使わない理由

Slack Bolt (`@slack/bolt`) は Node.js ランタイムを前提としており、Cloudflare Workers（V8 isolate）上では動作しない。内部で `http` モジュールや `express` 等の Node.js 依存を持つため。代わりに:
- **Hono**: ルーティング + Slack 署名検証
- **@slack/web-api**: メッセージ投稿のみ（HTTP クライアントとして使用）
- Events API / Interactive Components は Hono のエンドポイントで直接ハンドリング

---

## 7. GitHub 認証・連携設計

### 7.1 認証方式: GitHub App

**GitHub App を作成し、OrgOS リポジトリへの最小権限アクセスを実現する。**

| 項目 | 設定 |
|------|------|
| App 名 | `orgos-intelligence-bot` |
| 権限 | `contents: write`（commit/push + PR 作成に必要） |
| インストール先 | OrgOS リポジトリのみ |
| 認証方式 | Installation Access Token（短命トークンを都度発行） |

Personal Access Token ではなく GitHub App を使う理由:
- 最小権限の原則（リポジトリ単位で権限を限定）
- トークンが短命（1時間で失効）でセキュリティリスクが低い
- Bot として commit（`orgos-intelligence-bot[bot]`）が明示される

### 7.2 操作別のブランチ戦略

| 操作 | ブランチ | 方式 | 理由 |
|------|---------|------|------|
| 日次レポート保存 | `main` 直接 push | commit | 自動生成データ。レビュー不要 |
| 週次ダイジェスト保存 | `main` 直接 push | commit | 同上 |
| OIP 承認後の変更適用 | PR 作成 (`oip-auto/OIP-AUTO-xxx`) | Pull Request | .claude/ への変更はレビュー可能にする |
| config.yaml 更新 | `main` 直接 push | commit | ソース追加は軽微な変更 |

### 7.3 秘密情報の管理

| 秘密情報 | 保存先 |
|----------|--------|
| GitHub App の秘密鍵 | Cloudflare Workers Secrets |
| GitHub App ID | Cloudflare Workers Secrets |
| Slack Bot Token | Cloudflare Workers Secrets |
| Slack Signing Secret | Cloudflare Workers Secrets |
| Claude API Key | Cloudflare Workers Secrets |
| Gemini API Key | Cloudflare Workers Secrets |
| Google Custom Search API Key | Cloudflare Workers Secrets |
| Google Custom Search Engine ID | Cloudflare Workers Secrets |

---

## 8. Cloudflare KV 設計

### 8.1 用途

| 用途 | Key パターン | Value | TTL |
|------|-------------|-------|-----|
| レポートキャッシュ（対話用） | `report:YYYY-MM-DD` | レポート JSON | 8日 |
| OIP-AUTO カウンタ | `oip-auto:counter` | 最新番号 (number) | なし（永続） |
| OIP-AUTO ステータス | `oip-auto:XXX` | `{ status, created_at, reminded_at, title, level }` | 90日 |
| config キャッシュ | `config:current` | config.yaml の内容 (JSON) | なし（明示的更新） |
| Google Search 使用回数 | `search-count:YYYY-MM-DD` | 使用回数 (number) | 2日 |

### 8.2 KV Namespace

```toml
# wrangler.toml
[[kv_namespaces]]
binding = "INTEL_KV"
id = "xxx"
```

### 8.3 config.yaml の読み込み戦略

1. Cron 実行時: KV の `config:current` を読む
2. KV にない場合: GitHub API で OrgOS リポジトリから取得 → KV にキャッシュ
3. Slack でソース追加時: KV を即時更新 + GitHub に commit

---

## 9. 処理パイプライン設計

### 9.1 Workers 実行時間制限への対応

Cloudflare Workers Paid の CPU 時間制限は 30秒。
日次レポート生成は複数の外部 API 呼び出しを含むため、1回の Workers 呼び出しでは完結しない可能性がある。

### 9.2 パイプライン構成

```
Cron Trigger (9:00 JST)
  │
  ▼
Step 1: 差分収集 (Workers)
  ├─ RSS/API 巡回（並列 fetch、前回収集以降の新着のみ）
  ├─ Google Custom Search（前日以降の記事を対象）
  └─ 結果を KV に保存: `raw:YYYY-MM-DD`
  │
  ▼
Step 2: フィルタリング + 要約 (Gemini Flash)
  ├─ KV から raw データ読み込み
  ├─ OrgOS 関連性を判定（HIGH / MEDIUM / LOW）
  └─ 各記事を要約
  │
  ▼
Step 3: 深掘り調査 (Gemini Deep Research API) ← HIGH トピックのみ
  ├─ HIGH 判定されたトピックを Deep Research で調査
  ├─ 背景・ベストプラクティス・実装パターンまで収集
  └─ 結果を KV に保存
  │
  ▼
Step 4: OIP 分析・レポート生成 (Claude Sonnet)
  ├─ Deep Research 結果 + Flash 要約を入力
  ├─ OrgOS 文脈で OIP-AUTO を生成
  ├─ レポート JSON を KV に保存: `report:YYYY-MM-DD`
  └─ OIP-AUTO を KV に保存
  │
  ▼
Step 5: 配信・保存 (Workers)
  ├─ Slack に Block Kit 投稿
  ├─ OrgOS リポジトリに commit (レポート .md)
  └─ 完了ログを KV に保存
```

### 9.2.1 差分収集の仕組み

件数固定ではなく、**前回収集以降の新着を全て取得**する。

| ソース種別 | 差分検出方法 |
|-----------|-------------|
| RSS | `pubDate` が前回収集日時以降のエントリを取得 |
| Google Custom Search | `dateRestrict=d1`（過去1日以内）パラメータで絞り込み |
| GitHub Trending | 日次更新のため、毎回全量取得（差分は内容ベースで判定） |
| ブログ/公式サイト | RSS がない場合は Google Custom Search で `site:` 指定 |

**KV に最終収集日時を記録:**
- Key: `last-collected-at`
- Value: ISO 8601 タイムスタンプ
- 各ソースごとに `last-collected-at:<source-id>` も保持

**結果が0件の日:**
- 「本日の新着はありませんでした」と短いレポートを配信
- Deep Research / OIP 生成はスキップ

### 9.2.2 Deep Research の使用条件

Gemini Deep Research API は以下の条件を**全て満たす**トピックにのみ使用:

1. Step 2 で **HIGH** と判定された
2. OrgOS への影響がある（`orgos_impact = あり`）
3. 1日あたり最大 **3件** まで（コスト制御）

3件を超える HIGH トピックがある場合は、OrgOS 影響度が高い順に優先。
残りは Gemini Flash の要約のみで配信。

### 9.3 実行戦略

**まずは単一 Workers で全ステップを直列実行する（Phase 1）。**

理由:
- Workers Paid の壁時計時間（wall time）は制限が緩い（CPU 30秒だが I/O 待ちは含まない）
- 外部 API 呼び出しの大半は I/O 待ち（fetch のレスポンス待ち）
- CPU 集約処理はほぼない

**CPU 30秒を超える場合のみ、Cloudflare Queues で分割する（Phase 1 検証後に判断）。**

### 9.4 月曜の追加処理

月曜は日次レポートに加えて週次ダイジェストを生成:
- KV から過去7日分の `report:YYYY-MM-DD` を取得
- Claude Sonnet で週次サマリーを生成
- Slack に追加投稿 + OrgOS リポジトリに commit

---

## 10. OrgOS 自己進化フロー（旧7章）

### 7.1 OIP-AUTO の生成条件

レポート生成時に、以下の全条件を満たす情報から OIP-AUTO を自動生成:

1. OrgOS に影響がある（`orgos_impact = あり`）
2. 具体的な変更対象ファイルが特定できる
3. 変更の仮説が明確
4. 検証方法が存在する

### 7.2 承認レベル（初期運用）

**初期は全提案 Owner 承認必須。Level 1 自動承認は OS Evals 整備後に解禁。**

| Level | 対象 | 初期運用 | Evals整備後 |
|-------|------|---------|------------|
| **Level 0** | 情報記録のみ | 承認不要 | 承認不要 |
| **Level 1** | Userland 軽微変更 | **Owner 承認必須** | 自動承認可（Evals通過が条件） |
| **Level 2** | Userland 重要変更 | Owner 承認（Slack） | Owner 承認（Slack） |
| **Level 3** | Kernel 変更 | Owner 承認必須 + 影響分析 | Owner 承認必須 + 影響分析 |

### 7.3 適用フロー

```
OIP-AUTO 生成
  │
  ├─ Level 0: そのまま記録（レポートに掲載のみ）
  │
  ├─ Level 1-2: Slack で提案（ボタン付き）
  │   ├─ Owner「承認」→ OrgOS リポジトリに PR 作成
  │   ├─ Owner「却下」→ DECISIONS.md に記録
  │   ├─ 3日無応答 → Slack リマインド
  │   └─ 7日無応答 → 自動保留（DECISIONS.md に記録）
  │
  └─ Level 3: Slack で提案 + 影響分析を添付
      ├─ Owner 明示的承認 → PR 作成
      └─ それ以外 → 適用しない
```

### 7.4 承認後の反映

```
Owner 承認
  │
  ▼
Intelligence が OrgOS リポジトリに PR を作成
  │
  ├─ PR タイトル: "[OIP-AUTO-012] Tool Use 仕様の更新対応"
  ├─ PR 本文: 変更内容、トリガー、影響範囲
  ├─ 変更ファイル: .claude/agents/*.md 等
  │
  ▼
次の /org-tick で Manager が PR をマージ
  │
  ▼
DECISIONS.md に適用記録
```

### 7.5 ロールバック

適用後に問題が検出された場合:

```
問題検出（手動 or OS Evals）
  │
  ▼
git revert で変更を取り消し
  │
  ▼
Slack に通知: 「OIP-AUTO-012 をロールバックしました。理由: ...」
  │
  ▼
DECISIONS.md に記録
```

---

## 11. OS Evals（免疫系）

### 8.1 位置づけ

OIP-AUTO を安全に適用するための免疫系。
**初期は未整備のため、全提案 Owner 承認必須で運用。**
Evals 整備後に Level 1 自動承認を解禁する。

### 8.2 最低限必要な Evals（将来整備）

| テスト | 検証内容 |
|--------|---------|
| **台帳整合性** | TASKS.yaml, DECISIONS.md のスキーマが正しい |
| **エージェント定義** | .claude/agents/*.md が必須フィールドを持つ |
| **安全制御** | セキュリティルールが存在し、矛盾がない |
| **ゲート保護** | Kernel 領域のファイルが不正変更されていない |

### 8.3 Intelligence 固有の Evals

| テスト | 検証内容 |
|--------|---------|
| **ソース到達性** | 設定された RSS/API が応答する |
| **レポート品質** | 生成されたレポートが必須セクションを持つ |
| **OIP 整合性** | OIP-AUTO が必須フィールド（トリガー、影響範囲、リスク）を持つ |

---

## 12. Kernel / Userland 境界

### Kernel（自動変更禁止、Level 3 承認必須）

```
.claude/rules/security.md          # 安全制御
.claude/rules/review-criteria.md   # レビュー基準（CRITICAL判定）
.claude/rules/project-flow.md      # 基本フロー
.ai/CONTROL.yaml                   # OS 制御設定
```

### Userland（Intelligence が提案可能、Level 1-2）

```
.claude/agents/*.md                # エージェント定義
.claude/rules/agent-coordination.md # モデル選択、並列実行パターン
.claude/rules/performance.md       # パフォーマンス設定
.claude/skills/*.md                # 技術スキル
.claude/rules/testing.md           # テスト基準（追加方向のみ）
```

---

## 13. エラーハンドリング

| エラー | 挙動 |
|--------|------|
| 一部ソースの取得失敗 | 取得できた分だけでレポート生成。失敗ソースをレポート末尾に明記 |
| 全ソース取得失敗 | Slack にエラー通知のみ（「本日の収集は全ソース失敗しました」） |
| Gemini Flash API エラー | Claude Haiku にフォールバック |
| Claude Sonnet API エラー | Slack にエラー通知。レポートは Topics のみ（OIP生成スキップ） |
| Slack API エラー | リトライ（3回まで）。全失敗なら OrgOS リポジトリへの保存のみ |
| OrgOS リポジトリへの push 失敗 | Slack にエラー通知。次回 cron で再試行 |

---

## 14. コスト見積もり

### 月額コスト（概算）

| コンポーネント | 月額 | 内訳 |
|---------------|------|------|
| **Cloudflare Workers Paid** | $5 | CPU 30秒、cron、KV 拡張枠 |
| **Gemini Flash** | ~$1-3 | 日次の差分記事フィルタ・要約 |
| **Gemini Deep Research** | ~$2-5 | HIGH トピック × 最大3件/日 × 30日 |
| **Claude Sonnet** | ~$5-15 | 日次OIP分析 + 週次ダイジェスト + Slack対話 |
| **Google Custom Search** | $0 | 無料枠内（100回/日、80回で警告） |
| **Slack** | $0 | Bot は無料 |
| **合計** | **~$13-28/月** | $50上限に対して余裕あり |

### コスト最適化

- 収集・フィルタリングは Gemini Flash（安い）に任せる
- Claude Sonnet は OIP 生成と対話のみ
- 対話がない日は Sonnet コストほぼゼロ
- 週次ダイジェスト生成時は、KV の要約済みレポートを入力にし、raw データを再処理しない

---

## 15. コンポーネント一覧

| # | コンポーネント | 役割 | 技術 | リポジトリ |
|---|---------------|------|------|-----------|
| 1 | **情報収集** | RSS/API/Google Search でソース巡回 | TypeScript, Hono | orgos-intelligence |
| 2 | **フィルタ・要約** | 記事の関連性判定・要約 | Gemini Flash | orgos-intelligence |
| 2b | **深掘り調査** | HIGH トピックの詳細調査 | Gemini Deep Research API | orgos-intelligence |
| 3 | **分析・OIP生成** | Deep Research 結果 + OrgOS 文脈で OIP-AUTO 生成 | Claude Sonnet | orgos-intelligence |
| 4 | **レポート生成** | Block Kit 形式のレポート構築 | TypeScript | orgos-intelligence |
| 5 | **Slack 連携** | 投稿・対話・承認処理 | Hono + @slack/web-api | orgos-intelligence |
| 6 | **OrgOS 連携** | レポート保存、承認済みOIPのPR作成 | GitHub App + API | orgos-intelligence |
| 7 | **状態管理** | レポートキャッシュ、OIP採番・ステータス | Cloudflare KV | orgos-intelligence |
| 8 | **監視設定** | ソース・トピック・閾値の管理 | config.yaml | OrgOS |
| 9 | **OS Evals** | 変更の安全性検証（将来） | テストスクリプト | OrgOS |

---

## 16. 成熟度ロードマップ

| Phase | 内容 | 前提 |
|-------|------|------|
| **Phase 0** | 手動で1回レポートを生成し、質を確認 | なし |
| **Phase 1** | Cloudflare Workers で日次自動収集 + レポート生成 + OrgOS リポジトリ保存 | Workers + API キー |
| **Phase 2** | Slack Bot でレポート配信 + ボタン付き承認 + スレッド対話 | Slack App 構築 |
| **Phase 3** | OIP-AUTO 生成 + 承認 → OrgOS PR 自動作成 | Phase 2 完了 |
| **Phase 4** | OS Evals 整備 + Level 1 自動承認解禁 | Evals 基盤 |
| **Phase 5** | ロールバック機構 + Kernel 保護の自動検知 | Phase 4 完了 |
| **Phase 6** | ソース追加の Slack 対話フロー | Phase 2 完了 |

---

## 17. セキュリティ考慮事項

| リスク | 対策 |
|--------|------|
| API キーの漏洩 | Cloudflare Workers の Secrets に保存。リポジトリに含めない |
| Slack Bot の不正利用 | Bot は `#orgos-intelligence` チャンネルのみ応答 |
| 外部ソースからの汚染 | Tier に応じた信頼度表記。Tier 3 の情報は「参考」として明記 |
| OrgOS への不正変更 | PR 経由でのみ変更。Kernel ファイルは Level 3 承認必須 |
| コスト暴走 | 月額上限 $50 をアラート設定。閾値超過で自動停止 |

---

## 18. 既知の制約・注意事項

| # | 項目 | 内容 | 対策 |
|---|------|------|------|
| 1 | Block Kit 50ブロック制限 | Slack は1メッセージ50ブロックまで | トピック10件超は分割投稿 |
| 2 | Google Search 無料枠 | 100回/日。ソース追加で依存が増加する可能性 | 80回/日で警告。KV でカウント |
| 3 | Workers CPU 時間 | Paid でも CPU 30秒。ただし I/O 待ちは含まない | Phase 1 で検証し、必要なら Queues で分割 |
| 4 | KV の結果整合性 | KV は結果整合性（eventually consistent） | レポート生成は単一 Worker で完結するため影響なし |

---

## 19. この設計書の位置づけ

本書は要件が確定した全体設計書である。
次のステップで各コンポーネントの詳細設計・実装に進む。

### 関連ドキュメント（今後必要に応じて作成）

- `.ai/DESIGN/INTELLIGENCE_COLLECTION.md` — 情報収集の詳細設計
- `.ai/DESIGN/INTELLIGENCE_SLACK_BOT.md` — Slack Bot の詳細設計
- `.ai/DESIGN/INTELLIGENCE_OIP_FLOW.md` — OIP-AUTO フローの詳細設計
- `.ai/DESIGN/ORGOS_EVALS.md` — OS Evals の設計
- `.ai/DESIGN/ORGOS_KERNEL_USERLAND.md` — Kernel/Userland 境界の定義
