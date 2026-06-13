# 第3 AI 向け prompt — OrgOS 理想形批評 (T-OS-403)

> 用途: Owner が本ファイル全文を ChatGPT / Gemini / Claude.ai (別チャット) / Grok 等にコピペして実行。
> 結果を `.ai/REVIEW/T-OS-400/external-ai-response.md` に貼り付け。
> 推奨: 「reasoning model」(o1 / o3 / Gemini Thinking 等) を使うこと。理由は思考量が必要なため。

---

## 以下、AI への prompt 本文 (ここから下を全文コピー)

---

あなたは、ソフトウェアアーキテクトかつ AI エージェント運用の専門家です。
ある人物 (以下「Owner」) が、Claude Code 上で動く「自律エージェント運営 OS (OrgOS)」を運用していますが、**「問題が発生するたびに暫定対応が積み重なり、本来の理想形に近づいていない」**と感じています。

私 (Owner) はこの状態を脱したく、3 つの視点で意見を集めています:
- ① OrgOS 内部の Manager (Claude) 自身
- ② 同 OrgOS の実装 worker (Codex CLI = GPT-5.5)
- ③ あなた (外部の第三者 AI、本 prompt の相手)

あなたには **first-principles から OrgOS のあるべき形を提案** してほしい。Manager と Codex の視点には縛られない、外部 reviewer としての率直な意見を求めます。

---

## 0. 出力指示

以下の Output Format に従って 5000〜10000 字の日本語で回答してください。
忖度や socially-safe な答えは不要。**辛口で構わない**。Owner は批判的 feedback を歓迎しています。

---

## 1. OrgOS とは (前提知識)

OrgOS は以下の特徴を持つ:

### 構造
- **位置**: Claude Code (Anthropic の CLI) の上で動く markdown + YAML + shell script の集合
- **役割分担**: Owner (人) / Manager (Claude が務める) / Codex (GPT-5.5 が務める実装 worker) / 各種 sub-agent
- **状態管理**: 複数の YAML / Markdown ファイル群 (`.ai/TASKS.yaml`, `.ai/GOALS.yaml`, `.ai/USER_PROFILE.yaml`, `.ai/CAPABILITIES.yaml`, `.ai/CONTROL.yaml`, `.ai/DECISIONS.md`, `.ai/DASHBOARD.md`, ...) を SSOT として手動 + 半自動で更新
- **ルール**: `.claude/rules/*.md` に 30 以上のルール。`Iron Law` (絶対遵守) と通常 rule の区別あり
- **強制**: `.claude/hooks/pretool_policy.py` という Python script が一部の rule を runtime で強制。大部分の rule は markdown 上の宣言のみ
- **フロー**: Request Intake Loop という 10 step の状態機械を全依頼に適用

### 設計思想
- 「Iron Law (例外なし) で OS 中核ファイルを保護」
- 「Codex は完了報告 (Handoff Packet) を schema 化して返す」
- 「全 task を `.ai/TASKS.yaml` に登録してから実行 (ad-hoc 禁止)」
- 「Manager は自律実行を優先し、Owner には本当に必要な情報のみ問う」

### 規模感
- `.claude/rules/` のファイル数: 30+
- `.ai/TASKS.yaml`: 52 task (queued + running)
- `.ai/TASKS_ARCHIVE.yaml`: done task 多数 (T-OS-001〜T-OS-382)
- `.ai/DECISIONS.md`: PLAN-UPDATE 22 件
- `scripts/`: 数十の shell / python script
- 全体行数: 数万行 (ルールとログとスクリプト)

---

## 2. 直近の事故 (背景)

### 事故 A: 並列セッション衝突 (2026-05-10)
Owner が 2 つの Claude Code セッションを並走 (チャットを分けて) 同じ git repo で別 task を回したところ:
- セッション A が `develop` ブランチに自動コミット (Codex 経由)
- セッション B が `main` ブランチに自動コミット
- 結果、`src/lib/ads/orchestrator/*` 配下 7 ファイルで add/add 衝突
- cherry-pick で部分回避するワークアラウンドが必要

### 事故 B: 意図しないブランチ切替 (2026-05-09)
- 9 プロセス並走中、git reflog に "意図しない `main` への checkout" 3 回記録
- main への誤コミット寸前で発見、`git branch -f` で手動復旧

### Manager / Owner の現在の対応
- 既に 2026-04 に「並列セッション禁止 rule」「pretool branch consistency check」「Codex worktree wrapper」「git flock」を 4 タスク (T-OS-360〜363) として実装し done にしていた
- それらが**事故を防げなかった**

### 今回 (2026-05-14) の Owner FB
今回も Owner FB を受けて、Manager は新規 9 task (T-OS-390〜399) を起案:
- Codex 自動 commit 禁止 / allowed_paths 衝突 pre-flight / main 直 commit 拒否 / worker フィールド / heartbeat / .ai/LOCKS / etc.

