# REPO_LAYOUT_V1 — OrgOS リポジトリ全体のフォルダ構成簡素化設計

> status: **draft**（Owner 確認で confirmed へ昇格）
> 作成: 2026-06-13 / 根拠データ: 同日 grep 実測（対象: `.claude/ tests/ scripts/ .github/ .githooks/ .orgos-manifest.yaml CLAUDE.md AGENTS.md README.md ORGOS_QUICKSTART.md`）
> Owner 要望（原文）: **「フォルダ構成をとにかく明瞭にしてほしい。.ai の中だけではなく、orgOS 全体を見直してくれ」**

## 0. 前提 — ORGOS_TOBE_V3 §4 との合成

`.ai/` 内部の再編（人間用 = `.ai/` 直下 / 機械用 = `.ai/_machine/`）は **ORGOS_TOBE_V3.md §4 が SSOT** であり、並行ワークフローが実施中（`.ai/_machine/` は既に存在することを確認済み）。**本設計は `.ai/` の内部を一切再設計しない**。本設計のスコープは「`.ai/` の外側」= ルート直下のファイル群・`scripts/`・`docs/`・`tests/` であり、TOBE_V3 §4 と同じ原則（人間が開く場所と機械が触る場所の分離、参照実測に基づくリスク判定、kernel write path 経由の移行）をリポジトリ全体に外挿する。

両計画の接触点は **`.orgos-manifest.yaml` のみ**（§4 Stage 3 と本計画 R4 が両方 manifest を編集する）。それ以外の対象パスは完全に素である（disjoint）ため、実行順の依存は manifest 編集の 1 点に集約される（→ §5 実行計画）。

---

## 1. トップレベル棚卸し（全エントリ・実測根拠つき）

2026-06-13 時点のルート 22 エントリ（`.git` 含む）。「固定」= 慣習・ハーネス・CI が位置を規定しており動かせない。

| エントリ | 正体 | 誰が消費するか | 位置 | 判定 |
|---|---|---|---|---|
| `CLAUDE.md` | Manager 指示書 | Claude Code ハーネス（起動時自動読込） | **固定**（ハーネス規約） | 残す |
| `AGENTS.md` | Codex/agent 指示書 | Codex CLI（規約パス） | **固定** | 残す |
| `README.md` | リポジトリ入口 | 人間 / GitHub | **固定** | 残す |
| `ORGOS_QUICKSTART.md` | 導入ガイド | 人間。manifest publish (L65) + README L110 + org-publish.md L144 が参照 | 可動（要 3 ファイル編集） | **残す**（入口文書はルートが慣習。移動は編集 3 件に対し明瞭化ゼロ） |
| `requirements.md` | **v0.3 時代の歴史的仕様書**（冒頭に「[歴史的文書]…実装と乖離」と自己申告。38KB、最終コミット 2026-01-30） | ほぼ誰も読まない。参照 4 行のみ（manager.md ×1 / org-admin.md ×2 / ORGOS_QUICKSTART.md ×1） | 可動 | **`docs/archive/` へ移動** |
| `docs/` | `kernel-v2/dogfood.md` + `dogfood-checklist.md` の 2 ファイルのみ | 人間。kernel-write-path.md ルールが 2 箇所参照。tests の `docs/kernel-v2/` はフィクスチャ文字列（実体不要） | 可動だが移動不要 | **残す = 人間用ドキュメントの正規置場に昇格**（archive を吸収） |
| `outputs/` | 成果物置場（README + 日付別 3 ディレクトリ） | 人間 + agents。`.claude/rules/output-management.md` が配置先として規定（参照 4 ファイル） | **ルール固定** | 残す |
| `scripts/` | 21 サブディレクトリ / 129 ファイル — **混乱の主因** | kernel hooks / harness / CI / tests | 内部再編 | **§3 で 21→13+`_archive` に統合** |
| `tests/` | `kernel/`（37 ファイル, run-kernel-tests.sh）+ `activity/`（6） | 回帰ゲート（kernel write path の受入条件） | 残す | 残す |
| `.ai/` | 台帳（並行再編中） | 全員 | TOBE_V3 §4 が SSOT | **触らない** |
| `.claude/` | rules/agents/commands/skills/evals/hooks/schemas/state | ハーネス（レイアウト規約）+ kernel | **固定**（ハーネス規約） | 残す |
| `.github/` | CI 3 本（test.yaml = manifest 存在検証 / release.yaml / orgos-scheduler.yml → `scripts/scheduler/run-detection.sh`） | CI | **固定** | 残す |
| `.githooks/` | git hooks | git | **固定** | 残す |
| `.gitignore` / `.pre-commit-config.yaml` | VCS 設定 | git / pre-commit | **固定** | 残す |
| `.orgos-manifest.yaml` | 配布 SSOT。org-import/publish/release がリテラルパスで参照、CI test.yaml が publish/core の実在を検証 | CI + commands | **固定**（パス変更 = commands 4 ファイル + CI 改修） | 残す |
| `.worktrees/` | Codex 隔離 worktree（gitignored、44 個滞留） | kernel（run-in-worktree.sh）+ settings.json additionalDirectories | 固定（運用中） | 残す。**44 個の滞留掃除は運用タスクであり本設計のスコープ外**（artifact-manifest 検証後 cleanup の既存機構に従う） |
| `.collaborator/` | `replay-cache.json` 1 ファイルのみ（2026-03-28 で停止、gitignored、untracked、参照ゼロ — gitignore の 1 行を除く） | 死んだローカルキャッシュ | — | **ディスクから削除** |
| `.DS_Store`（ルート + outputs/） | macOS ジャンク（gitignored、untracked 確認済み） | — | — | **削除** |
| `.git/` | VCS | git | 固定 | — |

