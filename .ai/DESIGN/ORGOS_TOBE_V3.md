# OrgOS ToBe v3 — 構造監査後の再設計

> 作成: 2026-06-10 / 起草: subagent → Manager レビュー済 (2026-06-11)
> status: **manager_reviewed**（Owner 確認で confirmed へ昇格。フォルダ移行マップ§4 と Wave 構成§5 を Manager が承認。ISS-005 は OWNER_INBOX D-2026-06-11-001 で判断待ち）
> 入力:
> - `.ai/AUDIT/AUDIT-2026-06-10-orgos-structural.md`（確定 31 件 / RC-1〜RC-5 / 推奨着手順序）
> - `.ai/AUDIT/AUDIT-2026-06-10-confirmed-findings.json`
> - `.ai/DESIGN/ACTIVITY_LEDGER.md`（T-OS-481 confirmed / 482 実装中）
> - `.ai/DECISIONS.md` PLAN-UPDATE-WEEK8-AUDIT（kernel supersession 裁定）
> 系譜: ORGOS_TOBE.md (v1: 作業者→参謀長, 2026-04-18) → kernel v2 計画 (Week 0-8, 2026-05) → **本書 (v3: 監査後の整合回復と恒久構造)**
>
> 本書は設計のみ。ファイル移動・kernel 変更・manifest 変更は一切実施しない。

---

## 1. ビジョン

**OrgOS = Owner の Chief of Staff。** タスク管理ツールでも開発テンプレートでもなく、Owner の意図を預かり、どの作業現場（リポジトリ）でも同じ規律で動き、結果を 1 つの記録に残し、自分の調子を正直に申告する参謀である。

v3 が Owner に立てる **3 つの約束**:

| # | 約束 | 意味 | 現状とのギャップ |
|---|---|---|---|
| **(a)** | **どのリポジトリでも同じ品質で動く** | OrgOS をクローン/import した先で、本体と同じ kernel 保護・同じ正規書込パス・同じ Manager 挙動が成立する | 配布閉包が壊れている（ISS-006/007/029）。導入先では Iron Law の参照先が存在しない |
| **(b)** | **すべての活動が 1 つのジャーナルに残る** | リポジトリ横断で「今日実行したこと・考えたこと」が `~/.orgos/activity/` に集約され `/org-journal` と dashboard で見える | Activity Ledger は confirmed・実装進行中（T-OS-482）。repo 内イベントは 4 系統に分裂（ISS-015/019） |
| **(c)** | **自己計測が信頼できる** | eval の green は本物の green、red は見える red。DASHBOARD の表示は常に実測値 | eval 恒常 red + 41 日未実行 + fixture 自作自演 + 虚偽 green 表示（ISS-009/010/011/012, RC-5） |

判断基準: 以後のすべてのタスク・設計は「3 つの約束のどれを前進させるか」を明示する。どれも前進させない作業は受け付けない。

---

## 2. 現状診断 — 5 つの根本原因と「あるべき状態」

### RC-1: ルール層が kernel より遅く進化する（指示書未移行）
kernel v2 で正規の書込パスが hooks / org-tools に移ったのに、Manager が実際に読む指示面（CLAUDE.md・rules・commands・agents・AGENTS.md）は一行も更新されておらず、`update-task.py` / `integrator-commit.sh` への参照が全指示ファイルで 0 件。最高位 Iron Law が命じる行動（台帳直接編集・raw git commit）を kernel が deny する自己矛盾の結果、コミットが 3 週間停止し、エージェントは Bash バイパスへ構造的に誘導されている（ISS-001/002/018/021-025/030/031）。
**あるべき状態**: 指示層は「何を judgement するか」だけを薄く持ち、「どう書き込むか」は必ず org-tools のコマンド名で記述する。kernel/ツールの変更時は「下位文書 grep 総当たり更新」を変更タスクの acceptance に含める（配線完遂の定義 = RC-3 と同じ）。deny メッセージは常に正規パスを案内する。