しかし Owner はこれを見て「**また暫定対応の積み増しだ。理想形を検討したい**」と発言。本 prompt はその応答として作られている。

---

## 3. あなたへの質問

以下に対し、**順番に**、**正直に**回答してください。

### Q1. patch-on-patch ループの根本原因
なぜ OrgOS は「事故 → ルール追加 → 事故 → ルール追加」を繰り返してしまうのか。
表層的説明 (「実装が不十分」「テストが足りない」) ではなく、設計思想レベルでの根本原因を 3〜5 個挙げてください。

### Q2. OrgOS の「OS」アナロジーは妥当か
OrgOS は自らを OS と呼んでいるが、実態は markdown + YAML + shell script の集合体である。
- 「OS」というアナロジーは妥当か?
- 別のアナロジー (例: framework / DSL / playbook / agent harness / 何か else) のほうが適切ではないか?
- アナロジーを変えると、設計選択がどう変わるか?

### Q3. 状態管理: 複数 YAML/MD vs 別解
現状、SSOT を名乗るファイルが 7+ 個あり、整合性は手動 + script で維持されている。
- これは持続可能か?
- もし別解を提案するなら、何か? (例: event sourcing, sqlite, structured log, 専用 DB, 何もしない=元に戻す)
- 各案のトレードオフ

### Q4. AI エージェントへの信頼境界
OrgOS では「Codex は commit してはいけない」を markdown rule で書いている。これが破られた可能性がある (事故 A の遠因)。
- AI エージェントに対し、policy (= ルール宣言) で行動を制約する手法はどこまで信頼できるか?
- 物理的サンドボックス (file system isolation, git hook で拒否, syscall filter) と policy の使い分けは?
- 「policy-as-code」(OPA / Cedar) のような中間解の評価

### Q5. 30+ ルールの帰結
ルール数が単調増加している (consolidation 機構なし)。
- これは健全か?
- ルール削減 / 統合をどう設計に組み込むか?
- 「ルールが多い OS」と「ルールが少ない OS」のどちらが望ましいか?
- 参考事例 (Linux kernel, AWS IAM, 法律体系, etc.) があれば挙げる

### Q6. Manager (LLM) の責務範囲
現状 Manager は: 意図解釈 + 状態 bind + リスク分類 + 判断 + 実行 + 検証 + ledger 更新 + 報告、を 1 LLM ターンで行う。
- これは LLM に適切な責務か?
- 分割する場合、どこで切るのが工学的に正しいか?
- 「LLM が忘れる / 飛ばす」を構造的に防ぐ手法は?

### Q7. Owner の認知負荷
現状 Owner は `CONTROL.yaml` の flag を直接編集することがある。`/org-tick` の意味を理解する必要がある。各種 phase 遷移を把握する必要がある。
- これは UX として妥当か?
- 「Intent を述べたら OS が plan を返す」抽象に再設計するなら、どう?
- 設計の見直しで Owner 負荷をどこまで下げられるか?

### Q8. もし白紙から作り直すなら
完全に白紙の状態で、Owner の真のニーズ (= 「複数 AI を協調させて自分の意図通りにソフトウェア開発したい」) を満たす最小システムを設計するとしたら、それは OrgOS とどう違うか?
- 構成要素 (5〜10 個)
- 各要素の責務
- 状態管理方式
- AI への制約方式
- 想定される失敗モードと対策

### Q9. 短期 / 中期 / 長期アクション提案
あなたの分析を踏まえ、Owner が次に取るべきアクションを優先順位で 10 件以内に絞って提案してください。
- 各アクションの目的
- 実装難度 (S/M/L)
- 期待効果
- リスク

### Q10. 「やめるべきこと」リスト
OrgOS が現状やっていることのうち、**止めるべきもの**を率直に挙げてください。継続を前提とせず、ゼロベースで。

---

## 4. Output Format

```markdown
# OrgOS 理想形批評 — 第3 AI 視点

## 自己紹介
私は <model name>。<日付> 時点の知識を持つ。本回答は OrgOS の外部 reviewer の立場で書く。

## Q1. patch-on-patch の根本原因
...

## Q2. OS アナロジーの妥当性
...

(以下 Q3〜Q10 同様)

## Summary
3〜5 文で全体結論
```

---

## 5. 重要な依頼

- **Manager (Claude) の視点ドキュメントは読んでいない前提で書いてください**。同じ結論になったらそれは収束のサインとして価値があります
- 「総論賛成」のような無難な回答は不要。**Owner は辛口を歓迎**しています
- 不明点があれば「ここは情報不足で判断できない」と明記してください。創作はしないこと
- 最後の Summary では「次の一手」を 1 つだけ太字で示してください

---

(prompt 本文ここまで。Owner はここから上を AI に投げる)