---

## 2. 目標トップレベル像

可視エントリ **9 → 8**（目標 ≤10 を達成）。各行に「誰が開くか」を付す。

```
OrgOS/
├── README.md               # 人間（初見者）— リポジトリの入口
├── ORGOS_QUICKSTART.md     # 人間（導入者）— /org-import 後の最初の 1 枚
├── CLAUDE.md               # ハーネス（Manager 指示書。人間は編集時のみ）
├── AGENTS.md               # Codex CLI（worker 指示書。人間は編集時のみ）
├── docs/                   # 人間（開発者）— kernel 運用ログ + 歴史的文書の唯一の置場
│   ├── kernel-v2/          #   dogfood 実運用ログ（kernel-write-path.md が参照）
│   └── archive/            #   requirements-v0.3.md（旧仕様書の退避先・新設）
├── outputs/                # 人間（Owner）— 成果物。output-management.md がルール固定
├── scripts/                # 機械 + 開発者 — 13 の生きたサブ系統 + _archive（§3）
├── tests/                  # CI/開発者 — kernel/ + activity/ 回帰ゲート
│
└── （不可視・固定）.ai/  .claude/  .github/  .githooks/  .gitignore
    .orgos-manifest.yaml  .pre-commit-config.yaml  .worktrees/
```

意味づけの一行ルール（README に転記する案内板）:
**「ルートの可視物 = 人間の入口 4 文書 + 人間の置場 3 ディレクトリ（docs/outputs/tests）+ 機械の道具箱 1（scripts）。実行時データはすべて不可視領域（.ai/_machine, .claude/state, .worktrees）にある」**

---

## 3. scripts/ 統合案 — 21 ディレクトリ → 13 + `_archive/`

参照実測（2026-06-13。ext = `.claude/ tests/ .github/ manifest/ ルート文書` からの行数(ファイル数)、cross = 他 scripts からの行数）:

### 3.1 KEEP — 生きている 13 系統（証拠つき）

