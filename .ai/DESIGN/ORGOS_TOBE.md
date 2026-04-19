# OrgOS ToBe 設計: 「作業者」から「参謀長」へ

> 作成: 2026-04-18 / Manager（Claude Opus 4.7）
> 背景: Owner フィードバック「OrgOS は作業者で止まっている。気が利かない外注の人」
> 目的: ChatGPT Pro を含む第三者レビューに耐える、OrgOS の本質的 ToBe 像を定義する

---

## 0. この文書について

この文書は **OrgOS を次のステージに進めるためのアーキテクチャ転換案** です。
既存の「アップデート余地の網羅的修正（T-OS-110〜144, 20 タスク）」は **対症療法** に過ぎず、根本の設計思想を見直さない限り Owner の実体験は改善しないという診断に基づきます。

読者想定: Owner (Yu Yokotani) + 外部レビュワー (ChatGPT Pro 等)
評価してほしい観点は「8. 自覚している盲点」セクションに集約しています。

---

## 1. 現在地の診断: なぜ OrgOS は「気が利かない外注」に見えるのか

### 1.1 Owner の実体験から見える 3 つの症状

**症状 A: 短絡的な負担転嫁**
- CLI で検索できる情報を「GUI 手順」として Owner に依頼する
- 過去に連携した認証情報（id/pw、project_ref）を毎回聞き直す
- 自分の手元で使えるツールを忘れている（次回セッションで再確認が必要）

**症状 B: プロジェクト全体像の欠如**
- 目の前のタスクだけを解く。周辺タスクとの文脈共有がない
- 並列タスクで文脈が飛ぶ（片方の成果を片方が知らない）
- 単発依頼を受けると、進行中のプロジェクト文脈を完全に無視することがある

**症状 C: 情報補完の姿勢が受動的**
- 不明な点を「推測」で埋める（あとで食い違う）
- Owner をパートナーとして巻き込まず、一人で完結させようとする
- 巻き込むときも「作業を丸投げする」形になる（認知負荷の最適化がない）

### 1.2 症状の根本原因: アーキテクチャの 4 つの空白

