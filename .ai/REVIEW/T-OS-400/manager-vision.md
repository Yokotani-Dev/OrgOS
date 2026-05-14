# OrgOS 理想形 — Manager 視点 (T-OS-401)

> 作成: 2026-05-14 / 作成者: Manager (Claude Opus 4.7)
> 目的: 「問題が発生するたびに暫定対応が続く」サイクルからの構造的脱却を、Manager 自身の運用感覚から起案する。

---

## 1. 現状の根本病理 — なぜ patch-on-patch が止まらないか

### 1.1 観測された症状

- 事故 2026-05-10 (ecology incident): T-OS-360〜363 を 2026-04 に done にしたのに、同種の並列実行衝突が再発。
- 事故 2026-05-09 (reflog incident): 9 プロセス並走で `main` への意図しない切替 3 回 + 誤 commit 寸前。
- SELFREVIEW-001/002 で「Authority Layer 12%」「Quality Contract 後出し」が指摘され、その都度ルール追加。
- T-OS-380〜382 (SELFREVIEW-002 follow-up) と T-OS-390〜399 (本回 FB) が並走しており、**メタ修正タスク自体が patch-on-patch している**。
- `.claude/rules/*.md` は本セッション起動時点で 30 ファイル超。Iron Law が複数ファイルに分散し、矛盾検出が人手依存。

### 1.2 5 つの構造的欠陥

#### 欠陥 A — Rule と Runtime Enforcement の解離
`.claude/rules/*` は markdown で「やってはいけないこと」を宣言するが、実際にそれを止めるのは `pretool_policy.py` / `scripts/*` のごく一部のみ。**ルール本数 30 vs 実 runtime gate 数 5 件未満**という非対称が、「ルールはあるのに事故が起きる」現象の正体。

具体例: `parallel-session-policy.md` が「1 セッション = 1 リポジトリ」を Iron Law として宣言したが、それを物理的に止めるロックは存在せず、Owner が複数チャットを開く瞬間に無効化される。

#### 欠陥 B — Manager の責務過剰 (overload)
Request Intake Loop の Step 1〜10 で Manager は: 原文保存 / memory retrieve / work graph bind / capability discovery / risk classify / decide / execute / verify / ledger update / coherence report、までを 1 ターンで行う。
さらに DESIGN gate / IMPLEMENTATION gate / Quality Contract / Journey / Domain Constraint / Threat Model / Authority Layer の各 rule を読みながら判断する。

**結果**: Manager は「忘れる」「飛ばす」「コンテキスト圧縮で消える」。Tick フロー統合 (T-OS-380) が必要になったのはこのため。

#### 欠陥 C — 状態の散逸 (state fragmentation)
SSOT を名乗るファイルが乱立:

| ファイル | 主たる責務 | 重複 |
|---|---|---|
| `TASKS.yaml` | task DAG | `GOALS.yaml` と tasks_ref 二重管理 |
| `GOALS.yaml` | milestone / project | `TASKS.yaml` と status 同期手作業 |
| `USER_PROFILE.yaml` | facts / preferences / secrets | `DECISIONS.md` と past_qa 重複 |
| `CAPABILITIES.yaml` | tool manifest | `scripts/capabilities/scan.sh` 出力で再生成 |
| `CONTROL.yaml` | flags / phase | `GOALS.yaml.active_graph.current_phase` と二重 |
| `DECISIONS.md` | 判断ログ | append-only だが scan されない |
| `DASHBOARD.md` | summary | 手動更新 / 自動更新混在 |

**透明性のためのファイルが、整合性メンテナンスの負債源になっている**。

#### 欠陥 D — 抽象化の方向ミス
OrgOS は「人間の組織図 (Owner / Manager / Codex / Reviewer / Architect / ...)」を比喩として採用したが、これは**ソフトウェア工学的に不正な抽象**である。

理由: 人間組織の役割分担は「能力差」「責任問題」「契約」が前提だが、AI agent には能力差はあれど責任は無く、契約は無く、信頼境界は技術的構造でしか担保できない。
組織図抽象を採ると「Codex に commit させない」が "ルール遵守の問題" として扱われ、**サンドボックスで物理的に commit を阻止する** という工学的解が出てこない。

#### 欠陥 E — フィードバック非対称性
- ❌ Owner FB → ルール追加 → 配備 → 事故 → ルール追加 (現状ループ)
- ✅ 期待: Owner FB → 根本原因階層化 → kernel/userspace どちらの問題か判定 → kernel なら invariant 追加 / userspace なら hot-patch

現状は「全 FB が等しく `.claude/rules/` に積まれる」ため、本質的 invariant とその場限りの workflow tweak が混在している。

---

## 2. 理想形 — 8 つの設計原則

### 原則 1: Kernel と Userspace の明確分離
**OrgOS は OS なら、kernel が必要。**