| dir | files | ext refs | 消費者 | 一行目的 | 判定理由 |
|---|---|---|---|---|---|
| `org/` | 29 | **258 (41)** | kernel hook（SessionStart.sh）、rules 40 行、tests 191 行、manifest 30 行 | kernel-v2 org-tools（台帳 mutation の唯一の正規経路） | **KEEP・改名禁止**。258 参照の書換リスクは明瞭化益を桁違いに超える。「org という名が汎用的すぎる」不満は README 1 枚（`scripts/org/README.md` = 「kernel write path の道具。台帳を触る時はここだけ」）で解消する |
| `codex/` | 5 | 44 (10) | tests 31 行、commands、manifest | Codex worktree 隔離ランナー | KEEP |
| `activity/` | 5 | 27 (9) | **hooks 3 行**、commands 9 行、manifest 10 行 | Activity Ledger（~/.orgos/activity）bridge/journal。**別ワークフロー所有** | KEEP・触らない |
| `session/` | 6 | 27 (8) | **hook 1 行**、rules 7 行、manifest 12 行 | session bootstrap / bind-request | KEEP |
| `capabilities/` | 12 | 24 (4) | manifest 19 行、commands 2 行 | capability probe（CAPABILITIES.yaml 再生成） | KEEP |
| `platform/` | 2 | 21 (5) | commands 16 行（org-tick 等の platform 分岐） | OS 判定 + codex wrapper | KEEP |
| `memory/` | 4 | 15 (4) | rules 6 行、manifest 6 行、pre-commit | memory lint / secret scanner | KEEP（`security/common.sh` を吸収 → 5 ファイル） |
| `eval/` | 6 | 9 (2) | `.claude/evals/manager-quality/` のみ | manager-quality eval のフィクスチャハーネス | KEEP（§4 の evals 統合は将来課題として保留） |
| `evolution/` | 14 | 1 + scheduler 経由 | `scheduler/run-detection.sh` が detect/synthesize/apply を呼ぶ → CI cron | Self-Evolution パイプライン本体 | KEEP（`evolve/` を吸収 → 17 ファイル） |
| `scheduler/` | 4 | **1 = `.github/workflows/orgos-scheduler.yml` L37** | CI cron | Always-On scheduler 入口 | KEEP（CI 参照あり。移動益なし） |
| `inbox/` | 5 | cross 4（evolution/peer-review.sh が add-decision.sh を呼ぶ） | evolution | OWNER_INBOX.md 操作ツール（inbox.py 23KB） | KEEP |
| `authority/` | 13 | 1（authority-layer.md の設計言及） | 手動 / T-OS-171〜173 の実装体 | autonomy level 判定エンジン | KEEP（配線は薄いが設計上の現役サブシステム。kernel への吸収判断は TOBE_V3 Wave 4 以降の別議題） |
| `git/` | 4 | live 0（`.claude/state/*.jsonl` 実行ログにのみ痕跡） | 手動 / parallel-session-policy Phase 3 | git 協調ロック（acquire-lock 等） | KEEP（parallel-session-policy.md の実装体。安全装置を「参照が薄い」だけで退役させない） |

### 3.2 MERGE — 統合 2 件

| 現在 | 統合先 | 根拠 | 必要編集 |
|---|---|---|---|
| `evolve/`（3 ファイル: daily-health-check.sh / generate-fix-task.sh / 統合メモ md） | `evolution/` | **名前がほぼ同一で二重系統に見える**のが混乱源。実体は同じ Self-Evolution 圏（TOBE_V3 W4-3 が daily-health-check の scheduler 配線を予定 = 統合先で配線する方が一貫） | `evolution/scanners/eval-scanner.sh` L152 の推奨文字列 1 行。live 参照ゼロ確認済み |
| `security/`（1 ファイル: common.sh = コンソール色付け shell ライブラリ） | `memory/common.sh` | **単一ファイル + 誤誘導する名前**（"security" の中身が色付けユーティリティ）。source 元は `memory/` の 3 スクリプトのみと実測 | memory 3 スクリプトの source 行、manifest 2 エントリ（L215/L399）、`tests/kernel/test-manifest-closure.sh` L200 のフィクスチャ行、`org-import.md` L138 のディレクトリ列挙 — 計 7 箇所 |

### 3.3 RETIRE — `scripts/_archive/` へ退避 6 件（全て inbound 参照 0 を実測確認）

`.claude/rules/_archive/` の既存パターンを踏襲し、削除でなく `_archive/` 移動（git mv）+ README 台帳で可逆に保つ。**`_archive/` は manifest に含めない**（rules/_archive と同じ扱い）。

