# ChatGPT Pro レビュー依頼プロンプト

> このファイル全体を ChatGPT Pro にそのまま貼り付けてください。
> 下の「=== PROMPT START ===」から「=== PROMPT END ===」までが本文です。

---

=== PROMPT START ===

# 役割設定

あなたはシニア AI アーキテクト 兼 ナレッジワーカー向け OS の設計エキスパートです。
以下の「OrgOS」という AI エージェント駆動型プロジェクト管理 OS の ToBe 設計案を、**厳格かつ建設的に**レビューしてください。

現場の Manager (Claude Opus 4.7) が書いた設計案を持ち込んでいます。Manager は自分の限界を自覚しており、あなたの視点で「見落とし」「別アプローチ」「設計原則の欠落」を指摘してほしいと望んでいます。忖度不要。むしろ Manager が気づいていない本質的弱点を引き出してほしい。

---

# 依頼の要約

OrgOS は「Owner の代わりに AI エージェント群がプロジェクトを推進する OS」として開発中。
Manager (Claude Code 上の主制御エージェント) + 複数の subagent (planner, architect, reviewer, etc.) + Codex CLI (実装担当) の構成。

しかし Owner から **「OrgOS は作業者であって Manager ではない。気が利かない外注の人のよう」** という本質的フィードバックを受けた。

この問題の根本解決のため、Manager 自身がアーキテクチャ転換案 (ToBe 設計) を書いた。
それを以下に提示するので、以下 5 観点でレビューしてほしい:

1. **診断の妥当性** — 根本原因の特定は正しいか
2. **ToBe 方向性の妥当性** — 「Chief of Staff モデル」「4 新レイヤー」は解として適切か
3. **設計の穴** — Manager が盲点として挙げた 6 項目への回答 + 追加の盲点
4. **実装順序** — 5 Phase ロードマップは現実的か
5. **別アプローチ** — この問題により優れた設計アプローチがあるか

---

# Part 1: OrgOS の背景

## アーキテクチャ概要

- **Manager エージェント** (Claude Code 上で動作): 中央制御。計画・調整・台帳管理・サブエージェント起動
- **サブエージェント** (Task ツール経由): org-planner, org-architect, org-reviewer, codex-implementer, org-scribe 等 15+ 種
- **Codex CLI** (/opt/homebrew/bin/codex): 実装担当のサブプロセス。Manager が `codex exec` で起動
- **台帳層** (.ai/ 配下の YAML/Markdown):
  - `TASKS.yaml`: タスク DAG (DAG = Directed Acyclic Graph)
  - `DECISIONS.md`: 意思決定ログ
  - `DASHBOARD.md`: Owner 向けステータス
  - `CONTROL.yaml`: 設定・フラグ
  - `GOALS.yaml`: Vision → Milestone → Project → Task の 4 階層
