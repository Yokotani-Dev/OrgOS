# OrgOS Intelligence Report — 2026-01-30 (木)

> 今日の AI ニュースまとめ（直近1週間: 1/23〜1/30）

---

## 目次

1. **Gemini 3 Flash** — SWE-bench 78% で Pro を超えたが、ハルシネーション率91%（1/29）
2. **Chrome Auto Browse** — AI がブラウザを自動操作、Chrome に標準搭載（1/28）
3. **Claude Agent SDK v2.1.0** — スキルホットリロード・フック強化（1/28）
4. **MCP Apps** — ツールがインタラクティブ UI を返せるようになった（1/26）
5. **Stanford 論文: LLM の計算限界** — ハルシネーションは構造的に不可避と数学的に証明（1/23）
6. **FastMCP 3.0 beta** — Provider/Transform パターンで再設計（1/20）
7. **Moltbot セキュリティ事件** — 偽 VS Code 拡張でマルウェア配布（1/27）
8. **Cursor 2.0** — バックグラウンドエージェント8並列、VM 分離（1/22）
9. **GPT-5.2** — 400K コンテキスト、client-side compaction API（1/24）
10. **IQuest-Coder 40B** — コミット遷移学習、ベンチマーク汚染問題（1/1）

---

## 詳細

### 1. Gemini 3 Flash リリース — SWE-bench 78% で Pro を超えたが、ハルシネーション率91%（2026-01-29）

Google が Gemini 3 Flash を公開。「速くて安い」モデルのはずが、コーディングベンチマーク（SWE-bench Verified 78%）で上位モデルの Gemini 3 Pro（76.2%）を超えた。

**スペック:**
- GPQA Diamond（PhD レベル推論）: 90.4%
- 処理速度: 218 tokens/秒、Pro の3倍高速
- 価格: $0.50/1M input、$3/1M output（Pro の数分の1）
- Gemini アプリ・AI Mode in Search のデフォルトモデルに

**注意点:** AA-Omniscience ベンチマークでのハルシネーション率が **91%** と、主要モデルの中で最悪。速度と精度のトレードオフが極端。

**なぜ注目か:** 「安いモデルが高いモデルを一部超える」パターンが頻発しており、モデル選択の基準が「大きい=良い」から「タスク適合性」に変わりつつある。ハルシネーション率の高さは、検証レイヤーなしでの本番利用に警鐘を鳴らす。

