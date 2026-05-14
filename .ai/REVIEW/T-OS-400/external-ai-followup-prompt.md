# GPT-5.5 Pro follow-up prompt — 実装具体化 (T-OS-405)

> 用途: Owner が本ファイル全文を、同じ GPT-5.5 Pro チャットの**続き**として投入 (新規チャットではなく、前回の回答が context に残っている状態を推奨)。
> 新規チャットの場合は冒頭の「前回回答の要旨」を読ませてから本文へ。
> 結果を `.ai/REVIEW/T-OS-400/external-ai-followup-response.md` に保存。

---

## 以下、AI への follow-up prompt 本文 (ここから下を全文コピー)

---

前回の OrgOS 理想形批評をありがとう。方向性 (capability boundary / per-task worktree / single integrator commit gate / SQLite + event log / Manager の dispatcher 化 / Owner Plan Contract UX / Iron Law を 5-7 個に絞る) は Owner も Manager (Claude) も筋がいいと判断した。両者で独立に書いた批評がほぼ同じ結論に収束したのは収束のサインとして受け取った。

ただしここから先、**実装に落とす段階で別の難所**がある。あなた (GPT-5.5 Pro) に追加で詰めてほしい論点が 7 つある。前回と同じく辛口・具体的に、忖度なしで頼む。

---

## 前提の補足 (前回 prompt から追加した情報)

- 基盤は **Claude Code** という Anthropic の CLI 上で動く。独立した daemon プロセスは原則作れない (Owner がチャット session を開いている間だけ Manager が live)
- Manager = Claude Opus 4.7 (1M context)、Codex = GPT-5.5 Pro/High という構成
- Claude Code は subagent (Task tool 経由の sub-LLM 呼び出し)、hooks (pretool / posttool / sessionstart)、bash 実行を提供する。**それ以外の primitive はない**
- 既に存在する物理資産: `.claude/hooks/pretool_policy.py`、`scripts/codex/run-in-worktree.sh`、git worktree (実運用しているが未活用)、`.claude/state/git.lock` (flock)
- Owner は git に慣れているがプログラマではない。Python / shell は読めるが、新たな daemon や Rust binary を運用するのは負荷
- 「Owner ひとり開発、ただし 10+ project を OrgOS で並列運用したい」が真の要件

---

## Q1. Constitutional Invariants (5-7 個) の具体仕様

前回「constitutional invariants は 5-7 個、それ以外は降格」と提案してくれた。
**具体的に何をその 5-7 個に置くか**、以下の項目で各 invariant を書いてほしい:

- 名前 (短く、英語可)
- 内容 (1 行)
- 違反検出の手段 (pretool hook / git hook / event log / CI / 不可能、のいずれか)
- enforcement の手段 (拒否 / 警告 / Owner 通知 / rollback)
- 違反時のリカバリ手順 (1-2 行)

「これは constitutional ではなく procedure に降格」のラインも明示してほしい。

---

## Q2. Migration Plan — 6-8 週間の週次ロードマップ

「最小 kernel から作り、kernel で守れない機能は追加しない」と前回言った。
ただし**現状の OrgOS は既に稼働中**で、Owner は 10+ project で日々使っている。**一気に作り直すのは無理**。

以下を満たす週次 migration plan を書いてほしい:

- 6-8 週間で完了
- 各週は「ship可能な単位」(週末時点で OrgOS が壊れない)
- 既存 `.ai/TASKS.yaml` の active task は途中で読めなくならない (並走または変換)
- どの週で何を ship し、何を deprecate するか
- 「ここで失敗したら巻き戻す」rollback point を 2-3 箇所
- Owner が運用しながら進める想定 (停止期間を作らない)

特に **Week 1 で何を ship するか** に焦点を当ててほしい。最初の 1 週間で誤 commit と shared worktree が止まれば、Owner は他の作業を続けられる。

---

## Q3. Integrator Gate の具体設計 (Claude Code 基盤上で)

「commit できるのは integrator のみ」を Claude Code 上でどう実現するか?

選択肢として:
(a) Claude Code の subagent として org-integrator を作り、Manager が work order を渡す形
(b) `.claude/hooks/pretool_policy.py` を強化し、`git commit` を発見したら現在の agent を判別して拒否
(c) Codex worktree 内で `git config --local core.hooksPath` を仕掛け、commit hook で常に exit 1
(d) Codex を AGENTS.md レベルで「commit 禁止」と明示し、reasoning に効かせる
(e) 別 git wrapper script (`scripts/git/safe-git`) を強制し、PATH を制限
(f) 上記の組み合わせ

それぞれの**実装難度・bypass 可能性・運用コスト**を表で評価し、推奨を 1 案 (または最小組み合わせ) 選んでほしい。

「Codex の意志を信頼する」案 (d) は前回否定済みだが、現実には PATH 制限などをすり抜ける手段は無数にある。あなたの**「これくらいで十分」のラインをどこに引くか**を明示してほしい。

---

## Q4. State Store のスキーマ案

SQLite + append-only event log の二層構成を推した。
これを Owner 1 人 + 10+ project で実用化する場合の具体スキーマを書いてほしい:

- SQLite tables (各 table のカラムと型、最低限のもの)
- event types (TaskCreated, LeaseAcquired, ... など、現実的な粒度で 10-20 個)
- どこに event log を置くか (per-repo? per-Owner global? hybrid?)
- 既存 `.ai/TASKS.yaml` (52 task) からの初期 import 戦略
- 「YAML / Markdown は generated view」と言ったが、**どのタイミングで再生成するか** (event 毎? daily? on-demand?)
- AI が「現在の TASK 一覧」を知りたいとき、どこを読むか (DB? generated YAML? どちらも危険な場合は?)
- 同じファイルを human が編集してしまった事故をどう検出するか

