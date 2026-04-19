# OrgOS セルフレビュー — 完璧な状態とのギャップ分析

> 実施日: 2026-04-18
> 実施者: Manager（4 並列 Explore subagent による多観点調査 → 統合）
> 依頼者: Owner（「今の構成や使い方をセルフレビューしてみて」）

---

## 総合診断スコア: **76 / 100**

| 観点 | スコア | 主要ボトルネック |
|------|--------|-----------------|
| A. 自律駆動の徹底度 | 70 | 選択肢提示 38 箇所・セッション終了選択肢の残骸 |
| B. エコシステム接続 | 40 | MCP/aitmpl.com/Slack/GitHub 連携が計画段階のみ |
| C. 運用インフラ | 55 | 観測性・リカバリ・自己回帰テストが原始的 |
| D. UX・知識継承 | 76 | アーキ図・用語集・肥大化対応の欠落 |

---

## 「完璧な OrgOS」の定義

| カテゴリ | 完璧な姿 |
|----------|----------|
| A. 自律性 | Owner は依頼を 1 回投げたら、結果だけ受け取る。途中の選択・確認ゼロ。 |
| B. エコシステム | 世界中の agents/skills/MCP と相互運用。自動取り込み・還元ループ。 |
| C. 運用 | 24/7 自動回復。メトリクス・トレンドで自己認識。失敗時自動ロールバック。 |
| D. UX | 初見 3 分で理解。1000 プロジェクト並行でも劣化なし。ベテラン／新人問わず即戦力。 |

---

## A. 自律駆動の中途半端さ（原則違反の残骸）

> **問題**: T-OS-070 で方針転換したがドキュメント層のみ。実装層に旧設計の残骸。

| # | 重要度 | 内容 | 位置 |
|---|-------|------|------|
| A-1 | CRITICAL | セッション終了の選択肢提示が残存 `[A] 新しいセッション [B] 継続` | `.claude/commands/org-tick.md` L192-200 |
| A-2 | HIGH | `.claude/commands/` 全体で「選択肢:」が **38 箇所** | org-start/org-goals/org-settings 等 |
| A-3 | HIGH | 「スコープ外 → Owner 確認」の過剰残存 | `project-flow.md` L70,L115 / `plan-sync.md` L127 |
| A-4 | HIGH | Iron Law 網羅性 **3/15 agents のみ保有**（12 エージェント無防備） | agents/ 全体 |
| A-5 | HIGH | 非推奨 `org-implementer` 参照が rules に残存 | `agent-coordination.md` L53,56 |
| A-6 | MEDIUM | ad-hoc 実行検出ロジックが未実装（ルール文面のみ） | project-flow.md |

---

## B. エコシステム接続の未熟（OS としての孤立）

> **問題**: OrgOS は「孤立した OS」。外部信号を吸収できない自給自足状態。

| # | 重要度 | 内容 | 工数 |
|---|-------|------|------|
| B-1 | CRITICAL | aitmpl.com / skills.sh / superpowers 連携は **計画のみ**（T-OS-100〜103 queued） | 大 |
| B-2 | CRITICAL | MCP 統合が CONTROL.yaml で定義のみ・実行パイプラインなし | 大 |
| B-3 | HIGH | Intelligence Pipeline は「監視トピック定義」のみ・実装なし | 大 |
| B-4 | HIGH | Slack webhook 設定欄あるが未使用 (`evolve.slack_webhook: ""`) | 小 |
| B-5 | HIGH | GitHub / Linear / Jira 連携 **全無し**（計画もない） | 大 |
| B-6 | HIGH | /org-dashboard はパスリストのみ・プロジェクト間学習転移ゼロ | 中 |

---

## C. 運用インフラの欠如（本番運用不可レベル）

> **問題**: 一度つまずくと止まる。SLA 達成不可。

