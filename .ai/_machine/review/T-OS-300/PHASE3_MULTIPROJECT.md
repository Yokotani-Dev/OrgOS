# Phase 3 候補: Multi-Project Decision Hub (Local-First)

> 作成: 2026-05-01 / Owner Feedback 反映
> 位置付け: Phase 2 (Self-Evolution Engine) の **後** または **並行** で検討。本ファイルは Phase 3 の論点記録。

---

## Owner Declaration (原文)

> 「これは本当に将来的でいいんだけど、org を使って 10 個ぐらいの PJ を並列して開発しているから、決済点だけを確認するにしてもそれを管理できていない状況なんだよね。一方、claude code を使う以上はローカルで作業しないといけないから、それをどう管理するか、が次の論点としてあるね。」

---

## 問題定義

### 1. 多プロジェクト並列の現実
- Owner は約 **10 個** の OrgOS プロジェクトを並列稼働
- 各プロジェクトに独立した `.ai/OWNER_INBOX.md` / `DASHBOARD.md` / `TASKS.yaml` が存在
- Phase 2 で OWNER_INBOX を Decision Table 化しても、**プロジェクトごとに 1 つの table** ができるだけ
- 結果: Owner は「どの PJ にどんな決済がいくつ溜まっているか」を瞬時に把握できない

### 2. ローカル制約
- Claude Code は **ローカル** で動作する前提 (各 PJ ディレクトリで `claude` 起動)
- リモート集約サービスを作るのは現実的でない
- 各 PJ の OS が独立して動き、それを **跨ぐ集約レイヤー** が必要

### 3. 既存資産との関係
- T-OS-060〜062 で `OrgOS Dashboard` が言及されている (マルチプロジェクト統合 UI、status: done)
- 実態確認が必要 — 設計のみか、稼働しているか
- もし稼働しているなら Phase 3 は **その拡張** として位置付け

---

## 設計仮説 (粗いスケッチ、詳細は本格着手時)

### 仮説 A: Hub Repository (上位ディレクトリ)

```
~/.orgos/
├── hub.yaml                   # 登録された PJ 一覧 + path
├── decisions.aggregated.md    # 全 PJ の決済点を集約 (cron で fetch)
├── digest.weekly.md           # 全 PJ の Weekly Digest 集約
└── projects/
    ├── 01-orgos-dev → ~/Dev/Private/OrgOS
    ├── 02-ec-site   → ~/Dev/Private/EC
    └── ...
```

- 各 PJ の `.ai/OWNER_INBOX.md` `EVOLUTION/events.jsonl` `METRICS/owner-bandwidth/` を symlink/scan で集約
- `orgos-hub` CLI で「今どの PJ に何件決済」「全体 Owner Bandwidth」を 1 画面表示
- Slack/Webhook 通知も hub から一元発信

### 仮説 B: Hub-as-Project

OrgOS 自身を「メタ OrgOS」として運用:
- このリポジトリ (`OrgOS/`) を **Hub PJ** として設定
- 他 10 PJ は `subprojects` として登録
- Phase 2 で作る Decision Table を Hub レベルでも同形式で持ち、子 PJ から fetch
- Hub PJ の Manager が「全 PJ の Synthetic Owner」役を担い、Owner には 1 つの Decision Table だけ提示

### 仮説 C: Federated DNA

Phase 2 の `ORG_DNA.yaml` を活用:
- 各 PJ の DNA に `siblings: []` フィールドを追加 (他の自分のプロジェクトを参照)
- DNA レベルで「この決済は他 PJ に伝播する/しない」を宣言
- 例: `model_alias` 変更は全 PJ に伝播、`literacy_level` は PJ 個別

---

## 解くべき問題リスト

| ID | 問題 | 緊急度 |
|---|------|------|
| MP-01 | 全 PJ の決済点を **1 画面** で把握できる UI/CLI | 高 |
| MP-02 | 全 PJ の Owner Bandwidth metrics を集約 | 中 |
| MP-03 | プロジェクト横断の P0 incident (例: capability degraded) を 1 ヶ所に通知 | 高 |
| MP-04 | 1 つの決済が他 PJ に伝播すべきか自動判定 (例: モデル alias 更新) | 中 |
| MP-05 | ローカル制約下で hub をどう常駐させるか (launchd / cron / GitHub Action) | 高 |
| MP-06 | 各 PJ の Self-Evolution Engine が暴走したとき hub レベルで stop できる仕組み | 中 |
| MP-07 | Hub と各 PJ の DNA バージョンずれ (community DNA を 1 PJ だけ取り込んだ等) の管理 | 低 |
| MP-08 | Hub 自身の Manager Quality 評価 — メタ OS の品質をどう測るか | 低 |
| MP-09 | ローカル制約で「Owner が PC を開いてないとき」の動作 (Phase 2 Always-On との接続) | 中 |
| MP-10 | Claude Code セッションを跨いだ context 引き継ぎ — hub 経由で session-state を共有可能か | 低 |

---

## Phase 2 との関係 (依存・直交)