### RC-2: 配布マニフェストに検証がなく、配布モデル自体が崩壊している
`.orgos-manifest.yaml` は手書き静的リストで、実体存在・参照閉包・kill 判定との同期がいずれも機械検証されない（eval-loop 死参照で CI が 3 週間 RED）。さらに上流で dev ツリー全体が public リポジトリへ丸ごと push され、キュレーション配布という前提自体が記録なしで放棄されている（ISS-003/004/005/006/007/029）。
**あるべき状態**: manifest は手書きしない。「タグ付け（このファイルは publish/core/dev）+ 依存閉包の自動解決」から**生成**し、生成物に対して (1) 実体存在 (2) 参照閉包（settings→hooks、CLAUDE.md→rules/agents、rules→scripts）(3) kill 判定同期、の 3 テストを CI で強制する。配布モデルは ISS-005 の Owner 判断（§6）で一本化する。

### RC-3: 「done」の定義に配線・検証が含まれていない（納品ギャップ）
SessionStart 検証 hook（未登録）、check-task-done.py（呼び出し元ゼロ）、daily-health-check（スケジュール未配線）、scheduler（出力読取機構なし）、update-active-graph.sh（未実装）など、**成果物は作られたが起動経路に接続される前に done になった**ケースが 8 件（ISS-008/012/014/016/019/020/026/028）。テストが env 注入や spurious pass で断線を隠蔽している。
**あるべき状態**: done = **実体 + 配線 + 本番経路での発火確認**。具体的には Work Order の acceptance に「どの hook / cron / コマンドから呼ばれるか」「本番経路での発火 1 回の証拠（イベント ID）」を必須項目化し、`check-task-done.py` を `update-task.py` の done 遷移にゲートとして配線する（ISS-013/014 の修正がこの強制の実装そのもの）。

### RC-4: 台帳 SSOT の世代交代が中途半端（旧は凍結・deny、新は未実体化）
WEEK8 audit で DASHBOARD/STATUS/RUN_LOG を superseded、EVENTS を新真実台帳と宣言したが、後継（orgos.sqlite / *.generated.* / plans/）が一つも実体化していない。旧台帳は kernel に手動編集を deny されたまま stale 情報を毎セッション注入し（デッドロック）、イベント台帳は 4 系統に分裂、Evidence-Gated Done は初の実運用 done で素通りした（ISS-013/015/017/019/027/028）。
**あるべき状態**: 世代交代は**同一トランザクション**で行う —「新台帳の実体化 + 生成パイプライン稼働 + 旧台帳の archive 移動 + 参照書換」を 1 つのタスク群として完了するまで、どちらか一方だけの状態を作らない。イベント発行は `append-event.py` の単一系統に統一し、`|| true` での無音化を禁止する。

### RC-5: eval / 計測系が信号を失い、かつ自己汚染している
eval は status enum drift で恒常 red（→ /org-evolve が全改善を REVERT）、41 日未実行なのに DASHBOARD は「20/20 pass」を表示、過去の green 自体が fixture facts を本番 USER_PROFILE に植え込んだ自作自演（ISS-009/010/011/012）。**ゲートが常時赤だと誰も赤を見なくなり、緑は信用できない。** 計測層の崩壊は他のすべての修復速度を律速する。
**あるべき状態**: (1) fixture と本番メモリの完全分離（`--profile-path` 注入）(2) /org-evolve の判定を「絶対 pass/fail」から「baseline 差分」へ変更 (3) DASHBOARD の eval 表示は実行結果 JSON からの自動生成のみ（手書き禁止）(4) eval 実行を scheduler に配線し、結果が Owner に届く（RC-3 の done 定義を適用）。

---

## 3. ターゲットアーキテクチャ — 5 層モデル

```
┌────────────────────────────────────────────────────────────┐
│ 観測層  Activity Ledger (~/.orgos/activity) + eval + journal│ ← 全層の実行結果を観測
├────────────────────────────────────────────────────────────┤
│ 配布層  .orgos-manifest.yaml（生成物）+ publish/import CI    │ ← 下 3 層を他リポジトリへ複製
├────────────────────────────────────────────────────────────┤
│ 指示層  CLAUDE.md / rules / commands / agents（薄く・判断のみ）│ ← Manager の judgement
├────────────────────────────────────────────────────────────┤
│ org-tools  scripts/org/ ほか（唯一の正規 mutation 経路）      │ ← 全状態変更はここを通る
├────────────────────────────────────────────────────────────┤
│ kernel  hooks(policy_core) + invariants + event chain + integrator │ ← 物理的 enforcement
└────────────────────────────────────────────────────────────┘
```