| dir | files | 退役理由 | 残作業 |
|---|---|---|---|
| `dashboard/`（render.sh） | 2 | **後継あり**: kernel-v2 の `org/generate-dashboard.py`（test-dashboard-generator.sh でテスト済み）が DASHBOARD 生成の正規系。旧 Phase 2 世代 | なし（参照 0） |
| `tasks/`（archive-done.sh） | 2 | **後継あり**: `org/archive-tasks.py`（test-archive-tasks.sh でテスト済み） | `.ai/RUNBOOKS/archive-tasks.md` の 3 箇所を `scripts/org/archive-tasks.py` に書換（Runbook は古い方を指したまま = 現状が既に不整合） |
| `dna/` | 3 | `.ai/ORG_DNA.yaml` 登録簿の維持系。commands/rules/skills からの参照 0 = 未配線 MVP | なし |
| `intel/` | 4 | 週次 Intelligence MVP。データ側 `.ai/INTELLIGENCE` には参照があるがパイプライン本体への参照 0 | なし |
| `journeys/` | 3 | JOURNEYS.yaml init/validate。journey gate は commands 側に実装済みで本系統は未配線 | なし |
| `integrity/` | 2 | scan-stale.sh 単発レポータ。参照 0 | なし |

`_archive/README.md` に「dir / 退役日 / 理由 / 後継 / 復活条件 / 削除判断日（+90 日）」の表を置く。90 日後に復活実績がなければ削除タスクを切る。

**結果: 可視サブディレクトリ 21 → 13 + `_archive`。生きている系統だけが scripts/ 直下に並ぶ。**

---

## 4. tests/ と .claude/evals/ の重複 — 現状維持（記録のみ）

- `tests/` = 決定論的回帰（kernel write path の受入ゲート。run-kernel-tests.sh 37 本 + activity 6 本）
- `.claude/evals/` = 指示層の品質チェック。**org-tick L673 / org-evolve L70,257 がリテラルパスで run-all.sh を呼び、test-manifest-closure.sh が `.claude/evals/` 配下の実在をフィクスチャで検証**している
- 統合すると commands 2 ファイル + closure テスト + manifest の連鎖書換になり、TOBE_V3 Wave 1（W1-3 で evals 自体を修理中）と正面衝突する。**本設計では動かさない**。evals の信号が回復した後（Wave 1 完了後）に「実行系テストは tests/、宣言検証は evals」の境界文書化だけ行う

---

## 5. 実行計画 — 単一パス 6 ステップ（各ステップにテストゲート）

前提条件（着手ゲート）: ① `tests/kernel/run-kernel-tests.sh` green ② `test-manifest-closure.sh` green ③ `.ai/` 移行（TOBE_V3 Wave 3）の Stage 進行と独立だが、**R4 のみ manifest を編集するため、TOBE_V3 W2-3（manifest 生成化）が完了済みならタグ修正・未完了なら手書き修正と判断して着手**する。全ステップ kernel write path（lease + worktree + integrator）経由・1 ステップ = 1 タスク。

| # | 内容 | リスク | ゲート（pass しなければ revert） |
|---|---|---|---|
| **R0** | ジャンク除去: `.DS_Store` ×2 と `.collaborator/` をディスクから削除（全て untracked。コミット不要） | LOW | `git status` 差分ゼロ確認のみ |
| **R1** | `scripts/_archive/` 新設 + dashboard/dna/intel/journeys/integrity/tasks の 6 dir を git mv + `_archive/README.md` 台帳 + `.ai/RUNBOOKS/archive-tasks.md` 3 箇所書換 | LOW（全 dir 参照 0 実測） | kernel suite（特に test-archive-tasks.sh / test-dashboard-generator.sh が後継の健在を証明）+ `grep -rF 'scripts/(tasks|dashboard|dna|intel|journeys|integrity)/'` が `_archive` 外でゼロ |
| **R2** | `evolve/` → `evolution/` 統合（git mv 3 ファイル + eval-scanner.sh L152 の文字列 1 行） | LOW | kernel suite + `bash scripts/scheduler/run-detection.sh --dry-run` 正常終了 |
| **R3** | `security/common.sh` → `memory/common.sh`（git mv + source 行 3 + manifest 2 + closure テスト 1 + org-import.md 1 の計 7 編集） | **MED**（manifest + closure テスト同時変更） | `test-manifest-closure.sh` + CI test.yaml 相当の publish/core 実在チェックをローカル実行 + `pre-commit run --all-files` |
| **R4** | `requirements.md` → `docs/archive/requirements-v0.3.md`（git mv + 参照 4 行書換: manager.md / org-admin.md ×2 / ORGOS_QUICKSTART.md） | **MED**（`manager.md` 編集 = authority-layer の `requires_owner_approval`。**本設計の Owner confirm をもって承認とし、DECISIONS.md に OS-MUTATION 記録**） | `.claude/evals/check-refs.sh`（markdown リンク実在検証が移動漏れを機械検出）+ kernel suite |
| **R5** | 案内板: README.md に §2 の一行ルールとトップレベル表を追記。`docs/README.md` 新設（kernel-v2 / archive の案内） | LOW | check-refs.sh + evals run-all.sh |