| Phase 2 タスク | Phase 3 への前提性 |
|--------------|-----------------|
| T-OS-320 (Event Store) | **必須前提**: 各 PJ の events.jsonl が標準化されないと hub で集約できない |
| T-OS-321 (Decision Table) | **必須前提**: Decision schema が PJ 共通でないと集約が破綻 |
| T-OS-323 (DNA v0.1) | **必須前提**: Federated DNA の基盤 |
| T-OS-329 (Always-On) | **共通基盤**: hub のスケジューラと統合 |
| T-OS-330 (Marketplace) | **同種思想**: community DNA fetch と hub-internal DNA sync は同じ機構 |
| T-OS-331 (Evolution Dashboard) | **同種思想**: PJ 単位 Dashboard を hub 単位に拡張 |

**結論**: Phase 3 は Phase 2 の上に**積み上げる**設計で、Phase 2 完了前に着手するのは非効率。

---

## 推奨着手タイミング

### 短期 (今すぐ)
- 本ファイル `.ai/REVIEW/T-OS-300/PHASE3_MULTIPROJECT.md` で記録 (✅ 完了)
- TASKS.yaml に T-OS-340 系として queued 登録 (`status: queued`, `deps: [T-OS-321, T-OS-323]`)
- Owner には「Phase 3 として記録、Phase 2 完了後に再評価」と説明

### 中期 (Phase 2 が First 3 Tasks 完了後 = 約 1 ヶ月後)
- T-OS-060 (既存 OrgOS Dashboard) の実態確認
- Hub 仕様の MVP 設計 (仮説 A/B/C のどれを採るか)
- Owner の 10 PJ のうち 2-3 を pilot として選定

### 長期 (Phase 2 全完了後 = 約 3-4 ヶ月後)
- Hub 本実装 (T-OS-340〜349)
- Federated DNA 実装
- 全 10 PJ の onboarding

---

## Phase 3 P0 タスク (粗案、詳細は着手時に再設計)

| ID | Title | 想定 Effort |
|---|-------|------------|
| T-OS-340 | T-OS-060 (OrgOS Dashboard) 実態確認 + ギャップ分析 | S |
| T-OS-341 | Hub Repository 仕様定義 (`~/.orgos/` schema) | M |
| T-OS-342 | 全 PJ Decision Aggregator (events.jsonl から fetch) | M |
| T-OS-343 | Hub CLI (`orgos-hub status / inbox / digest`) | M |
| T-OS-344 | Cross-Project Bandwidth Tracker | S |
| T-OS-345 | Federated DNA — `siblings` 機構 | L |
| T-OS-346 | Hub レベル P0 incident 通知 (Slack/Webhook 一元化) | S |
| T-OS-347 | Hub Always-On scheduler (各 PJ の cron 統合管理) | M |
| T-OS-348 | Hub から子 PJ への伝播判定 (例: モデル alias 更新) | M |
| T-OS-349 | 10 PJ pilot rollout + 学び抽出 | L |

---

## ローカル制約への補足設計

Owner declaration「claude code を使う以上はローカルで作業しないといけない」への直接応答:

### 現実的な前提
- Anthropic 側のクラウド常駐サービスは現状ない
- 各 PJ は Owner の MacBook 等で claude code 起動が必要
- **Owner が PC を開く時間** が依然として律速

### 緩和策 1: Local Daemon
- `~/.orgos/daemon` を launchd で常駐
- 各 PJ の `.ai/EVOLUTION/events.jsonl` を 5 分間隔で scan
- P0 event を即 Slack 通知 (Owner の PC が立ち上がっていない時間帯も)
- Owner が PC を開いた時点で hub CLI が即サマリ表示

### 緩和策 2: GitHub Actions (PJ ごと)
- 各 PJ の GitHub repo に Action を仕込み、深夜 daily で `/org-evolve dry-run` 相当を回す
- 結果を artifact として残す
- Owner が PC を開く頃には「夜中に何件の検出があったか」が GH Actions に記録済

### 緩和策 3: Async Owner Reply
- Slack に届いた D-XXX に「approve」と返信 → GitHub webhook で対応 PJ の OWNER_COMMENTS.md に commit
- 次に Owner が PC を開いて claude を起動した瞬間に取り込まれる
- Phase 2 T-OS-415 (Always-On Slack 承認) と同じ機構を hub レベルでも

---

## 公開設計議論

本ファイルは **問題提起と粗スケッチ** に留め、詳細設計は Phase 2 完了後に再着手。Phase 2 で得られる以下の成果が前提となる:

- DNA schema が安定 (Federated DNA の前提)
- Decision Table format が標準化 (Aggregator の前提)
- events.jsonl schema が標準化 (Hub Scanner の前提)
- Synthetic Owner が信頼できる (Hub-as-Project 案の前提)

逆に Phase 2 がこれらを満たせば、Phase 3 は数週間で MVP が立ち上がる見込み。

---

## Owner Action 不要

本ファイルは記録目的。Owner は何も承認する必要なし。Phase 2 が First 3 Tasks (T-OS-320/321/322) を完了した時点で Manager が再度 Phase 3 提案を行う。