### 各層の SSOT と更新規律

| 層 | 構成物 | SSOT | 更新規律 |
|---|---|---|---|
| **kernel（enforcement）** | `.claude/hooks/*`, `KERNEL_FILES`, invariant 定義, `tests/kernel/` | `policy_core.py` + `kernel-mode.json` | Owner 承認 + kernel テスト green が必須。**発行する invariant ID と設定可能 ID は常に 1:1**（ISS-016/026 の再発防止: 「実装済み invariant のみ設定可」をテストで強制）。deny メッセージは必ず正規ツールを案内する |
| **org-tools（正規 mutation）** | `scripts/org/update-task.py`, `append-event.py`, `append-decision`(新), `integrator-commit.sh`, `acquire-lease.sh`, `generate-dashboard.py` | スクリプト実体 + そのテスト | 状態変更の追加要求が出たら**ルールではなくツールを足す**。すべての mutation はイベント発行（`append-event.py` 単一系統）を伴う。`\|\| true` での失敗無音化禁止 |
| **指示層（judgement・薄く）** | CLAUDE.md, `.claude/rules/`（WEEK8 still-needed 12 件のみ）, commands, agents | 各 rule ファイル | 「何をすべきか」の判断基準だけを書く。**書込手順は org-tools コマンド名で参照**し、手順本文を複製しない（pointer-not-payload）。kernel/ツール変更時は grep 総当たり更新が acceptance（RC-1 対策） |
| **配布層（生成 + 検証）** | `.orgos-manifest.yaml`（**生成物化**）, `/org-publish`, `/org-import`, 公開 CI | ファイル別タグ（publish/core/dev）+ 依存閉包リゾルバ | 手書き禁止。生成 → 3 検証（実体存在 / 参照閉包 / kill 判定同期）→ CI green が publish の前提条件（RC-2 対策）。ISS-005 の Owner 判断後にモデル一本化 |
| **観測層（Activity Ledger + eval）** | `~/.orgos/activity/events-*.jsonl`（横断 SSOT）, repo 内 `.ai/events/`（kernel chain）, evals, `/org-journal`, orgos-dashboard | 横断活動 = 中央ストア / repo 内監査 = hash chain / 品質 = eval 結果 JSON | repo 内 kernel イベントは bridge で中央へ自動取込（二重計装しない）。eval fixture は本番メモリと分離。表示（DASHBOARD/dashboard UI）はすべて観測データからの**生成**であり手書きしない（RC-4/RC-5 対策) |

### 層間の依存原則

1. **上の層は下の層を呼ぶ。下の層は上の層を知らない**（kernel は rules を読まない。rules は kernel の deny を前提に書く）。
2. **mutation は必ず org-tools 経由**。指示層が Edit/Write で状態を変える設計を新規に作らない。
3. **配布層は下 3 層の「閉包」を配る**。settings.json を配るなら hooks も配る。CLAUDE.md を配るならその参照先 rules も配る。閉包が壊れた配布は CI で物理的に止まる。
4. **観測層は唯一の「事実の出口」**。Owner への状況報告（DASHBOARD・journal・eval 表示）はすべて観測データの射影で、手書き更新は kernel が deny する（現に deny されている — 後継の生成系を実体化することで矛盾を解消する）。

---

## 4. フォルダ構成リデザイン — 人間用と機械用の分離

> Owner 要望（原文）: **「人間が開くフォルダとそうじゃないものを明確に分けてほしい」**

### 4.1 原則