完了条件（全体）: kernel suite green / manifest closure green / evals run-all が「説明可能な結果」/ 旧パス grep ゼロ / `git status` clean。
**`.ai/` 移行との衝突回避**: 本計画は `.ai/` 配下のパスを一切移動しない（R1 の RUNBOOKS 書換と R4 の DECISIONS 追記は通常の台帳更新）。TOBE_V3 Stage 1〜3 のどの時点で実行しても干渉しないが、manifest 二重編集を避けるため **R3 だけは TOBE_V3 Stage 3（CODEX 移動 = manifest 追随）と同一ウィンドウに重ねない**。

---

## 6. やらないこと（固定理由の明示）

| 対象 | 理由 |
|---|---|
| `CLAUDE.md` / `AGENTS.md` / `README.md` のルート位置 | ハーネス・Codex CLI・GitHub の規約パス |
| `.claude/` のレイアウト（rules/agents/commands/skills/evals/hooks/schemas/state） | Claude Code ハーネス規約 + kernel（policy_core/pretool_policy）がこの位置で動作 |
| `.github/` `.githooks/` `.gitignore` `.pre-commit-config.yaml` | ツール規約パス |
| `.orgos-manifest.yaml` のルート位置 | org-import/publish/release がリテラルパス参照 + CI test.yaml が直接 open |
| **`scripts/org/` の改名**（例: scripts/kernel-tools） | ext 258 行 / 41 ファイル（kernel hook・rules・tests・manifest 横断）。書換リスク・レビュー負荷が明瞭化益を大きく超える — 正直にコスト超過と判定。README 1 枚で目的を掲示する方が安全に同じ効果を得る |
| `outputs/` の移動・改名 | output-management.md ルールが配置先として固定 |
| `ORGOS_QUICKSTART.md` の docs/ 移動 | manifest publish + README + org-publish.md の 3 点編集に対し、入口文書をルートから消す = むしろ明瞭性低下 |
| `tests/` と `.claude/evals/` の統合 | §4 のとおり。Wave 1 の evals 修理と衝突するため保留 |
| `.worktrees/` の整理 | レイアウトでなく運用（cleanup 機構は kernel に実装済み）。滞留 44 件は別途運用タスク |
| `.ai/` 内部の一切 | ORGOS_TOBE_V3 §4 が SSOT。並行ワークフロー所有 |

---

## 7. 受け入れ基準（acceptance）

1. ルート可視エントリが 8 件（README / QUICKSTART / CLAUDE / AGENTS / docs / outputs / scripts / tests）である
2. `scripts/` 直下が 13 live dirs + `_archive/` であり、`_archive/README.md` に退役台帳がある
3. 旧パス（scripts/evolve, scripts/security, scripts/tasks, scripts/dashboard, scripts/dna, scripts/intel, scripts/journeys, scripts/integrity, ルート requirements.md）への参照が `_archive` 内と git 履歴を除きゼロ
4. `run-kernel-tests.sh` / `test-manifest-closure.sh` / `check-refs.sh` / `evals/run-all.sh` が R 実行前と同等以上の結果
5. DECISIONS.md に PLAN-UPDATE（本設計採択）と OS-MUTATION（manager.md 1 行書換）が記録されている