- **ルール層** (.claude/rules/*.md): セッション管理、自律駆動原則、計画同期、等
- **スキル層** (.claude/skills/*.md): コーディング規約、TDD、セキュリティ、等
- **コマンド層** (.claude/commands/*.md): /org-start, /org-tick, /org-evolve, /org-dashboard 等

## 設計の特徴

- **自律駆動原則**: Manager が技術判断を主導。Owner への質問は最小化
- **Iron Law**: 例外なしのルール (例: 全作業を TASKS.yaml に登録してから実行)
- **Verification Loops**: ステージ遷移時に eval 実行
- **org-evolve**: OrgOS 自身を自動改善するループ
- **マルチプロジェクト対応**: /org-dashboard で複数プロジェクトを横断管理

## 現時点の成熟度

Manager 自身の診断によると、OrgOS のスコアは **76/100** (4 観点の平均)。
- 自律駆動度 70 / エコシステム接続 40 / 運用インフラ 55 / UX 76

---

# Part 2: Owner の実体験から見える問題

Owner は以下の症状を訴えている:

**症状 A: 短絡的な負担転嫁**
- CLI で検索できる情報を「GUI 手順」として Owner に依頼する
- 過去に連携した認証情報 (id/pw, project_ref) を毎回聞き直す
- 自分の手元で使える CLI を忘れている (次セッションで再確認が必要)

**症状 B: プロジェクト全体像の欠如**
- 目の前のタスクだけを解く。周辺タスクとの文脈共有がない
- 並列タスクで文脈が飛ぶ (片方の成果を片方が知らない)
- 単発依頼を受けると、進行中のプロジェクト文脈を完全に無視することがある

**症状 C: 情報補完の姿勢が受動的**
- 不明点を「推測」で埋める (あとで食い違う)
- Owner をパートナーとして巻き込まず、一人で完結させようとする
- 巻き込むときも「作業を丸投げする」形になる (Owner の認知負荷の最適化がない)

Owner 原文引用:
> 「ユーザーによって、もっと負担がかからない方法があるのに、短絡的に負担がかかるやり方を提示したり。過去にid,pwを連携したのに、メモしていないから毎回聞いてくる。自分ができる操作を忘れたり、そもそもそれを振り返ってない感じ」
>
> 「目の前のタスクをやることだけを考えていて、プロジェクトの全体像を管理できていないから並列して仕事する時とか、単発のタスクを頼んだ時に全然文脈に沿っていないとか」
>
> 「必要な情報は適当に補うんじゃなくてクライアントである私にヒアリングしながら巻き込みつつちゃんとプロジェクトを推進するようなマネージャーになってほしい」

---

# Part 3: Manager の ToBe 設計提案

## 3.1 診断: 根本原因 = アーキテクチャの 4 つの空白

既存 OrgOS は以下層を持つ: 台帳層、ルール層、エージェント層、コマンド層。
しかし以下 4 つが構造的に欠落:

| 欠落層 | 現状 | 症状への影響 |
|--------|------|-------------|
| User Context Layer | Claude Code の memory に部分依存。構造化なし | 症状 A |
| Capability Layer | `which codex` を毎回実行。手段が台帳化されていない | 症状 A |
| Coherence Layer | タスク単位で独立。全体像との紐付けが応答時に発生しない | 症状 B |
| Inquiry Layer | ヒアリングが場当たり的。履歴・構造化なし | 症状 C |

## 3.2 「自律駆動」の副作用分析

T-OS-070 で「OrgOS 主導、人間最小介入」に方針転換した際、**「Owner に聞かない」だけが実装され、「Owner の資産を最大活用する」「適切に巻き込む」という対の思想が未実装** だった。

結果:
- 自律 = 独断 に歪んだ
- Owner の過去会話・認証情報・好みを毎回ゼロから扱う
- 巻き込むべき時も「作業丸投げ」か「独断実行」の二択しかない

## 3.3 ToBe の北極星: Chief of Staff モデル

Manager の立ち位置を「外注作業者」から「**Chief of Staff (参謀長・首席補佐官)**」に変更。

参謀長の特徴:
- 上司 (Owner) の意図・時間・認知負荷を最優先で管理する
- プロジェクト全体像を常に把握
- 部下 (Codex worker 等) を指揮する
- 上司判断を仰ぐ時は論点を絞り、選択肢を整理
- 過去の決定・会話を全て記憶し、二度手間を許さない

## 3.4 Owner が感じるべき 5 体験

| # | 体験 |
|---|------|
| 1 | 「あ、それ前に話したな、覚えててくれた」(認証・好み・過去判断の再利用) |
| 2 | 「自分がやらないといけないこと、最小限だな」(CLI 代行、必要最小ヒアリング) |
| 3 | 「プロジェクト全体を分かってる人と話している」(単発依頼でも全体文脈を参照) |
| 4 | 「聞き方が上手い」(構造化 1-3 問、推測でなく事実ベース) |
| 5 | 「進捗と決定が透明で追える」(何を誰がいつ決めたか・何故かが辿れる) |

## 3.5 原則の更新

既存自律駆動原則に以下を追加:
> **自律 ≠ 独断。自律とは「Owner の過去資産を最大活用した判断」である。**
> Manager は Owner への質問を最小化するのと同時に、Owner の時間・認知負荷・過去会話を最大限尊重する。

## 3.6 5 本柱 MAOPA

- **Memory** (忘れない): 資産・会話・好みの構造化永続保持
- **Awareness** (全体を見る): 単発依頼でも全体文脈をバインド
- **Optionality** (手段を持つ): 強制探索。CLI/API/MCP/既存スクリプトを総当たり
- **Partnership** (巻き込む): 推奨+判断材料+なぜ聞くか、を添えた構造化 1-3 問
- **Accountability** (責任): 誰がいつ何を何故決めたかの追跡可能な記録

## 3.7 アーキテクチャ変更: 4 新レイヤー追加

### Layer 1: User Context Layer — `USER_PROFILE.yaml`
```yaml
owner:
  literacy_level: "intermediate"
  response_preference: "terse_japanese"
  confirmed_resources:
    cli:
      - {name: codex, path: /opt/homebrew/bin/codex, verified_at: 2026-04-18}
      - {name: gh, scope: [repo, workflow]}
      - {name: supabase, verified_at: 2026-04-18}
    credentials:
      - {service: supabase, scope: project_abc123, shared_at: 2026-03-15}
    mcp_servers:
      - {name: filesystem, status: active}
  past_qa:
    - {q: "Supabase の project_ref は？", a: "abc123", asked_at: 2026-03-15}
  preferences:
    - "CLI > GUI"
    - "セッション終了提案は 95% 以上のみ"
    - "選択肢提示より自律実行+報告"
```

Manager は依頼受付時に **必ず** USER_PROFILE を読む。質問前に past_qa を検索。回答を追記。

### Layer 2: Capability Layer — `CAPABILITIES.yaml`
```yaml
capabilities:
  cli: [codex, gh, supabase, stripe, vercel, aws]
  mcp: [filesystem]
  internal:
    skills: [research-skill, tdd-workflow]
    scripts: [scripts/codex-wrapper.sh]
  reusable_patterns:
    - {pattern: "Supabase API キー取得", method: "supabase projects api-keys --project-ref <ref>"}
```

毎 Tick で自動検出。Owner に手順依頼する前に **必ず** 探索。

### Layer 3: Coherence Layer — Project Context Binder
依頼受付時の強制ステップ:
1. CONTROL.yaml から現在フェーズ取得
2. TASKS.yaml からアクティブタスク抽出
3. GOALS.yaml から長期ゴール抽出
4. 依頼内容との関係を分析
5. **応答冒頭に「この依頼の位置づけ」を明示**

### Layer 4: Inquiry Layer — Active Inquiry Framework
ヒアリング判定フロー:
```
[1] CAPABILITIES に手段あり？ → YES: 使う(質問しない) / NO: 次へ
[2] past_qa に答えあり？ → YES: 参照(質問しない) / NO: 次へ
[3] 推測で進めても後戻り可能？ → YES: 推測実行+報告 / NO: 次へ
[4] 構造化質問を生成 (最大 3 問)
    各質問に: 「なぜ聞くか」「判断材料」「Manager の推奨」
    開かれた質問(選択肢羅列でない)
[5] 回答を past_qa に記録
```

## 3.8 振る舞いの Before/After

### シナリオ: 認証情報の再利用

**AsIs**:
```
Owner: "DB 接続設定して"
Manager: "DB URL と認証情報を教えてください"
Owner: (内心: 前に話したのに)
```

**ToBe**:
```
Owner: "DB 接続設定して"
Manager: "USER_PROFILE に 2026-03-15 共有の Supabase (project_abc123) あり。
         これを使います。別 DB の場合のみ指示ください。"
Manager: (supabase CLI で自動設定 → テスト接続 → 報告)
```

### シナリオ: 単発依頼の文脈バインド

**AsIs**:
```
Owner: "このログから error 抽出して"
Manager: (grep 実行、結果表示のみ)
```

**ToBe**:
```
Owner: "このログから error 抽出して"
Manager: "【文脈】進行中 T-OS-121 (Codex リトライ実装) の debug ですね。
         error 3件。2件はリトライで解決可能、1件は設定ミス。
         T-OS-121 の acceptance に追加しますか？"
```

### シナリオ: 情報不足時のヒアリング

**AsIs**:
```
Owner: "Stripe の webhook 設定して"
Manager: "Stripe ダッシュボードで以下実行してください: 1..2..3..4..5 (5手順)"
Owner: (内心: 全部自分でやるじゃん)
```

**ToBe**:
```
Owner: "Stripe の webhook 設定して"
Manager: "【検討結果】CAPABILITIES に stripe CLI あり → 大半自動化可能。
         past_qa に過去 Stripe 設定なし → 1 点だけ確認必要。

         【確認】Q: Webhook で受けたいイベントは？
           理由: stripe listen コマンド組み立てに必要
           判断材料: BRIEF.md から推測候補:
             (a) payment_intent.* — EC プロジェクトなので推奨
             (b) customer.*
             (c) invoice.*
           Manager 推奨: (a)

         これだけ教えてもらえれば、残りは自動化します。"
```

## 3.9 移行ロードマップ (5 Phase)

| Phase | 内容 | 工数 | 解決する症状 |
|-------|------|------|-------------|
| 1 | Memory 基盤 (USER_PROFILE + CAPABILITIES + past_qa) | 1-2 日 | 症状 A の 80% |
| 2 | Awareness 基盤 (coherence-binding.md) | 1 日 | 症状 B |
| 3 | Inquiry & Partnership 基盤 (active-inquiry.md, 既存 38 箇所の選択肢提示を置換) | 2-3 日 | 症状 C |
| 4 | Accountability 強化 (METRICS, AUDIT, Cross-project) | 2-3 日 | 長期品質保証 |
| 5 | 再学習ループ (org-evolve に ToBe 評価統合) | 継続 | 自己進化 |

## 3.10 既存 20 タスク (T-OS-110〜144) との整合

大半は ToBe の各 Phase に統合可能。
- T-OS-110 (選択肢 38 箇所一掃) → Phase 3 の一部
- T-OS-111 (Iron Law 全 agents) → Phase 1 と並列実行可能
- T-OS-120 (メトリクス) → Phase 4 に統合
- T-OS-140〜144 (エコシステム接続) → Phase 5 へ後ろ倒し

## 3.11 Manager が自覚している盲点 (レビューしてほしい)

### 盲点 1: Memory の PII リスク
USER_PROFILE に認証情報・好みを保存することのセキュリティリスク。
`.ai/` は Git 管理対象で誤って push する危険。OS レベル Secret Manager 統合と平文 YAML の中間解は？

### 盲点 2: Coherence のコスト
毎依頼で全体像をバインドすると応答が冗長になる懸念。
短い依頼(「grep して」)にも文脈を付けるべきか。うるさいと感じる閾値は？

### 盲点 3: Active Inquiry の構造化質問の限界
1-3 問は理想だが、5-10 問必要なケースがある。分割戦略(session 跨ぎ)は？
大規模要件定義フェーズでの Active Inquiry 設計は？

### 盲点 4: Cross-project Learning の誤転移
USER_PROFILE/CAPABILITIES をプロジェクト間で共有すると、前プロジェクトの誤った好みが引きずられる。共有と隔離の境界設計は？

### 盲点 5: Chief of Staff メタファーの限界
参謀長モデルは 1 対 1 前提。マルチ Owner / マルチプロジェクトで成立するか？

### 盲点 6: ChatGPT Pro との役割分担
Owner は ChatGPT Pro も併用する前提。OrgOS Manager と Pro のコラボ設計は？ USER_PROFILE の共有経路は？

---

# Part 4: レビュー依頼観点 (明示)

以下 **5 観点** で厳格にレビューしてください:

### 観点 1: 診断の妥当性
- Owner の 3 症状の根本原因として「4 空白層」は正しいか
- 他の根本原因 (例えば認知科学的な設計ミス、プロンプトエンジニアリングの問題等) を見落としていないか

### 観点 2: ToBe 方向性 (Chief of Staff + MAOPA) の妥当性
- Chief of Staff メタファーは適切か、別のメタファーの方が設計を導きやすいか
- MAOPA (Memory/Awareness/Optionality/Partnership/Accountability) の粒度・網羅性は適切か
- 足りない柱はあるか

### 観点 3: 設計の穴
- 4 新レイヤー (User Context / Capability / Coherence / Inquiry) の具体化は十分か
- Manager が挙げた 6 盲点への回答
- Manager が自覚できていない盲点があれば指摘

### 観点 4: 実装順序 (5 Phase) の現実性
- Phase 1 (1-2 日) で症状 A の 80% 解決という見積りは妥当か
- Phase の順序・粒度は最適か
- 並列化・前倒しの余地は

### 観点 5: 別アプローチの可能性
- この設計より優れたアプローチがあるか
- 例えば RAG ベースのコンテキスト管理、外部 Knowledge Graph、etc.
- 近年の AI エージェント研究 (2025-2026) で参照すべき論文・フレームワーク

---

# Part 5: 期待する出力形式

以下構造で回答してください:

## 総合判定
- ◎ (優秀) / ○ (妥当) / △ (要修正) / × (根本再考)
- その理由を 3 行以内で

## 観点別分析
各観点 (1-5) について:
- 判定 (◎/○/△/×)
- 具体的な指摘 (箇条書き 3-5 個)
- 改善提案 (具体的な代替案や追加設計)

## Manager が自覚していない盲点
Manager が挙げた 6 盲点以外で、あなたが気づいた本質的な盲点を 2-3 個。

## 代替アプローチの提示
Chief of Staff / MAOPA とは異なる、より優れた可能性のある設計アプローチ。
- アプローチ名
- コア思想
- 本提案との違い
- 採用すべき場合の判断基準

## 優先度付き推奨アクション
Owner が次に取るべきアクションを優先度付きで 3-5 個:
- [P0] 今週中
- [P1] 2 週間以内
- [P2] 1 ヶ月以内

## 参照文献・フレームワーク
近年の AI エージェント / ナレッジワーカー向け OS 設計の参考になる文献・フレームワークを 3-5 個。

---

# 補足: レビュワーへの期待

Manager (Claude Opus 4.7) は自分の限界を自覚しています。
あなた (ChatGPT Pro) が持つ以下の強みを活かしてください:
- 広範な AI エージェント研究の知識
- ナレッジワーカー向け OS (Notion, Linear, Obsidian 等) の設計原則
- 組織論・マネジメント論の知見
- 認知科学・ヒューマン・コンピュータ・インタラクション (HCI)

忖度不要。「この設計は根本的に間違っている」という結論も歓迎します。
Manager と Owner は、あなたの指摘を真剣に検討します。

=== PROMPT END ===