1. **トップレベルで二分する**: `.ai/` 直下は「Owner / Manager が読む文書」だけにし、機械が読み書きする実行時データは **`.ai/_machine/`** に集約する（`_` プレフィックスは「人間は通常開かない」の視覚的シグナル + ソート先頭）。
2. **kernel が literal path で保護するファイルは動かさない**: `policy_core.py` の `PROTECTED_STATE_FILES`（TASKS.yaml / DASHBOARD.md / DECISIONS.md 等 10 件）と `.ai/CODEX/ORDERS/` / `.ai/plans/` は kernel 定数。これらの移動は kernel 編集（= Owner 承認 + テスト + バージョン bump）とセットでのみ可。
3. **日次ジャーナルはリポジトリ外**: 「今日やったこと」は `~/.orgos/activity/`（Activity Ledger, confirmed 済み）が SSOT。人間の入口は `/org-journal` と orgos-dashboard であり、`.ai/sessions/` は機械側に降格する。
4. **大文字/小文字の分裂を移動時に解消する**: `_machine/` 配下は小文字スネークケースに統一（`.ai/ARTIFACTS` vs `.ai/artifacts` 分裂 = 監査 P3-29 の解消を兼ねる）。

### 4.2 新トップレベル像

```
.ai/
├── （人間が開く: そのまま残す）
│   BRIEF.md  PROJECT.md  GOALS.yaml  JOURNEYS.yaml  RISKS.md
│   DASHBOARD.md（→将来 generated 化）  DECISIONS.md（読む用台帳）
│   OWNER_INBOX.md  OWNER_COMMENTS.md  CONTROL.yaml  TASKS.yaml（→将来 generated 化）
│   DESIGN/  AUDIT/  RUNBOOKS/  RESOURCES/  TEMPLATES/  OIP/
│   README.md（新設: この分離の案内板）
│
└── _machine/（機械の実行時データ: 人間は通常開かない）
    events/  leases/  queue/  sessions/  codex/  artifacts/  backups/
    metrics/  evolution/  integrity/  scheduler/  intelligence/
    approvals/  review/  os/  learnings/  supervisor-review/
    plans/（PlanContract 実装時にここへ新設）  archive/（superseded 旧台帳の退避先）
```

### 4.3 移動マッピング表（参照カウント実測値つき）