「Owner にとって編集しないけど目視はする」ファイル (例: 生成された DASHBOARD.md) と、「人間も読まないし書かない、機械専用」ファイル (例: SQLite) の境界を明確にしてほしい。

---

## Q5. Owner UX — Intent から Plan Contract への対話例

前回「Owner が intent を述べ、System が Plan Contract を返す」と提案した。
**実際の対話例**を 2-3 件書いてほしい:

例 A: 通常依頼 (例: 「認証機能の bug を直して」)
例 B: 並列依頼 (例: 「auth と billing を並列で直して」)
例 C: 危険依頼 (例: 「production の DB schema を変更したい」)

各例について:
- Owner の発話
- System (Manager) の Plan Contract 出力例 (フォーマット込みで具体的に)
- Owner の possible responses (approve / modify / reject)
- Owner approve 後、System が何を実行するか
- Owner が plan を読まずに approve した場合の安全装置

可能なら「現状の `/org-tick` が見せている情報量」と「理想の Plan Contract」の差分を表で比較してほしい。

---

## Q6. Kill List — 既存資産の棚卸し

現状 OrgOS の以下を、新アーキテクチャ移行時に **「殺す / 残す / 形を変えて残す」** で分類してほしい:

- `.claude/rules/*.md` (30+ ファイル) → どのカテゴリの rule は kill か?
- `.claude/agents/*.md` (manager / codex / org-architect / org-reviewer / org-planner / ... 計 15+ 個の subagent prompt)
- `.ai/TASKS.yaml` の 52 task のうち、本 meta-review 完了後に **撤回すべき task** はあるか? (特に T-OS-390〜399 の対応案)
- `scripts/` 配下の数十 script
- `.ai/USER_PROFILE.yaml` / `.ai/CAPABILITIES.yaml` / `.ai/GOALS.yaml` / `.ai/DECISIONS.md` / `.ai/DASHBOARD.md` (個別評価)
- Request Intake Loop (10 step) — kernel に昇格? procedure に降格? 廃止?
- Handoff Packet schema — 「Handoff は説明であって証拠ではない」と言ったが、ではこの schema 自体は不要?
- Authority Layer (autonomy_level: silent_execute / execute_with_report / ask_before_execute / owner_only) — 残すべき?

**「これは残す価値がある」と「これは捨てるべき」を、現実主義的に**。100% kill だと migration 不可能、100% keep だと変わらない。50-70% kill を目安に。

---

## Q7. 自己批判 — 提案アーキテクチャの failure mode

前回の提案 (capability broker / event sourcing / integrator gate / Plan Contract) が**現実に失敗するシナリオ**を 3-5 個挙げてほしい。

例えば:
- SQLite + event log を入れたら projection バグでさらに混乱
- Integrator gate が bottleneck になり、並列の意味がなくなる
- Plan Contract が Owner にとって冗長で、結局元に戻る
- Capability broker が抜け道だらけになる
- Manager が plan できなくなり、Owner が自分で task graph 書く羽目になる

各シナリオに**早期検出指標** (これが起きたら migration を中止すべき) を付けてほしい。

---

## Q8. (任意) 「Owner 個人開発、AI 中心」というスケールへの最適化

OrgOS の真の規模は「Owner 1 人 + 複数 AI + 10+ project 並列」。
これは普通の software team の規模ではない。**個人 + AI 中心** という新しい構造に対し、既存の software engineering best practice (CI/CD、code review、PR workflow) をどこまで踏襲し、どこから捨てるべきか?

例えば:
- Pull request 文化は維持か廃止か (1 人なら不要では?)
- Code review は AI 同士でやらせれば十分か
- Branch 戦略は何が最適か (Git Flow? trunk-based? feature branch?)
- CI は必要か (自分しか触らない repo で)

「個人開発 + AI」のための新しいワークフロー設計を、5-10 行で示してほしい。

---

## Output Format

```markdown
# OrgOS 理想形批評 — Follow-up 回答 (GPT-5.5 Pro)

## Q1. Constitutional Invariants 仕様
| 名前 | 内容 | 検出 | enforcement | 復旧 |
|---|---|---|---|---|
...

## Q2. Migration Plan (週次)
### Week 1
- Ship: ...
- Deprecate: ...
- Rollback point: ...
### Week 2
...

## Q3. Integrator Gate 設計
| 選択肢 | 実装難度 | bypass 可能性 | 運用コスト |
|---|---|---|---|
...
推奨: ...

## Q4. State Store スキーマ
### SQLite tables
...
### Event types
...

## Q5. Owner UX 対話例
### 例 A: 通常依頼
Owner: 「...」
System: 「Plan Contract: ...」
...

## Q6. Kill List
### 殺すもの
...
### 残すもの
...
### 形を変えて残すもの
...

## Q7. 自己批判 — 失敗モード
1. シナリオ ... / 早期検出指標 ...
2. ...

## Q8. (任意) 個人 + AI 開発の workflow
...

## Summary
3-5 文。次の一手を太字で 1 つ。
```

---

## 重要な追加依頼

- 前回回答と整合させること。矛盾するなら「前回はこう言ったが、Claude Code substrate 制約を踏まえると改める」と明示
- **Week 1 で何を ship するか**は最重要。ここが現実的でないと全体が机上の空論になる
- Kill List は遠慮せず厳しく。Owner と Manager (Claude) は感情的に資産を捨てにくいので、外部視点で踏み込んでほしい
- 自己批判 (Q7) は本気で。「失敗するなら最低限こうやって早く気付く」までセットで

---

(prompt 本文ここまで)