| # | 重要度 | 内容 | 工数 |
|---|-------|------|------|
| C-1 | HIGH | メトリクス収集なし（Tick 時間・Codex 成功率・エラー率・コスト） | 中 |
| C-2 | HIGH | Codex CLI 失敗時のリトライ機構ゼロ（そのまま次タスクへ） | 中 |
| C-3 | HIGH | .ai/ 台帳破損時の修復ロジックなし（手動介入必須） | 中 |
| C-4 | HIGH | 自己回帰テスト未実装（OrgOS が自分を壊さない保証なし） | 中 |
| C-5 | MEDIUM | checkpoint 評価が定義のみ（org-tick の実装に integration なし） | 小 |
| C-6 | MEDIUM | 監査ログなし・secret scanning なし・role-based access なし | 中 |
| C-7 | MEDIUM | TASKS.yaml に done タスク **31 件** が滞留（アーカイブ移動停止） | 小 |
| C-8 | MEDIUM | 並列タスク片方失敗時の復旧フロー未定義 | 中 |

---

## D. UX・知識継承の弱さ（人間の学習曲線）

> **問題**: 初見で迷う。長期利用で劣化する。

| # | 重要度 | 内容 | 工数 |
|---|-------|------|------|
| D-1 | CRITICAL | アーキテクチャ図が ASCII のみ・Mermaid/画像なし | 小 |
| D-2 | CRITICAL | 初見 Owner 向けフロー図（/org-start → /org-tick → /org-evolve）なし | 小 |
| D-3 | HIGH | Dashboard UI の Markdown vs 実装の整合性未定義 | 中 |
| D-4 | MEDIUM | Iron Law / Red Flags / CSO の用語集（GLOSSARY.md）が散在・統合なし | 小 |
| D-5 | MEDIUM | DECISIONS.md **878 行**・TOC なし・検索性低 | 小 |
| D-6 | MEDIUM | TASKS.yaml 肥大化対応（500 超）の自動アーカイブ基準なし | 小 |
| D-7 | MEDIUM | STATUS.md vs RUN_LOG の役割分離（T-OS-034）が実装で曖昧 | 小 |
| D-8 | LOW | Codex 環境依存（`/opt/homebrew/bin/codex` Mac 前提） | 中 |

---

## 推奨対応順序（Manager 判断）

### 第1波: A カテゴリ完遂（自律駆動の残骸一掃）
**理由**: OrgOS のアイデンティティ直結。既に方針転換済みなので低コストで達成可能。

- A-1 修正: org-tick.md L192-200 の選択肢削除
- A-2 一括修正: commands/ 38 箇所の選択肢を「Manager 判断 → 報告」に置換
- A-3 修正: rules 3 ファイルの「Owner 確認」例外を狭める
- A-4: 12 agents に Iron Law 追加
- A-5 修正: agent-coordination.md の非推奨参照更新

### 第2波: C カテゴリの CRITICAL（本番運用可能化）
- C-2 Codex リトライラッパー
- C-7 TASKS.yaml 自動アーカイブ
- C-1 簡易メトリクス（metrics.json 出力）

### 第3波: D カテゴリの可視化（オンボーディング改善）
- D-1,D-2 Mermaid 図追加（低コスト・高効果）
- D-4 GLOSSARY.md 作成

### 第4波: B カテゴリ（エコシステム接続）
- T-OS-100〜103（aitmpl.com 連携）既登録 → 実行

---

## 結論

OrgOS は **設計・統治の枠組みが優秀**（台帳 SSOT、役割分離、ゲート制御、自律改善ループ）だが、以下 4 点で「完璧な OS」への昇華にギャップがある:

1. **自律性の未完遂**: ドキュメントは自律主導に転換済みだが、実装に旧設計の残骸
2. **エコシステム孤立**: 外部との双方向接続（入力: パターン取込 / 出力: スキル還元）が未実装
3. **運用耐性の欠如**: 観測性・リカバリ・自己回帰テストが原始的で本番運用不可
4. **学習曲線の急勾配**: ビジュアル化・用語集・肥大化対応が未整備

「1 つのプロジェクト向けの高度な Manager」域にあり、「組織全体を駆動する OS」への完成には **推定 3-4 ヶ月**。

---

## 出典

- 4 並列 Explore による統合（構造/自律駆動/機能/UX の各観点）
- Owner 依頼（2026-04-18）