| 層 | 内容 | 変更コスト |
|---|---|---|
| **kernel** | invariant runtime enforcement (pretool hook, schema validator, lock manager, authority gate) | 高 (Owner 承認 + 動作テスト必須) |
| **userspace** | agent prompts, skills, workflow templates, communication style | 低 (Manager 自律編集可) |

判定基準:
- ある rule を破ると「データ消失 / 不可逆操作 / セキュリティ侵害」が起きる → kernel
- ある rule を破っても「効率悪化 / 説明不足 / 軽微なミス」のみ → userspace

現状の `.claude/rules/*` の **半分以上は userspace に再分類すべき**。

### 原則 2: 全 Iron Law は Runtime Check を持つ
markdown で書かれた Iron Law は、それを破ろうとした瞬間に止める runtime check (pretool hook / schema validator / lint) を必須セットで持つ。

```
rule追加 PR の受入基準:
  ☐ markdown で rule を明文化
  ☐ 違反を検出する runtime check 実装
  ☐ check を bypass する手段の明示 (Owner 承認フロー)
  ☐ check の自動テスト (違反 case と正常 case)
```

**現状 30 rule 中、これを満たすのは 5 件未満。**残りは「documentation-only rule」として userspace へ降格、または check 追加までは Iron Law を名乗らない。

### 原則 3: 状態は単一の event log + 派生 view
SSOT を「ファイル」ではなく「append-only event log」に統一する。

```
.ai/EVENTS.jsonl  (SSOT, append-only)
  ↓ project (replay)
.ai/views/tasks.yaml      ← TASKS.yaml の代替
.ai/views/goals.yaml      ← GOALS.yaml の代替
.ai/views/dashboard.md    ← DASHBOARD.md の代替
.ai/views/profile.yaml    ← USER_PROFILE.yaml の代替
```

Manager は **event を append するだけ**。view は projection で生成。整合性は projection が保証。手作業の同期不要。

副次効果: Time-travel debug、状態 rollback、cross-session merge が trivial になる。

### 原則 4: Codex を sandbox に閉じ込める (capability、not permission)
「Codex は commit してはいけない」を**ルール**で書くのではなく、**Codex 起動環境で git binary に commit hook を仕込み物理的に拒否**する。

```bash
# scripts/codex/sandbox-init.sh
git config --local core.hooksPath .git/orgos-hooks
# .git/orgos-hooks/pre-commit: exit 1 (Codex worktree では常に拒否)
```

「やってはいけない」を「やれない」に変換。authority layer は capability-based に再設計。

### 原則 5: Manager は dispatcher であり、 worker ではない
Manager の責務を以下に限定:
- intake (依頼を受け原文保存)
- bind (work graph に紐付け)
- dispatch (適切な kernel service or userspace agent に投げる)
- aggregate (結果集約)

**risk classification, capability discovery, ledger update は kernel service が担当**する。Manager は service の戻り値を Owner に伝えるだけ。

これにより Manager が「忘れる」「飛ばす」が構造的に発生不能になる (service が呼ばれなければ動かないので)。

### 原則 6: Owner は Intent を述べる、OrgOS は Plan を返す
現状 Owner は CONTROL.yaml flags、TASKS.yaml schema、authority level、worktree、Codex の挙動を知らないと運用できない。**これは OS ではなく toolkit である**。

理想:
```
Owner: 「並列で 3 つ動かしたい」
OrgOS:  Plan を提示 (どの worktree でどう dispatch するか) → Owner 承認 → 実行
```

Owner は「やりたいこと」を述べ、OrgOS は「どう安全に達成するか」の plan を返す。flag の手動操作は最後の手段。

### 原則 7: 定期的な consolidation (compaction)
ルール / タスク / 決定が単調増加するのを止める。

```
四半期ごとに consolidation tick:
  - 過去 N か月で発火しなかった rule → archive 候補
  - 同一 invariant を表現する複数 rule → merge
  - 古い decision で superseded されたもの → fold
  - kernel への昇格 / userspace への降格
```

これを行わないと、**OrgOS 自身が誰も読まないドキュメント群になる** (= 現状)。

### 原則 8: 観測可能性とテスト可能性
全 kernel invariant に対し:
- 違反 case の自動テスト
- 正常 case の自動テスト
- 1 か月の発火履歴 (.ai/EVENTS.jsonl から集計)

「rule が機能しているか」を**勘ではなく数値で判断**する。Manager Quality Eval はこの方向の先駆けだが、kernel runtime にも適用する。

---

## 3. 現状アーキテクチャとの差分