参照カウントは `scripts/ .claude/ tests/ .github/ .orgos-manifest.yaml CLAUDE.md AGENTS.md` を対象に `grep -rF`（*.sh/*.py/*.json/*.yaml/*.yml/*.md）で 2026-06-10 に実測。**refs = 該当行数 / files = 該当ファイル数**。リスク基準: LOW = refs ≤ 5、MED = 6–20、HIGH = 21+ または kernel hooks から参照あり。

| 現在パス | 新パス | refs (files) | kernel 参照 | リスク | 移行ステージ |
|---|---|---|---|---|---|
| `.ai/SUPERVISOR_REVIEW/` | `.ai/_machine/supervisor-review/` | 0 (0) | なし | **LOW** | Stage 1 |
| `.ai/LEARNED/` + `.ai/LEARNINGS/` | `.ai/_machine/learnings/`（統合） | 0 (0) | なし | **LOW** | Stage 1 |
| `.ai/APPROVALS/` | `.ai/_machine/approvals/` | 1 (1) | なし | **LOW** | Stage 1 |
| `.ai/OS/` | `.ai/_machine/os/` | 1 (1) | なし | **LOW** | Stage 1 |
| `.ai/BACKUPS/` | `.ai/_machine/backups/` | 2 (2) | なし | **LOW** | Stage 1 |
| `.ai/TASKS.yaml.bak.*`（3 ファイル, git tracked） | `.ai/_machine/backups/`（または削除, P3-23 と統合判断） | 0 | なし | **LOW** | Stage 1 |
| `.ai/INTEGRITY/` | `.ai/_machine/integrity/` | 3 (2) | なし | **LOW** | Stage 1 |
| `.ai/SCHEDULER/` | `.ai/_machine/scheduler/` | 6 (3) | なし | **MED** | Stage 2 |
| `.ai/sessions/` | `.ai/_machine/sessions/` | 7 (4) | **hook 1 件** | **MED** | Stage 2 |
| `.ai/events/` | `.ai/_machine/events/` | 11 (4) | append-event.py（org-tool） | **MED** | Stage 2 |
| `.ai/METRICS/` | `.ai/_machine/metrics/` | 14 (10) | なし | **MED** | Stage 2 |
| `.ai/leases/` | `.ai/_machine/leases/` | 15 (9) | **hook 1 件** | **MED** | Stage 2 |
| `.ai/REVIEW/` | `.ai/_machine/review/` | 18 (11) | なし | **MED** | Stage 2 |
| `.ai/ARTIFACTS/` + `.ai/artifacts/`（大小文字分裂） | `.ai/_machine/artifacts/`（統合） | 3+18=21 (12) | なし | **HIGH** | Stage 3 |
| `.ai/queue/` | `.ai/_machine/queue/` | 22 (7) | integrator-commit.sh | **HIGH** | Stage 3 |
| `.ai/INTELLIGENCE/` | `.ai/_machine/intelligence/` | 23 (8) | なし | **HIGH** | Stage 3 |
| `.ai/EVOLUTION/` | `.ai/_machine/evolution/` | 43 (17) | check-task-done.py default | **HIGH** | Stage 3 |
| `.ai/CODEX/` | `.ai/_machine/codex/` | 90 (24) | **policy_core.py:101-102（ORDERS パス hardcode）** | **HIGH** | Stage 3（kernel 編集伴う） |
| `.ai/plans/`（未存在・PlanContract 用） | 最初から `.ai/_machine/plans/` に新設 | （policy_core.py:260,322,329 が hardcode） | **あり** | **MED**（未稼働の今なら定数変更のみ） | Stage 2（PlanContract 実装前に kernel 定数を更新） |

**動かさないもの（人間用 / kernel-pinned）**:

| パス | refs | 理由 |
|---|---|---|
| `.ai/TASKS.yaml` `.ai/CONTROL.yaml` `.ai/DECISIONS.md` `.ai/DASHBOARD.md` `.ai/OWNER_INBOX.md` `.ai/OWNER_COMMENTS.md` `.ai/RISKS.md` ほか PROTECTED_STATE_FILES | 69 / 53 / 27 / 21 / 25 / 16 / 8 | kernel が literal path で保護。人間が開く台帳でもある。移動メリット < kernel 改変リスク |
| `.ai/DESIGN/` (refs=53) `.ai/TEMPLATES/` (29) `.ai/RESOURCES/` (26) `.ai/AUDIT/` (5) `.ai/RUNBOOKS/` (3) `.ai/OIP/` (3) `.ai/BRIEF.md` `.ai/GOALS.yaml` `.ai/JOURNEYS.yaml` | — | 人間（Owner/レビュワー）が読む文書。`.ai/` 直下 = 人間用という新原則にそのまま適合 |
| `.ai/STATUS.md` `.ai/RUN_LOG.md` `.ai/RUNTIME.yaml`（superseded 旧台帳） | 6 / 6 / 0 | Wave 4（RC-4 世代交代）で generated 後継の実体化と**同一トランザクション**で `.ai/_machine/archive/` へ退避。先行移動しない |

### 4.4 3 段階移行計画（今は設計のみ・ファイル移動は実施しない）

**Stage 1 — 参照ゼロ〜LOW の安全移動 + 案内板**（リスク: 極小）
- 対象: SUPERVISOR_REVIEW / LEARNED+LEARNINGS / APPROVALS / OS / BACKUPS / INTEGRITY / TASKS.yaml.bak.*（計 refs ≤ 3 each）
- `.ai/_machine/` と `.ai/_machine/README.md`（「ここは機械用。人間用は `.ai/` 直下」）を作成、`.ai/README.md` に分離の案内板を新設
- LOW でも参照が 1–3 件あるもの（APPROVALS/OS/BACKUPS/INTEGRITY）は移動と同時に参照行を書換（少数なので symlink 不要）
- 検証: `tests/kernel/run-kernel-tests.sh` green + 旧パスへの grep がゼロ + セッション bootstrap 正常

**Stage 2 — シンボリックリンク併用で MED 移動**（リスク: 中）
- 対象: SCHEDULER / sessions / events / METRICS / leases / REVIEW（refs 6–18）+ `.ai/plans` の kernel 定数を稼働前に `_machine/plans` へ変更
- 実体を `_machine/` へ移し、旧パスに**シンボリックリンクを残す**ことで全既存参照を無修正で生かす → 動作確認後、参照を新パスへ順次書換
- 注意: (1) events/leases は kernel チェーン・hook が触るため、移動前後で kernel テスト + ライブ hook シミュレーション必須 (2) symlink は git tracked になるため windows-wsl クローンでの挙動を 1 ケース検証 (3) Activity Ledger bridge（`scripts/activity/` — **別ワークフロー所有、本計画からは触らない**）が `.ai/events/` を読むため、bridge 側の追随は当該ワークフロー完了後に調整タスクとして切る
- 検証: kernel テスト + イベント追記 1 件の実発火確認（RC-3 の done 定義）+ symlink 経由/直接の両パス読み書き一致

**Stage 3 — 参照書換と完全移行**（リスク: 高・kernel 編集を含む）
- 対象: artifacts(統合) / queue / INTELLIGENCE / EVOLUTION / CODEX(refs=90, policy_core hardcode)
- ディレクトリごとに 1 タスク（lease + worktree + integrator 経由）で「全参照書換 → 実体移動 → 旧パス symlink 削除」を実施。CODEX は policy_core.py:101-102 の書換 = kernel 変更プロセス（Owner 承認 + kernel テスト + kernel-mode バージョン記録）
- manifest（生成化後）・/org-import/org-publish のパス表もここで追随
- Stage 2 の symlink をすべて撤去し、旧パス参照 grep ゼロを CI チェック化（再発防止）
- 検証: kernel テスト + publish dry-run + import を別ディレクトリで実通し（約束 (a) の検証を兼ねる）

**順序の前提**: フォルダ移行は Wave 3（§5）。Wave 1/2（配線・配布の修復）より先に動かすと参照書換が二重作業になるため、**先に参照の総量を減らしてから動かす**。

---

## 5. 実行ロードマップ — 4 Waves

監査の推奨着手順序（ISS-001/002 → ISS-009/011 → ISS-003/004/005 → RC-3 群）を Wave に編成する。

### Wave 1 — 進行中 fix（信号回復と正規パスの文書化）: 即時
**目的**: 「kernel と指示書の矛盾」と「eval の信号喪失」を止血する。以後の全修正の検証基盤を作る。

| タスク | 対応 ISS | 内容 |
|---|---|---|
| W1-1 | ISS-001/002 (RC-1) | CLAUDE.md / manager.md / org-tick.md / project-flow.md / plan-sync.md / AGENTS.md の台帳更新・コミット指示を org-tools（update-task.py / append-event.py / append-decision / integrator-commit.sh / acquire-lease.sh）参照に書換。Bash 直書きバイパス（`cat >>` / sed -i / heredoc）を policy_core の Bash チェックへ追加 |
| W1-2 | ISS-002 | 未コミット 105 件を integrator 経由で統合コミット（warn 降格が必要な invariant は文書化完了までの時限措置として記録） |
| W1-3 | ISS-009/011 (RC-5) | check-schema.sh enum に cancelled/superseded 追加・org-evolve を baseline 差分判定へ・report.py に `--profile-path` 追加で fixture/本番メモリ分離・偽 fact 4 件 retire |
| W1-4 | ISS-010/018/031 | DASHBOARD eval 表示を実測自動化、org-tick Step 5 の終了提案テンプレ削除（session-management と同一ロジック化）、performance.md の矛盾テーブル修正 |
| W1-5 | — | Activity Ledger T-OS-482/483 完遂（別ワークフロー進行中 — 本計画からは触らず、完了確認のみ） |

- **リスク**: W1-1 は指示ファイル広範囲書換 → rule 間矛盾の一時増加。grep 総当たりチェックリストを Work Order に添付して緩和
- **検証**: eval run-all.sh が「説明可能な結果」を返す（red なら理由が ISS に対応）/ ライブ hook シミュレーションで正規パス案内が出る / 統合コミット後 `git status` クリーン

### Wave 2 — manifest / 配布モデル再建: Wave 1 完了後
**目的**: 約束 (a)。配布層を「生成 + 検証」に作り替え、CI を green に戻す。
**前提: ISS-005 の Owner 判断（§6）が必要** — public 直開発 or private 復帰の決定なしに publish パイプラインの設計が確定できない。

| タスク | 対応 ISS | 内容 |
|---|---|---|
| W2-1 | ISS-003/004 | manifest から eval-loop 死参照除去・kill 判定反映 → 公開 CI green 化（最小止血） |
| W2-2 | ISS-005 | **Owner 判断の実装**: (a) 公開直開発なら sessions/ORDERS/*.bak の gitignore + 履歴除去 + org-publish 廃止、(b) キュレーション復帰なら origin private 化 + 公開側 1-commit/release 再構築 |
| W2-3 | RC-2 | manifest 生成化: ファイルタグ + 依存閉包リゾルバ + 3 検証テスト（実体存在/参照閉包/kill 同期）を CI 必須化 |
| W2-4 | ISS-006/007/029 | import core セットに rules/agents/hooks/settings/依存 scripts の閉包を含める（または import-lite CLAUDE.md 分離）。別ディレクトリへの import 実通しを受入テスト化 |

- **リスク**: 履歴除去（W2-2a の場合）は不可逆 → Owner 承認 + バックアップ必須。閉包自動解決は過剰配布の恐れ → dev タグの明示除外リストで制御
- **検証**: 公開 CI green / クリーンな別リポジトリへ import → セッション起動 → kernel deny が正しく作動（約束 (a) の実地確認）

### Wave 3 — フォルダ移行（§4 の Stage 1→2→3）: Wave 2 完了後
**目的**: Owner 要望「人間用と機械用の分離」を、参照書換が一巡した安定状態で実施。

- タスク: Stage 1（LOW 一括 + README 案内板）→ Stage 2（MED + symlink + plans 定数先行変更）→ Stage 3（HIGH 書換 + kernel 編集 + symlink 撤去 + 旧パス grep ゼロの CI 化）
- **リスク**: CODEX(90 refs)/EVOLUTION(43 refs) の書換漏れ → ディレクトリ単位 1 タスク + grep ゼロ確認を acceptance に。windows-wsl の symlink 挙動 → Stage 2 で 1 ケース検証
- **検証**: 各 Stage で kernel テスト + イベント実発火 + publish/import dry-run。Stage 3 完了で `.ai/` 直下に機械ディレクトリが残っていないこと

### Wave 4 — RC-3 配線完遂 + RC-4 台帳世代交代完遂: Wave 3 と並走可（フォルダ非依存分から）
**目的**: 約束 (b)(c) の恒久化。「作ったのに動いていない」機構をすべて本番経路に接続し、台帳の世代交代を閉じる。

| タスク | 対応 ISS | 内容 |
|---|---|---|
| W4-1 | ISS-013/014 (RC-3) | check-task-done.py を update-task.py の done 遷移に配線・integrator 成功時 CommitIntegrated 発行・VerificationPassed 発行元実装・T-OS-470〜472 の done を再検証 |
| W4-2 | ISS-015 | イベント 4 系統を append-event.py に統一（lease/integrator の直書き廃止・`\|\| true` 削除） |
| W4-3 | ISS-008/012/020/026/028 | SessionStart 検証 hook 登録 + 誤パス修正、daily-health-check と eval の scheduler 配線（出力が Owner に届くまで）、未実装 invariant 3 件の実装 or 設定面からの削除、update-active-graph.sh 実装 |
| W4-4 | ISS-017/027 (RC-4) | orgos.sqlite / TASKS.generated.yaml / DASHBOARD.generated.md を実体化 → tick/SessionStart で再生成 → 旧 STATUS/RUN_LOG/RUNTIME を `_machine/archive/` へ退避（**実体化と退避を同一タスク群で**）。stage の生成元を CONTROL 1 箇所に統一 |
| W4-5 | RC-3 恒久化 | Work Order acceptance テンプレートに「配線先 + 本番発火証拠（イベント ID）」を必須項目として追加 |

- **リスク**: 生成系の一斉切替で一時的に表示が欠ける → 旧台帳 archive は生成系の 1 週間安定稼働後
- **検証**: Evidence-Gated Done が実タスクで 1 回「正しく block」してから「正しく pass」する E2E / `/org-journal` に当日の全 mutation がイベントとして現れる / DASHBOARD が生成のみで最新

---

## 6. Owner 判断が必要な項目

現時点で **ISS-005 の 1 件のみ**。それ以外の 30 件は Manager 権限内で修正可能（kernel 編集を伴うものは個別に承認フローへ）。

### ISS-005: public リポジトリに dev ツリー全体が公開済み — 配布モデルをどちらに一本化するか

**現状（平易に）**: OrgOS は本来「開発用の private リポジトリから、厳選したファイルだけを public リポジトリへ書き出す」二段構えの設計でした。ところが現在、開発リポジトリそのもの（`origin = Yokotani-Dev/OrgOS`）が **public** になっており、`.ai/` の台帳 438 ファイル（過去のセッション記録・Codex への作業指示書・バックアップファイルを含む）と開発コミット 109 件が、そのまま誰でも見られる状態で公開されています。この切替の決定記録はありません。**実際のパスワードや API キーの混入は監査で未検出**（テスト用のダミー鍵のみ）ですが、「何を公開するか選ぶ」という仕組み自体が機能していない状態です。

**選択肢 (a): 公開直開発を正式採用する（いまの状態を「仕様」にする）**
- やること: セッション記録・作業指示書・バックアップ類を gitignore + **git 履歴からも除去**（履歴書換は不可逆操作）。/org-publish と manifest の「公開用の選別」機能は廃止し、公開していい形で開発する規律に切り替える
- 利点: 配布パイプラインの維持コストがゼロになる。リポジトリが 1 つで済み、CI も 1 系統。OSS として人に見せやすい
- 欠点・リスク: **「公開してよいか」を毎回の作業で意識する必要が恒久化**する。Owner の思考メモ・ビジネス文脈・他プロジェクト名などが今後うっかり公開される構造的リスクが残る（kernel で完全には防げない）。一度公開された過去履歴は除去しても第三者のクローンには残り得る
- 向いているケース: OrgOS を OSS プロダクトとして育てる意思がある場合

**選択肢 (b): private 復帰 + キュレーション公開を再建する（元の設計に戻す）**
- やること: `Yokotani-Dev/OrgOS` を private に戻し、公開側リポジトリを「リリースごとに 1 コミット」で再構築。Wave 2 の manifest 生成化・検証 CI とセットで publish パイプラインを復旧
- 利点: **開発中の思考・台帳・指示書が構造的に非公開**になり、何も気にせず台帳に書ける（Chief of Staff としての記録の率直さを守れる）。公開物は常に検証済みの閉包セットのみ
- 欠点・リスク: publish パイプラインの維持コスト（ただし Wave 2 の生成 + CI 検証でほぼ自動化）。公開側の履歴がすでに dev 全量で汚染されているため、公開リポジトリの作り直し（既存 star/fork があれば影響）が必要
- 向いているケース: OrgOS を当面「Owner の個人参謀 + 限定配布」として運用する場合

**Manager 推奨（draft 段階の仮置き）**: **(b)**。理由: 約束 (b)「すべての活動が 1 つのジャーナルに残る」は、記録が率直であるほど価値が出る。公開前提の自己検閲は参謀の記録品質を下げる。OSS 化はキュレーション公開の延長でいつでも再判断できるが、(a) を選んだ後の「公開済み履歴」は取り消せない（不可逆性の非対称）。

**判断の形式**: OWNER_INBOX 経由で (a)/(b) の選択を記録 → DECISIONS.md に PLAN-UPDATE として登録（append-decision ツール経由）→ Wave 2 の W2-2 が起動。

---

## 付録: 参照カウントの再現方法

```bash
# 対象: 移行候補ディレクトリごとの参照行数・ファイル数（2026-06-10 実測）
grep -r --include="*.sh" --include="*.py" --include="*.json" \
     --include="*.yaml" --include="*.yml" --include="*.md" \
     -F "<対象パス>" scripts/ .claude/ tests/ .github/ \
     .orgos-manifest.yaml CLAUDE.md AGENTS.md | wc -l
```

注: `.ai/` 内部の相互参照・docs/ は移行時の追加確認対象（本表は実行系のみ）。kernel hooks 内の参照は別途 `grep -n "\.ai/" .claude/hooks/*.py` で確認済み（CODEX/ORDERS・plans・PROTECTED_STATE_FILES・sessions・leases）。
