# Observability & Learning v2 — 設計提案

> Owner 依頼 (2026-06-14): (1) UI ログが「session end」だらけで何をしたか分からない → 具体化したい。
> (2) 指示・修正からの「反省」を残し、間違い／思想をどう OrgOS に統合するか検討してほしい。
> 本書は #3(T-OS-504) と #4(T-OS-505) の設計。status: draft（Owner 確認待ち）。

---

## 課題 #3 — ログ品質（T-OS-504）

### 根本原因
`log-event.sh` を呼ぶのは主に SessionStart/Stop フックで、タイトルが固定の "session start"/"session end"。
セッション境界イベントがリポジトリごとに大量に並び、**実際の作業内容（commit / タスク完了 / 判断）が埋もれる**。
スクショの vsp-admin が "session end" × 15 はこれ。

### あるべき姿
「そのセッション/日に何をしたか」が一目で分かる。情報源は既にある:
- **git commit**（最も濃い。subject に実作業）
- **kernel イベント**（TaskCreated/Updated/CommitIntegrated + task_id）
- **Manager の明示記録**（decision / task_done / note — 私がワークフローで打っているもの）

### 対策（3 点）
1. **Stop フックでセッション要約を生成**（最大の効き目）
   セッション終了時に「そのセッションで起きたこと」を集約して 1 件の `session_end` に書く:
   - そのリポジトリの直近 commit 数 + 代表 subject
   - 触れた task_id（kernel イベントから）
   - → 例: `session_end: 3 commits (v2.0.1 公開, T-OS-499/500/501 close) / 5 tasks`
   実装: `scripts/activity/summarize-session.sh`（git log since session_start + events 集計）を Stop フックで呼ぶ。
2. **bridge のイベント富化**
   `bridge-kernel-events.sh` が commit イベントに **commit subject** を、task イベントに **task title** を
   タイトルとして載せる（今は "TaskCreated T-OS-xxx" のみ）。
3. **viewer/journal のノイズ抑制**
   セッション境界イベントは既定で折り畳み（「セッション N 回」だけ表示、展開で詳細）。
   commit / task_done / decision を前面化。`event_type` 別の表示重みを導入。

### 効果
ジャーナルが「session end ×15」から「v2.0.1 公開 / T-OS-502 完了 / クローン汚染解消コミット ...」に変わる。

---

## 課題 #4 — 振り返り・知見統合ループ（T-OS-505）

### 何を解きたいか
Owner の指示・修正（例: 「選択肢で聞くな」「フォルダを分けろ」「クローン汚染を直せ」）や、
私の間違い（例: モデル障害で空ワークフロー、gitignore で junk を拾う）、
全体思想（例: 人間用/機械用の分離、ローカル前提）を **散逸させず、OrgOS の振る舞いに還元する**。

### 既存の受け皿（バラバラに存在）
| 仕組み | 用途 | 限界 |
|---|---|---|
| `USER_PROFILE` feedback memory | 振る舞い方針の記憶 | 私が手動 capture、抜けやすい |
| `DECISIONS.md` | 意思決定記録 | 「決定」であり「反省」ではない |
| `.ai/_machine/learnings` | 学び | 未配線・ほぼ空 |
| OIP / evolution engine | OrgOS 改善提案 | 重い・自動生成中心 |

→ **「反省を 1 箇所で受け、適切な恒久ホームへ振り分ける」導線が無い**のが本質。

### 提案: Reflection Loop（捕捉 → 分類 → 統合）

```
反省の発生（Owner修正 / 私の誤り / 思想）
   ↓  /org-reflect  または セッション終了時の自動抽出
REFLECTIONS 台帳 (.ai/_machine/learnings/reflections.jsonl) に1件記録
   ↓  分類（どの恒久ホームへ還元するか）
   ├─ behavioral（振る舞い癖）      → USER_PROFILE feedback memory に昇格
   ├─ systemic（ルール/手順の穴）    → 該当 rule/skill を更新（or 新設）
   ├─ philosophical（全体思想）      → CLAUDE.md/AGENTS.md 級は OIP 化してOwner承認
   └─ one-off（その場限り）          → 記録のみ（昇格しない）
   ↓
次セッションで session-bootstrap が REFLECTIONS の confirmed を読み込み、行動に反映
```

### 構成要素
1. **`/org-reflect` コマンド**: `「〜という反省/学び」` を渡すと REFLECTIONS に記録 + 分類提案。
   Owner が「これは思想だから CLAUDE に」「これは癖だから memory に」と確定 → 該当ホームへ反映。
2. **REFLECTIONS 台帳** (`reflections.jsonl`): {ts, trigger(owner_correction/self_error/principle), text, category, status(open/integrated/discarded), integrated_into(path)}。
3. **セッション終了時の自動抽出（任意・後段）**: そのセッションで Owner の修正・私の失敗があれば reflection 候補をドラフト（Owner が確定）。
4. **bootstrap 連携**: 起動時に `status=integrated` の behavioral/philosophical reflection を要約注入（過去の反省を毎回踏まえる）。

### この設計の肝
- **散逸防止**: すべての反省が REFLECTIONS にまず落ちる（1 入口）。
- **正しい恒久ホーム**: 振る舞い→memory、手順→rule、思想→OIP/CLAUDE と**昇格先を分ける**（既存資産を活かす）。
- **Owner 確定**: 思想/ルール級の変更は必ず Owner 承認（authority-layer 準拠）。私が勝手に思想を書き換えない。
- **既存ループとの非重複**: evolution engine は「OrgOS が自分のメトリクスから自動改善」、Reflection Loop は
  「**Owner との対話から学ぶ**」。入力源が違うので補完関係。

---

## 実装順序（提案）
1. #3 を先に実装（即効・低リスク・情報源は既存）。Stop 要約 → bridge 富化 → viewer 抑制。
2. #4 は本設計の確定後に MVP: `/org-reflect` + REFLECTIONS 台帳 + 手動分類昇格。自動抽出/bootstrap 注入は次段。

## Owner 判断が必要な点（#4）
- A) Reflection の昇格を **Owner 確定必須**にするか、behavioral だけ自動昇格を許すか。
- B) 思想級（CLAUDE/AGENTS 変更）の還元を OIP 経由にするか、reflection から直接提案にするか。