| 領域 | 現状 | 理想形 | 差分 |
|---|---|---|---|
| 状態 | 7+ YAML/MD 手動同期 | event log + projection | 全 view 再生成 script + EVENTS.jsonl 設計 |
| 強制 | rule (markdown) | rule + runtime check の必須セット | 全 Iron Law に check を逆引きで追加 / 不可能なものは降格 |
| Codex | policy で commit 抑制 | sandbox で git 物理拒否 | sandbox-init.sh + hooksPath 設定 |
| Manager | 全責務 1 人 | dispatcher のみ | kernel service 群 (`orgctl risk`, `orgctl bind`, ...) 切り出し |
| Owner | flag 直接操作 | intent → plan 提示 | `orgctl plan` 的 CLI、`/org-tick` の plan 表示強化 |
| Rule | 単調増加 | 四半期 consolidation | retention policy + sunset 機構 |

---

## 4. 段階的移行案

### Phase A: kernel/userspace 棚卸し (2 週間)
- 現存 30+ rule を kernel / userspace / archive に再分類
- kernel と宣言した rule について runtime check の有無を表化
- check 不在のものを「降格 or check 追加」で決着

### Phase B: 状態統合 PoC (1 か月)
- EVENTS.jsonl + projection script を 1 view ($TASKS.yaml$) で試作
- 既存 TASKS.yaml と並走、不整合検出
- 問題なければ他 view へ拡大

### Phase C: Codex sandbox 工事 (1 週間)
- scripts/codex/sandbox-init.sh + git hooks
- 既存 T-OS-391 (Codex commit 禁止) を policy ではなく sandbox で実装
- 全 Codex 起動を sandbox 経由に移行

### Phase D: Manager dispatcher 化 (継続)
- 各 Step (risk classify, bind, capability, ledger) を CLI 化
- Manager prompt は dispatcher 用に簡素化
- session-bootstrap.sh が CLI を呼ぶ orchestrator になる

### Phase E: Consolidation 自動化 (継続)
- rule 発火履歴の集計
- 四半期で consolidation PR 自動提案
- archive 機構

---

## 5. T-OS-390〜399 の再評価

本理想形に照らすと:

- **T-OS-391 (Codex commit 禁止)** → 原則 4 へ昇格。policy ではなく sandbox で実装
- **T-OS-392 (allowed_paths 衝突 pre-flight)** → 原則 2 のとおり check 実装で本質的に正しい
- **T-OS-393 (main 直 commit 拒否)** → 原則 4 と同様、git hook で物理拒否
- **T-OS-394 (worker フィールド + heartbeat)** → 原則 3 と衝突。EVENTS.jsonl があれば worker 追跡は projection で十分
- **T-OS-395 (feature branch 自動)** → 原則 4 と統合。sandbox 起動時に branch 作成
- **T-OS-396 (.ai/LOCKS/)** → 原則 3 と衝突。EVENTS.jsonl から lock を projection
- **T-OS-398/399** → 短期不要、原則 7/8 の枠組みで再評価

**結論**: T-OS-390〜399 の 7 割は本理想形のもとで形を変える。本 epic 完了前に dispatch しないのは正しい判断。

---

## 6. リスクと反対意見への先取り回答

### Q1: EVENTS.jsonl 導入は overkill ではないか
A: 部分導入可能。最初は TASKS.yaml のみ projection 化、効果検証後に他へ拡大。初期コスト 1〜2 週間、その後の維持コストは現状の手動同期より低い。

### Q2: 既存ルールを大規模再分類すると破壊的では
A: 段階的移行 (Phase A) で 1 件ずつ評価。互換性は kernel/userspace タグの追加だけで保たれる。markdown 本体は触らない。

### Q3: sandbox で commit 拒否すると緊急時に困る
A: 緊急時は Owner が明示的に sandbox を bypass (環境変数 `ORGOS_SANDBOX_BYPASS=1` + DECISIONS.md 記録)。bypass 履歴は EVENTS.jsonl に残るので audit 可能。

### Q4: Manager dispatcher 化は LLM の強み (柔軟判断) を捨てないか
A: 柔軟判断は kernel service 内部で LLM を使えば残せる。Manager は「どの service を呼ぶか」を判断する。LLM のコンテキスト負荷が分散され、むしろ品質向上。

---

## 7. Owner への問い

本ドキュメントに対し、Owner に以下を問いたい:

1. 「OS としての kernel/userspace 分離」という抽象は、Owner の運用イメージに合うか?
2. EVENTS.jsonl 化は、Phase B (1 か月) のコストを払う価値があると感じるか?
3. Codex sandbox 化は、緊急時 bypass を設計すれば許容できるか?
4. Manager の dispatcher 化は、現状の応答粒度より「機械的すぎる」と感じる懸念はあるか?

これら 4 点は ②Codex 視点 / ③第3AI 視点 と突き合わせる前に Owner 直接判断が望ましい論点。

---

## Appendix: 本ドキュメントの限界

- Manager 自身が組み込まれている系を批評しているため、bias がある (役割を守りに行く / 削りに行く、いずれにも偏り得る)
- 実装難度の見積もり (Phase A-E の期間) は Manager の経験則。Codex / 第3AI の見積もりと突き合わせ要
- 「組織図抽象が不正」と断言したが、これは強い主張。第3AI に反論を求める価値あり