既存の OrgOS は以下の層を持つ:
- **台帳層**: PROJECT / TASKS / DECISIONS / STATUS
- **ルール層**: .claude/rules/*
- **エージェント層**: .claude/agents/*
- **コマンド層**: .claude/commands/*

しかし **以下の 4 つが構造的に存在しない**:

| 欠落層 | 現状 | 症状への影響 |
|--------|------|-------------|
| **User Context Layer** | Claude Code の memory に部分的に依存。OrgOS として構造化されていない | 症状 A（二度聞き、忘却） |
| **Capability Layer** | `which codex` を毎回実行。使える手段が台帳化されていない | 症状 A（CLI を知らず GUI を依頼） |
| **Coherence Layer** | タスク単位で独立。プロジェクト全体像との紐付けが応答時に行われない | 症状 B（全体像の欠如） |
| **Inquiry Layer** | ヒアリングは場当たり的。履歴・構造化・優先順位なし | 症状 C（推測で補完、巻き込み下手） |

### 1.3 「自律駆動」設計の副作用

T-OS-070 で「OrgOS 主導、人間は最小介入」に方針転換しました。これは正しい方向ですが、**実装されたのは「Owner に聞かない」だけ** で、「Owner の資産を最大活用する」「Owner を適切に巻き込む」という対の思想が未実装です。

結果、次のような歪みが生じています:

```
✅ 自律駆動 (実装済み): Owner に聞かず、Manager が判断する
❌ 自律駆動 (未実装): Owner の過去資産・認知状態を踏まえて判断する
❌ 自律駆動 (未実装): 巻き込むべき時は構造化して巻き込む
```

**自律 = 独断 ではない**。真の自律は「必要十分な情報を総動員して判断する」こと。その「情報」の中には Owner の過去発言・認証情報・好み・能力が含まれる。今の OrgOS はこれを **毎回ゼロから** 扱っている。

---

## 2. ToBe の北極星: Chief of Staff モデル

### 2.1 比喩の定義

Manager は「外注作業者」ではなく「**Chief of Staff（参謀長・首席補佐官）**」として振る舞う。

Chief of Staff の特徴:
- 上司（Owner）の意図・時間・認知負荷を最優先で管理する
- プロジェクト全体像を常に把握している
- 部下（Codex worker 等）を適切に指揮する
- 上司の判断を仰ぐ時は、論点を絞り、選択肢を整理する
- 過去の決定・会話を全て記憶し、二度手間を許さない
- 外部のリソース（人脈・ツール・情報源）を能動的に活用する

### 2.2 Owner が感じるべき 5 つの体験

ToBe の OrgOS を使った Owner は、以下を体験するはず:

| # | 体験 | 例 |
|---|------|-----|
| 1 | **「あ、それ前に話したな、覚えててくれた」** | 認証情報、好み、過去判断の再利用 |
| 2 | **「自分がやらないといけないこと、最小限だな」** | CLI で代行、自動化、必要最小のヒアリング |
| 3 | **「プロジェクト全体を分かってる人と話している」** | 単発依頼でも全体文脈を参照した応答 |
| 4 | **「聞き方が上手い」** | 構造化された 1-3 個の質問、推測でなく事実ベース |
| 5 | **「進捗と決定が透明で追える」** | 何を誰がいつ決めたか・何故かが常に辿れる |

### 2.3 現在の自律駆動原則との整合・更新

既存の `.claude/rules/ai-driven-development.md` の原則は維持しつつ、以下を追加する:

**追加原則**:
> **自律 ≠ 独断。自律とは「Owner の過去資産を最大活用した判断」である。**
> Manager は Owner への質問を最小化するのと同時に、Owner の時間・認知負荷・過去会話を最大限尊重する。

---

## 3. 5 つの柱 — MAOPA

ToBe OrgOS は以下 5 本の柱で成立する:

### 3.1 Memory（忘れない）

Owner の資産・会話・好みを構造化して永続保持する。
- 認証情報、アクセス権、使える CLI、過去の質疑応答、好みの応答スタイル
- セッションを超えて参照可能
- Claude Code の memory より **プロジェクト横断で構造化**

### 3.2 Awareness（全体を見る）

単発依頼であっても、応答前に必ず以下をバインドする:
- 現在のプロジェクトフェーズ (KICKOFF/REQUIREMENTS/DESIGN/...)
- 進行中のタスクと依頼との関係
- 長期ゴール (GOALS.yaml) との整合

「今この依頼は、プロジェクトのどこに位置する何か」を **応答に明示**する。

### 3.3 Optionality（手段の選択肢を持つ）

Owner に依頼を投げる前に、使える手段を総当たりする:
- 登録済み CLI → API → 既存スクリプト → MCP → 過去の類似パターン
- この探索は **強制ステップ** として実装（ルール文面だけでは機能しない）

### 3.4 Partnership（巻き込む）

Owner を「作業を依頼する対象」ではなく「戦略判断のパートナー」として扱う:
- 巻き込むべき判断（戦略・予算・破壊的操作）と、Manager が決める判断を明確分離
- 巻き込む際は **構造化された 1-3 問** のみ
- 質問には必ず **なぜ聞くか・判断材料・Manager の推奨** を添える

### 3.5 Accountability（責任を負う）

Manager の全判断・全実行に追跡可能な記録を残す:
- 誰が (Manager/Codex/Owner) いつ 何を なぜ 決めたか
- 失敗・誤判断を検出・記録・学習（Cross-project 共有）
- 「同じ失敗を二度しない」を構造で担保

---

## 4. アーキテクチャ変更: 4 レイヤーの追加

既存アーキテクチャに **4 つの新レイヤー** を追加する。

```
┌─────────────────────────────────────────────────┐
│  Owner                                          │
└─────────────────────────────────────────────────┘
            ↕ (依頼 / 質問)
┌─────────────────────────────────────────────────┐
│  【新】Inquiry Layer         (Partnership)     │
│    - 構造化質問の生成                           │
│    - 質問履歴 (past_qa) の参照                  │
│    - 推奨付き選択肢                             │
└─────────────────────────────────────────────────┘
            ↕
┌─────────────────────────────────────────────────┐
│  【新】Coherence Layer       (Awareness)       │
│    - プロジェクト全体像のバインド               │
│    - フェーズ・ゴール・並列タスクの文脈統合    │
└─────────────────────────────────────────────────┘
            ↕
┌─────────────────────────────────────────────────┐
│  【新】Capability Layer      (Optionality)     │
│    - CAPABILITIES.yaml: 使える手段の台帳        │
│    - 毎 Tick 自動検出 + 登録                    │
│    - 依頼 → 手段選定のマッチング                │
└─────────────────────────────────────────────────┘
            ↕
┌─────────────────────────────────────────────────┐
│  【新】User Context Layer    (Memory)          │
│    - USER_PROFILE.yaml: Owner 永続プロファイル │
│    - past_qa: 質疑応答の履歴                    │
│    - preferences: 好みの応答スタイル            │
└─────────────────────────────────────────────────┘
            ↕
┌─────────────────────────────────────────────────┐
│  既存: 台帳 / ルール / エージェント / コマンド │
└─────────────────────────────────────────────────┘
            ↕
┌─────────────────────────────────────────────────┐
│  【既存+強化】Accountability Layer             │
│    - AUDIT log / METRICS / DECISIONS            │
│    - Cross-project learning                     │
└─────────────────────────────────────────────────┘
```

### 4.1 User Context Layer — `USER_PROFILE.yaml`

```yaml
owner:
  name: "Yu Yokotani"
  literacy_level: "intermediate"
  response_preference: "terse_japanese"
  timezone: "Asia/Tokyo"

  # 確認済みの資産（セッション超えて記憶）
  confirmed_resources:
    cli:
      - name: codex
        path: /opt/homebrew/bin/codex
        verified_at: 2026-04-18
      - name: gh
        verified_at: 2026-04-18
    credentials:
      - service: supabase
        scope: project_abc123
        shared_at: 2026-03-15
    mcp_servers:
      - name: filesystem

  # 過去の質疑応答
  past_qa:
    - q: "Supabase の project_ref は？"
      a: "abc123"
      asked_at: 2026-03-15
      context: "初期セットアップ時"

  # 好み
  preferences:
    - "CLI > GUI（手順依頼は CLI 優先）"
    - "セッション終了提案は 95% 以上のみ"
    - "選択肢提示より自律実行+報告"

  # 過去の重要判断
  major_decisions_ref: [".ai/DECISIONS.md#D-xxx", ...]
```

**Manager の動作変更**:
- 依頼受付時に **必ず** USER_PROFILE を読む
- 質問する前に past_qa を検索
- 回答を必ず past_qa に追記

### 4.2 Capability Layer — `CAPABILITIES.yaml`

```yaml
capabilities:
  # 自動検出された CLI
  cli:
    - tool: codex
      detected_at: 2026-04-18
      usable: true
    - tool: gh
      scope: ["repo", "workflow"]
    - tool: supabase
    - tool: stripe
    - tool: vercel
    - tool: aws

  # MCP サーバー
  mcp:
    - server: filesystem
      status: active

  # 内部リソース
  internal:
    skills: [research-skill, tdd-workflow, ...]
    scripts: [scripts/codex-wrapper.sh, ...]

  # 過去に使えた操作パターン（再利用可能）
  reusable_patterns:
    - pattern: "Supabase API キー取得"
      method: "supabase projects api-keys --project-ref <ref>"
      last_used: 2026-03-15
```

**Manager の動作変更**:
- 毎 Tick で `capabilities-scan.sh` を実行して更新
- Owner に手順依頼する前に **必ず** CAPABILITIES を探索
- GUI 手順を依頼する前に CLI 代替を検証

### 4.3 Coherence Layer — Project Context Binder

**実装**: `.claude/rules/coherence-binding.md`（新規）

依頼受付時の強制ステップ:
1. 現在のフェーズを CONTROL.yaml から取得
2. 現在のアクティブタスクを TASKS.yaml から抽出
3. 長期ゴールを GOALS.yaml から抽出
4. 依頼内容とこれらの関係を分析
5. **応答の冒頭に「この依頼の位置づけ」を明示**

### 4.4 Inquiry Layer — Active Inquiry Framework

**実装**: `.claude/rules/active-inquiry.md`（新規）

ヒアリング判定フロー:
```
依頼受付
  ↓
[1] CAPABILITIES.yaml に手段があるか？
  → YES: 使う（質問しない）
  → NO: 次へ
  ↓
[2] USER_PROFILE.past_qa に答えがあるか？
  → YES: 参照（質問しない）
  → NO: 次へ
  ↓
[3] 推測で進めても後戻りできるか？
  → YES: 推測して進め、結果を報告
  → NO: 次へ（構造化質問へ）
  ↓
[4] 構造化質問を生成
  - 最大 3 問
  - 各質問に: 「なぜ聞くか」「判断材料」「Manager の推奨」
  - 開かれた質問（選択肢の羅列ではない）
  ↓
[5] 回答を past_qa に記録
```

---

## 5. 振る舞いの Before/After — 4 シナリオ

### シナリオ 5.1: 認証情報の再利用

**AsIs**:
```
Owner: "DB 接続設定して"
Manager: "データベースの URL と認証情報を教えてください。"
Owner: (内心: また？前に話したのに)
```

**ToBe**:
```
Owner: "DB 接続設定して"
Manager: "USER_PROFILE に 2026-03-15 に共有された Supabase (project_abc123) の
         連携情報があります。これを使って設定します。
         別の DB の場合のみ教えてください。"
Manager: (supabase CLI で自動設定 → テスト接続 → 結果報告)
```

### シナリオ 5.2: 単発依頼の文脈バインド

**AsIs**:
```
Owner: "このログから error 抽出して"
Manager: (grep 実行して結果表示)
```

**ToBe**:
```
Owner: "このログから error 抽出して"
Manager: "【文脈】進行中の T-OS-121 (Codex リトライ実装) の debug ですね。

         error 件数: 3件
         - 2件: リトライロジックで解決可能なタイプ
         - 1件: 設定ミス（別タスク化を推奨）

         T-OS-121 の acceptance に「これらのエラー型を全て処理」を追加しますか？"
```

### シナリオ 5.3: 情報不足時のヒアリング

**AsIs**:
```
Owner: "Stripe の webhook 設定して"
Manager: "Stripe ダッシュボードで以下の手順を実行してください:
         1. Developers > Webhooks を開く
         2. Add endpoint をクリック
         3. URL を入力
         4. Events を選択
         5. Signing secret をコピーして教えてください"
Owner: (内心: 全部自分でやるじゃん)
```

**ToBe**:
```
Owner: "Stripe の webhook 設定して"
Manager: "【検討結果】
         - CAPABILITIES に stripe CLI あり → 大半を自動化可能
         - past_qa に過去の Stripe 設定なし → 1 点だけ確認が必要

         【確認】
         Q: Webhook で受けたいイベントは？
            理由: stripe CLI で listen コマンドを組み立てるのに必要
            判断材料: BRIEF.md から推測した候補:
              (a) payment_intent.* — 支払い完了/失敗 (このプロジェクトは EC なので推奨)
              (b) customer.* — 顧客の作成・更新
              (c) invoice.* — 請求書
            Manager 推奨: (a) payment_intent.*

         これだけ教えてもらえれば、残りは全て自動化します。"
```

### シナリオ 5.4: 並列タスクの文脈共有

**AsIs**:
```
(T-OS-120 と T-OS-121 が並列実行中)
T-OS-120 完了: メトリクス JSON 形式を .ai/METRICS/*.jsonl に定義
T-OS-121 実行中: Codex リトライ失敗を別の形式で記録しようとしている
→ 形式が揃わず、後で手戻り発生
```

**ToBe**:
```
並列タスク起動時に Coherence Layer が:
  - 各タスクの成果物 schema を CAPABILITIES.internal.contracts に登録
  - 依存するタスク（T-OS-121）は T-OS-120 の schema を参照
  - 応答冒頭に "T-OS-120 で定義された metrics.jsonl 形式に揃えます" と明示

結果: 形式の統一が自動で保証される
```

---

## 6. 移行ロードマップ

### Phase 1: Memory 基盤（1-2 日）
- `.ai/USER_PROFILE.yaml` 新設
- `.ai/CAPABILITIES.yaml` 新設 + 自動検出スクリプト
- Manager プロンプトに「依頼受付時に両ファイルを必ず読む」を追加
- past_qa への自動追記ロジック

**ここだけで症状 A（短絡的な負担転嫁）の 80% は解決する見込み**

### Phase 2: Awareness 基盤（1 日）
- `.claude/rules/coherence-binding.md` 新設
- 応答テンプレートに「文脈バインド」セクションを強制
- Manager プロンプト改訂

### Phase 3: Inquiry & Partnership 基盤（2-3 日）
- `.claude/rules/active-inquiry.md` 新設
- 質問生成時の 5 段階判定フロー実装
- 既存の「選択肢提示」パターン（38 箇所）を Active Inquiry に置換

### Phase 4: Accountability 強化（2-3 日）
- METRICS / AUDIT の実装（既存 T-OS-120, T-OS-124 を組み込み）
- Cross-project Learning（USER_PROFILE を `~/.orgos/shared/` で共有）

### Phase 5: 再学習ループ（継続）
- org-evolve に ToBe 評価を追加
- Owner との対話から USER_PROFILE を自動更新

---

## 7. 既存 20 タスク（T-OS-110〜144）の再配置

| 既存タスク | ToBe との関係 | 扱い |
|------------|--------------|------|
| T-OS-110 選択肢一掃 | Inquiry Layer の一部 | **Phase 3 に統合** |
| T-OS-111 Iron Law 全 agents | Accountability の前提 | **維持** (Phase 1 と並列) |
| T-OS-112 非推奨クリーン | 保守作業 | **維持** (優先度低) |
| T-OS-113 ad-hoc 検出 | Accountability | **Phase 4 に統合** |
| T-OS-120 メトリクス | Accountability | **Phase 4 に統合** |
| T-OS-121 Codex リトライ | 運用基盤 | **維持** (独立) |
| T-OS-122 台帳修復 | 運用基盤 | **維持** |
| T-OS-123 自己回帰テスト | Accountability | **維持** |
| T-OS-124 監査ログ | Accountability | **Phase 4 に統合** |
| T-OS-125 自動アーカイブ | 運用基盤 | **維持** |
| T-OS-130 Mermaid 図 | UX | **維持** (ToBe 後に) |
| T-OS-131 Dashboard schema | Coherence | **Phase 2 に統合** |
| T-OS-132 GLOSSARY | UX | **維持** |
| T-OS-133 STATUS/RUN_LOG | 保守 | **維持** |
| T-OS-134 Codex 抽象化 | 保守 | **維持** |
| T-OS-140〜144 B 系 | エコシステム | **Phase 5 へ後ろ倒し** |

### 新規タスク案（Phase 1-3）
- **T-OS-150**: USER_PROFILE.yaml 設計 + 初期化
- **T-OS-151**: CAPABILITIES.yaml + 自動検出スクリプト
- **T-OS-152**: Manager プロンプトに Memory/Coherence バインドを追加
- **T-OS-153**: coherence-binding.md ルール新設
- **T-OS-154**: active-inquiry.md ルール新設
- **T-OS-155**: 既存 38 箇所の選択肢提示を Active Inquiry に置換 (T-OS-110 を代替)

---

## 8. 自覚している盲点（ChatGPT Pro への問いかけ）

Manager として、この設計で **自分が十分に検討しきれていない** と自覚している点:

### 8.1 Memory の PII リスク
USER_PROFILE に認証情報・好みを保存することのセキュリティリスク:
- `.ai/` は Git 管理対象。誤って push する危険
- 暗号化・Keychain 連携が必要か
- **問い**: OS レベルの Secret Manager 統合と平文 YAML の中間解は？

### 8.2 Coherence のコスト
毎依頼で全体像をバインドすると、応答が冗長になる懸念:
- 短い依頼（「grep して」）にも文脈を付けるべきか
- Owner が「うるさい」と感じる閾値はどこか
- **問い**: 文脈バインドの粒度を動的に調整する設計は？

### 8.3 Active Inquiry の「構造化質問」の限界
1-3 問の構造化質問は理想だが:
- 依頼の性質によっては 5-10 問必要なケース
- その場合の分割戦略 (session を跨ぐ？)
- **問い**: 大規模な要件定義フェーズでの Active Inquiry 設計は？

### 8.4 Cross-project Learning の誤転移
USER_PROFILE / CAPABILITIES をプロジェクト間で共有すると:
- 前プロジェクトの誤った好みが引きずられる
- プロジェクト固有の制約が汚染される
- **問い**: 共有と隔離の境界設計は？

### 8.5 Chief of Staff メタファーの限界
参謀長モデルは「1 人の上司 × 1 人の参謀」前提:
- チーム開発で複数 Owner がいる場合の設計
- 競合する指示への対処
- **問い**: マルチ Owner / マルチプロジェクトでの Chief of Staff は成立するか？

### 8.6 ChatGPT Pro との役割分担
Owner は ChatGPT Pro も併用する前提:
- OrgOS の Manager と ChatGPT Pro のコラボ設計
- USER_PROFILE の共有経路
- **問い**: AI エージェント間のコンテキスト共有プロトコルは？

---

## 9. 結論と次のアクション

### この ToBe 設計の要点
OrgOS を「作業者」から「参謀長」に進化させるには、**機能追加ではなく 4 つの新レイヤー** (Memory / Coherence / Capability / Inquiry) の導入が必要。これは対症療法 (T-OS-110〜144) ではなく、アーキテクチャの転換。

### Owner の次の判断ポイント
1. この ToBe 方向性で合意するか
2. ChatGPT Pro のレビューを経てから着手するか、並行で進めるか
3. 既存 20 タスクとの再配置を承認するか（Phase 分け）

### Owner の承認後のアクション
- `.claude/agents/manager.md` を ToBe モードに書き換え
- Phase 1 タスク T-OS-150〜155 を TASKS.yaml に追加
- 既存 20 タスクの Phase 再配置を反映

---

## 参考

- 診断の元資料: [.ai/RESOURCES/SELF_REVIEW_2026-04-18.md](../RESOURCES/SELF_REVIEW_2026-04-18.md)
- 既存の自律駆動原則: [.claude/rules/ai-driven-development.md](../../.claude/rules/ai-driven-development.md)
- Owner タスク最小化: [.claude/rules/owner-task-minimization.md](../../.claude/rules/owner-task-minimization.md)
- 合理化防止: [.claude/rules/rationalization-prevention.md](../../.claude/rules/rationalization-prevention.md)