**参考:** [Google 公式ブログ](https://blog.google/products/gemini/gemini-3-flash/) / [AI Fire 解説](https://www.aifire.co/p/gemini-3-flash-the-2026-guide-to-the-new-king-of-coding)

---

### 2. Chrome に「Auto Browse」搭載 — AI がブラウザを自動操作（2026-01-28）

Google が Chrome に Gemini 3 ベースの **Auto Browse** 機能を追加。テキスト指示でブラウザ操作を AI に委任できる。

**具体的にできること:**
- 複数サイトでのホテル・航空券の価格比較
- フォーム入力、予約、サブスク管理
- 写真から類似商品を検索 → カートに入れる（割引コード適用まで）
- Chrome パスワードマネージャー連携でログインも可能（許可制）

**制限:** 購入・SNS 投稿前に確認ダイアログ。Amazon は Perplexity を自動アクセスで提訴済み、eBay も規約で AI 注文を禁止。サイト側の抵抗が始まっている。米国限定、Google AI Pro/Ultra 有料プランのみ。

**なぜ注目か:** Chrome シェア70%超。ここに AI エージェントが標準搭載されたことで「AI がブラウザを操る」がメインストリームに入る。一方、サイト側との法的摩擦がどう展開するかが焦点。

**参考:** [Google 公式ブログ](https://blog.google/products/and-platforms/products/chrome/gemini-3-auto-browse/) / [TechCrunch](https://techcrunch.com/2026/01/28/chrome-takes-on-ai-browsers-with-tighter-gemini-integration-agentic-features-for-autonomous-tasks/)

---

### 3. Claude Code v2.1.0 → 「Agent SDK」に改名 — スキルホットリロード・フック強化（2026-01-28）

Anthropic が Claude Code の大型アップデート（v2.1.0、1,096 コミット）をリリース。名称を「Claude Agent SDK」に変更。

**実務で影響が大きい新機能:**
- **スキルのホットリロード**: `.claude/skills/` を編集するとセッション再起動なしで即反映
- **フック強化**: ツール実行の前後に処理を挟める（PreToolUse, PostToolUse, Stop）。コミット前の自動検証やツール呼び出しのログ記録が可能
- **MCP Tool Search**: 数千ツール登録でも必要な時だけ読み込み、速度低下なし
- **Claude in Chrome (Beta)**: Chrome 拡張と連携してブラウザ直接操作
- **Claude for Excel (Beta)**: ピボットテーブル、チャート、ファイルアップロード対応

**その他:** Console が `platform.claude.com` に移行。Web Fetch ツール（beta）で URL からコンテンツ取得可能に。Analytics API でチーム利用状況をプログラマティックに取得。

**なぜ注目か:** 「Claude Code」→「Agent SDK」への改名は、コーディング支援から汎用エージェント基盤への転換宣言。スキルホットリロードはエージェント開発の試行錯誤速度を大幅に上げる。

**参考:** [VentureBeat](https://venturebeat.com/orchestration/claude-code-2-1-0-arrives-with-smoother-workflows-and-smarter-agents) / [GitHub CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

---

### 4. MCP Apps 正式発表 — ツールが UI を返せるようになった（2026-01-26）

MCP（Model Context Protocol）に初の公式拡張「MCP Apps」が追加。AI ツールがテキストだけでなく、**ダッシュボード・フォーム・ボタンなどのインタラクティブ UI** を返せるようになった。

**対応状況:**
- ChatGPT、Claude、Goose、VS Code がすでに対応
- Anthropic、OpenAI、MCP-UI の3社が共同で仕様策定
- 「1回作れば全 AI クライアントで動く」UI コンポーネントが実現

**MCP 全体の動き（Core Maintainer Update 1/23）:**
- 新 Core Maintainer 3名が参加（Peter, Caitie, Kurtis）
- 進行中の仕様拡張: DPoP 認証、Multi-turn SSE、Server Cards（サーバー発見）
- 「接続前にサーバーの能力を知る」仕組み（.well-known URL）を準備中

**なぜ注目か:** MCP がテキスト → UI → マルチメディアへと拡張中。「AI ツールのエコシステム」が Web 標準のように成長しつつある。Server Cards が実装されれば、ツール発見が自動化され、エージェントの自律性がさらに上がる。

**参考:** [MCP Apps 公式](http://blog.modelcontextprotocol.io/posts/2026-01-26-mcp-apps/) / [Core Maintainer Update](https://blog.modelcontextprotocol.io/posts/2026-01-22-core-maintainer-update/)

---

### 5. 「LLM には超えられない壁がある」— Stanford 論文が数学的に証明（2026-01-23）

Stanford の研究チームが、Transformer ベースの LLM に**根本的な計算限界がある**ことを数学的に証明した論文を発表。

**論文の核心:**
- 長さ N のプロンプトに O(n^k) 以上の計算量を要するタスクが含まれる場合、LLM は**必ずハルシネーションを起こす**（Theorem 1）
- 計算理論の「時間階層定理」に基づく証明。アーキテクチャ改善では解決不能な構造的制約
- 「列挙可能なモデルクラスでは、普遍的にハルシネーションフリーにはなれない」（計算可能性理論より）

**業界の反応:**
- 元 Infosys CEO: 「LLM が信頼できるようになることは絶対にない」
- Harmonic 社: LLM 出力を Lean（数学証明言語）でエンコードして検証するアプローチを実用化中
- OpenAI: 「精度が100%になることはない」と認めている

**なぜ注目か:** 「スケールすれば AGI になる」論に対する理論的な壁。実務的には LLM 出力の検証レイヤー（Evals、型チェック、テスト）が「あると良い」から「なければ危険」に格上げされる根拠。

**参考:** [WebProNews 解説](https://www.webpronews.com/ai-agents-math-ceiling-proof-of-transformer-limits/) / [arXiv](https://arxiv.org/abs/2511.12869)

---

### 6. FastMCP 3.0 beta — MCP フレームワークを Provider/Transform で再設計（2026-01-20）

MCP サーバーの Python フレームワーク FastMCP がメジャーバージョン 3.0（beta）をリリース。アーキテクチャを根本から再設計した。

**3つの新プリミティブ:**
- **Provider**: コンポーネントの供給元を統一。デコレータ、ファイルシステム、OpenAPI、リモートサーバーなど、どこからでもツールを読み込める
- **Transform**: コンポーネントを変換するミドルウェア。名前空間付与、リネーム、バージョンフィルタ等をソースコードに触れずに適用
- **Per-Component Authorization**: ツール・リソース単位で認証チェックを付与可能（`@tool(auth=my_handler)`）

**実用面:**
- FileSystemProvider: ディレクトリからデコレート済み関数を発見、ホットリロード対応
- SkillsProvider: エージェントのスキルファイルを MCP リソースとして公開
- v2 系（2.14.4）も並行メンテナンス中

**なぜ注目か:** MCP エコシステムの中核フレームワークが「ツールを登録する」から「ツールを動的に発見・変換・制御する」に進化。Provider パターンはエージェントがツールを自律的に発見・利用する基盤になる。

**参考:** [FastMCP 3.0 公式ブログ](https://jlowin.dev/blog/fastmcp-3) / [GitHub](https://github.com/jlowin/fastmcp/releases)

---

### 7. Moltbot セキュリティ事件 — 偽 VS Code 拡張でマルウェア配布、公開インスタンスに認証なし（2026-01-27）

人気 AI アシスタント Moltbot（旧 Clawdbot）を模した**偽の VS Code 拡張機能がマルウェアを配布**していた事件が発覚。さらに本物の Moltbot にも深刻なセキュリティ問題が複数発見された。

**偽拡張機能の手口:**
- 拡張名「ClawdBot Agent - AI Coding Assistant」として VS Code Marketplace に公開（1/27）
- IDE 起動時に自動で外部からペイロードをダウンロード → ScreenConnect（正規リモートアクセスツール）を悪用して攻撃者のサーバーに接続

**本物の Moltbot にも問題:**
- Shodan で数百のインスタンスが公開状態。8件は認証なしで完全アクセス可能
- サプライチェーン攻撃の PoC: ClawdHub（スキルライブラリ）に悪意あるスキルをアップロード → 7カ国の開発者がダウンロード
- プロンプトインジェクション: 悪意あるメールで AI にユーザーのメール5通を攻撃者に転送させる実証（5分で成功）

**なぜ注目か:** AI コーディングツールの普及に伴い、「AI を偽装したマルウェア」「AI ツール自体の脆弱性」という2つの攻撃面が急速に拡大している。VS Code Marketplace の審査体制、AI ツールのデフォルトセキュリティ設計が問われる事例。

**参考:** [The Hacker News](https://thehackernews.com/2026/01/fake-moltbot-ai-coding-assistant-on-vs.html) / [The Register](https://www.theregister.com/2026/01/27/clawdbot_moltbot_security_concerns/)

---

### 8. Cursor 2.0 — バックグラウンドエージェント8並列、VM 分離、Slack/Web から起動可能（2026-01-22）

Cursor が 2.0 をリリース。独自コーディングモデル Composer と、マルチエージェント・ワークスペースを搭載。

**バックグラウンドエージェント:**
- 最大8エージェントを並列実行。各エージェントは分離された Ubuntu VM で動作
- git worktree でブランチを分離。完了後 PR を自動作成
- Slack、Web、モバイルから起動可能。`&` をメッセージ先頭に付けるとクラウドに送信
- Ctrl+E で起動、独自の Docker ファイルも指定可能

**Composer モデル:**
- Cursor 独自のコーディングモデル。類似モデルの4倍高速、大半のタスクが30秒以内に完了
- Max Mode 対応モデルのみバックグラウンドエージェントで使用可能

**なぜ注目か:** IDE が「ファイルエディタ」から「エージェント・ワークベンチ」に進化した象徴的リリース。複数モデルに同じタスクをやらせて最良の結果を選ぶ「競争的並列実行」パターンが注目される。

**参考:** [Cursor 公式](https://cursor.com/changelog/2-0) / [DevOps.com](https://devops.com/cursor-2-0-brings-faster-ai-coding-and-multi-agent-workflows/)

---

### 9. GPT-5.2 リリース — 400K コンテキスト、client-side compaction API（2026-01-24）

OpenAI が GPT-5.2 をリリース。GPT-5 シリーズの最新版。

**主要スペック:**
- コンテキストウィンドウ: 400K tokens（GPT-5.1 から大幅拡大）
- AIME 2025 数学ベンチマーク: 100%（満点）
- ハルシネーション率: 6.2%（改善）
- オープンウェイトモデルも公開（GPT-oss-120B、GPT-oss-20B）

**開発者向け新機能:**
- **client-side compaction API**: 長時間会話で `/responses/compact` エンドポイントを呼ぶと、コンテキストを圧縮できる
- **xhigh reasoning effort level**: より深い推論モードを指定可能
- Custom GPT が 1/12 に GPT-5.2 に移行済み

**なぜ注目か:** 400K コンテキストとコンパクション API の組み合わせで、「長時間セッションでもコンテキストが溢れない」運用が現実的に。オープンウェイトモデルの公開は OpenAI のオープン戦略の転換点。

**参考:** [OpenAI Changelog](https://platform.openai.com/docs/changelog) / [Developer Changelog](https://developers.openai.com/changelog/)

---

### 10. IQuest-Coder 40B — 中国ヘッジファンド発の OSS コーディング AI、ベンチマーク汚染問題も（2026-01-01）

中国の量的ヘッジファンド Ubiquant（九坤投資）の AI 部門 IQuestLab が、オープンソースのコーディング AI **IQuest-Coder-V1** を公開。

**技術的な特徴:**
- 7B / 14B / 40B の3サイズ。128K コンテキスト対応
- **Code-Flow Training**: 静的コードではなく、コミット遷移・リポジトリの進化パターンから学習
- 40B Loop: 再帰 Transformer でパラメータ共有。VRAM ~60-65GB で動作（通常の40Bモデルは ~80GB）

**ベンチマーク問題:**
- 当初 SWE-bench Verified 81.4% を主張 → 独立監査で**データ汚染が発覚**（テストセットの未来のコミットをトレーニングデータに含んでいた）
- 修正後スコア: 76.2%（Claude Sonnet 4.5 の 77.2% に迫る）
- 独立テスターは「ベンチマーク最適化（benchmaxxing）が目立つ。実際の曖昧な要件やマルチリポデバッグでは劣る」と評価

**なぜ注目か:** Code-Flow Training（コミット遷移からの学習）は新しいアプローチ。一方、ベンチマーク汚染問題は OSS モデル評価の信頼性に関する警鐘。「数字の裏を確認する」必要性が改めて示された。

**参考:** [DEV Community](https://dev.to/yakhilesh/china-just-released-the-first-coding-ai-of-2026-and-its-crushing-everything-we-know-3bbj) / [Hugging Face](https://huggingface.co/IQuestLab/IQuest-Coder-V1-40B-Instruct)

---

## OrgOS 改善提案（OIP-AUTO 候補）

上記トピックから OrgOS に適用可能な改善を抽出。実装には Owner 承認が必要。

---

### OIP-AUTO-001: スキルホットリロード対応の検証

**きっかけ:** Claude Agent SDK v2.1.0 でスキルのホットリロードが可能に（トピック3）

**現状の課題:** OrgOS のスキル（`.claude/skills/*.md`）を編集した場合、反映にはセッション再起動が必要。スキルの改善サイクルが遅い。

**具体的にやること:**
1. v2.1.0 のホットリロードが OrgOS の `.claude/skills/` に対して動作するか検証
2. 動作する場合、スキル開発時の推奨フロー（編集 → 即テスト → 確定）を `session-management.md` に追記
3. 動作しない場合、制約を記録（例: rules/ は対象外、など）

**変更対象:** `.claude/rules/session-management.md`（フロー追記）
**工数:** 検証1回 + ドキュメント数行追加
**リスク:** 低（検証 + ドキュメント追記のみ）

---

### OIP-AUTO-002: Evals 設計に「ハルシネーション前提」の検証レイヤーを追加

**きっかけ:** Stanford 論文で LLM のハルシネーションは構造的に不可避と証明（トピック5）

**現状の課題:** OrgOS Intelligence の OIP-AUTO 自動適用（T-INT-004）では、AI が生成した変更を OS に適用する。しかし現在の Evals 設計（設計書 Section 11）は「テストが通ればOK」レベルで、AI 生成コードの正当性を積極的に検証する仕組みがない。

**具体的にやること:**
1. T-INT-004 の Evals 設計に以下の検証ステップを追加:
   - **構文検証**: 変更後のファイルが valid YAML/Markdown であること
   - **diff サイズ制限**: 1ファイルあたり50行以上の変更は自動適用禁止 → Owner レビュー
   - **Kernel 境界チェック**: 変更対象が Userland であることを自動判定（既存の Section 12 と連携）
   - **セマンティック検証**: 変更前後で既存ルールとの矛盾がないか Claude に再チェックさせる（二重検証）
2. 設計書 Section 11 に上記を追記

**変更対象:** `.ai/DESIGN/ORGOS_INTELLIGENCE.md` Section 11
**工数:** 設計追記のみ（実装は T-INT-004 で実施）
**リスク:** 低（設計変更のみ。ただし過剰な検証はコスト増になるためバランスに注意）

---

### OIP-AUTO-003: FastMCP 3.0 の Provider パターンで OrgOS スキルを MCP 公開

**きっかけ:** FastMCP 3.0 beta が Provider/Transform パターンを導入（トピック6）

**現状の課題:** OrgOS のスキル（`.claude/skills/*.md`）は Claude Code のローカルファイルとしてのみ利用可能。他の AI クライアント（ChatGPT、Cursor 等）からは参照できない。

**具体的にやること:**
1. FastMCP 3.0 の `SkillsProvider` を使って、`.claude/skills/` のスキルファイルを MCP リソースとして公開できるか調査
2. 可能であれば、OrgOS のコーディング規約やパターンを MCP 経由で Cursor 等にも提供する PoC を作成
3. 調査結果を `.ai/RESOURCES/research/fastmcp-3-provider.md` に記録

**変更対象:** 調査結果ドキュメントのみ（PoC は別リポジトリ）
**工数:** 調査 + PoC で中規模
**リスク:** 低（調査段階。FastMCP 3.0 はまだ beta なので本番採用は時期尚早）

---

### OIP-AUTO-004: AI ツール偽装マルウェア対策チェックリストを security.md に追加

**きっかけ:** Moltbot セキュリティ事件 — 偽 VS Code 拡張でマルウェア配布（トピック7）

**現状の課題:** OrgOS の `security.md` は OWASP Top 10（Web アプリの脆弱性）を中心にカバーしているが、**AI 開発ツール自体のサプライチェーンリスク**（偽拡張、悪意ある MCP サーバー、プロンプトインジェクション経由の情報漏洩）への対策がない。

**具体的にやること:**
`security.md` に「AI ツールのサプライチェーンセキュリティ」セクションを追加:
- **VS Code 拡張の検証**: インストール前に publisher の verified マーク、ダウンロード数、ソースコード公開を確認
- **MCP サーバーの検証**: 接続先 MCP サーバーの認証方式、ソースコード公開、known-good リストの管理
- **プロンプトインジェクション対策**: 外部データ（メール、URL）を AI に渡す際のサニタイゼーションルール
- **定期監査**: 使用中の AI 拡張・MCP サーバーの一覧を `.ai/RESOURCES/` に記録し、月次で見直す

**変更対象:** `.claude/rules/security.md`（セクション追加、約30行）
**工数:** 小（ドキュメント追加のみ）
**リスク:** なし（防御的なドキュメント追加）

---

## 収集メタデータ

| 項目 | 値 |
|------|-----|
| 収集日 | 2026-01-30 |
| 対象期間 | 2026-01-23〜01-30 |
| 検索クエリ数 | 16 |
| 候補トピック数 | 15 |
| 採用トピック数 | 10 |
| OIP 候補数 | 4 |
| 失敗ソース | なし |
