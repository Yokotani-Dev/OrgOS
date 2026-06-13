# OrgOS WebConsole 変更履歴

このファイルは OrgOS WebConsole の各バージョンで何が変わったかを記録します。

---

## v2.0.1 (2026-06-13) — Post-release fixes

v2.0.0 後に残っていた品質課題を解消。利用者影響なし（内部品質・自己計測の改善）。

### 🔧 修正
- **integrator フロー欠陥 4 件 (T-OS-492)**: main 統合モード(`--allow-main`、`allow_main_mutation=true` 時のみ・偽装フラグ拒否) / `collect-artifacts.sh` の再帰スナップショット爆発(1.5GB/57k files)を抑制 / diff 5000 行 cap を設定可能化 / plan-contract 検証 diff をタスク宣言パスにスコープ
- **manager-quality eval 17/20 → 20/20 (T-OS-493)**: `CAPABILITIES.yaml` の common_operations 補完(MQ-007) + handoff packet fixture 完備(MQ-019/020)。`decision_trace_completeness` 9% → **100%**
- **RC-4 SQLite shadow 実体化 (T-OS-494)**: `.ai/orgos.sqlite` + generated views(TASKS/DASHBOARD/GLOSSARY.generated)を生成。SessionStart の checksum 警告を解消
- **互換層残リスク 2 件 (T-OS-498)**: 同月 events 衝突を `_from_legacy` ではなくマージし glob 可視性を維持 / `session_start_context.py` に legacy sessions フォールバック追加

### ✅ 検証
- 全 kernel test green (SUITE_EXIT=0) / `evals/run-all.sh` pass=8 fail=0 warn=1(既知の duplicate-content)

---

## v2.0.0 (2026-06-13) — Observability + Structural Clarity

### 🎯 Headline
全リポジトリの活動を 1 つのジャーナルに集約する **Central Activity Ledger** を導入。あわせて構造監査(31 確定課題)に基づき OrgOS の整合性を回復し、フォルダ構成を「人間が触る場所 / 機械の実行時データ」に二層化。既存リポジトリは後方互換層により安全に自動移行する。

### ✨ 追加 — Central Activity Ledger（横断実行ログ）
- `~/.orgos/activity/events-YYYYMM.jsonl`（追記専用・月次シャード）に全リポジトリの活動を集約
- `scripts/activity/log-event.sh`（writer・secret 自動マスキング）/ `journal.sh`（日次ダイジェスト）/ `bridge-kernel-events.sh`（既存 kernel イベントの冪等取込）
- `/org-journal` コマンド + stdio MCP サーバ `orgos-journal`（user スコープ・全プロジェクトから `journal_get`/`activity_search`/`activity_log`）
- orgos-dashboard に `/journal` 画面（日次ビュー、💭考えたこと / ⚙️実行したこと）
- SessionStart / Stop フックで自動記録

### 🔧 修正 — 構造監査 31 課題（5 根本原因）
- **ISS-001/002**: kernel 正規書込パスを `kernel-write-path.md` に文書化 + `append-decision.py` 新設 → 3 週間のコミット凍結を解消
- **ISS-009**: eval 信号回復（check-schema enum に cancelled/superseded、org-evolve を baseline 差分判定へ）
- **ISS-011**: memory 汚染除去（eval fixture facts を retire、`report.py --profile-path` で本番/fixture 分離）
- **ISS-010**: DASHBOARD の虚偽表示是正（実測値 + 監査リンク）
- **ISS-006/007/008**: manifest 依存閉包テスト、SessionStart checksum hook 配線
- 監査レポート: `.ai/AUDIT/AUDIT-2026-06-10-orgos-structural.md`

### 💥 BREAKING — フォルダ構成の二層化
- `.ai/` 直下 = 人間が読む台帳のみ。機械の実行時データ（events/leases/queue/sessions/codex/evolution/artifacts ほか 19 ディレクトリ）を **`.ai/_machine/`** へ移動
- `scripts/` を 21 → 13 ディレクトリ + `_archive/` に統合。ルート整理（`requirements.md` → `docs/archive/`、`.collaborator`/`.DS_Store` 削除）
- VSCode は `.vscode/settings.json` でエンジンルームを非表示、`README.md` に構成地図
- kernel パス定数（CODEX/leases/plans）を更新

### 🛡 後方互換 — 既存リポジトリ保護（T-OS-497）
- 冪等な `scripts/org/migrate-layout.sh`（SessionStart + `/org-import` 配線）で旧レイアウトを自動移行（状態分裂・データ喪失なし）
- dual-path リゾルバ（新パス→旧パス fallback）を安全網として配備
- `/org-publish` プリフライト: 互換層が manifest に無ければ配布中止（Iron Law）
- migration テスト 6 本を kernel suite に登録。全 kernel test green

## v1.0.0 (2026-05-20) — Production-Ready Kernel

### 🎯 Headline
GPT-5.5 Pro 8 週 migration plan 完走。Document-driven な OrgOS から **Mechanically-enforced Constitutional Kernel** へ進化。8 invariants が runtime で強制され、Plan Contract、Evidence-Gated Done、SQLite shadow、EVENTS.jsonl truth ledger により再現可能・監査可能な OS が完成。

### 追加 (Week 4 — SQLite Shadow)
- `.ai/orgos.sqlite` schema + init (`scripts/org/init-sqlite.py`)
- TASKS.yaml → SQLite import shadow (`scripts/org/import-tasks-yaml.py`)
- SQLite-backed task query (`list-tasks-sqlite.py` / `show-task.py`)
- DASHBOARD.generated.md from SQLite (`generate-dashboard.py`)

### 追加 (Week 5 — EVENTS.jsonl Truth Ledger)
- `.ai/events/` hash-chained JSONL event log (`scripts/org/append-event.py`)
- integrator-commit emits `CommitIntegrated` events
- collect-artifacts emits `ArtifactCollected` events
- acquire-lease / release-lease emit `LeaseAcquired` / `LeaseReleased` events
- Evidence-Gated Done (`check-task-done.py`): task done 移行に lease + artifact + commit event 証跡必須

### 追加 (Week 6 — Generated Views)
- TASKS.generated.yaml generator from SQLite
- Generated file checksum + manual-edit detection
- pretool deny direct edit of `*.generated.*` files
- SessionStart.sh checksum verifier (起動時に乖離検出)
- TASKS.yaml legacy sentinel header

### 追加 (Week 7 — Plan Contract)
- `.claude/schemas/plan-contract.v1.json` (`.plan.yaml` 用 JSON Schema)
- `/org-plan` generator (Work Order → `.ai/plans/<task>.plan.yaml`)
- **Invariant #8 PlanContractRequired**: 全 Edit/Write op に `.plan.yaml` 必須
- integrator-commit が plan + diff 一致を pre-commit 検証

### 追加 (Week 8 — Terminal Cleanup)
- Rule audit: 10 rules + 12 agents 分類 (kernel-superseded / SQLite-superseded / Manager-judgment-keep)
- `.claude/rules/_archive/`: kernel に取って代わられた 3 rules を物理移動
  (acceptance-pre-write / eval-loop / pre-implementation-risk-profile)
- Script consolidation audit (123 files, 0 backups, 全 referenced 存在)

### 8 Constitutional Invariants
| # | Invariant | 役割 |
|---|-----------|------|
| 1 | IntegratorOnlyCommit | Manager raw commit ブロック → integrator-commit.sh のみ |
| 2 | PerTaskWorktree | 並列 codex 衝突防止 |
| 3 | ProtectedBranchNoTouch | main/master/develop checkout/merge 直接禁止 |
| 4 | LeaseBeforeWrite | lease なき write 禁止 |
| 5 | StateMutationViaOrgTool | 保護台帳 + Generated files 直接編集禁止 |
| 6 | DurableArtifactBeforeCleanup | manifest なき cleanup 禁止 |
| 7 | OwnerApprovalForIrreversibleOps | 不可逆操作の Owner gate |
| **8** | **PlanContractRequired** (NEW) | `.plan.yaml` なき Edit/Write/commit 禁止 |

### 改善
- `update-task.py` が legacy sentinel header (`# ORGOS-LEGACY`) を保持
- `collect-artifacts.sh` / `integrator-commit.sh` / `acquire-lease.sh` / `release-lease.sh` が `append-event.py` CLI に対応

### Deferred (Owner-direct required)
- T-OS-458: `set-kernel-mode.sh` enum 拡張 (PlanContractRequired を flip 可能に)
- T-OS-462: CLAUDE.md slim down (kernel file は Owner 直接編集要)

### テスト
- kernel tests: 117 件 pass / 0 failures
- 14 新規 test スクリプト追加 (SQLite / events / plan-contract / checksum / sessionstart / rule-archive / script-consolidation)

---

## v0.24.0 (2026-05-10)

Pre-Implementation Quality + Self-Evolution Engine + Concurrent Safety + SELFREVIEW-002.

M-PHASE-6 (Quality Contract / Journey-First / Domain Constraint / Pre-Risk Profile / Acceptance Pre-Write / 4 Specialist subagents)。Phase 2 complete (DNA / Synthesis / Validation / Application engine / Capability Probe / Intelligence pipeline / Always-On scheduler / Evolution Dashboard)。M-PHASE-7 (parallel-session-policy / branch consistency check / Codex worktree wrapper / git lock)。

詳細は `.ai/VERSION.yaml` 参照。

---

## v0.23.0 (2026-04-19) — Chief of Staff Edition

### 🎯 Headline
ChatGPT Pro レビューを経て ToBe v2「Chief of Staff モデル」を完全実装。Manager Quality Eval が baseline 0/20 → 19-20/20 pass へ構造的改善。Owner の「OrgOS は気が利かない外注」という症状を解消し、「検証可能な制御システム」へ進化。

### 追加 (Phase 1-4 Core)
- **Manager Quality Eval**: 20 regression cases + 6 metrics + regression detection + trend 計算
- **Safe Memory** (`.ai/USER_PROFILE.yaml`): fact registry + secret pointer 方式、6 操作 Iron Law
- **Capability Preflight** (`.ai/CAPABILITIES.yaml`): 58 capability tool manifest、MCP 互換
- **Request Intake State Machine** (`request-intake-loop.md`): 10 ステップ Iron Law + deterministic reduction rules
- **Handoff Packet** (schema + protocol): 全 subagent 標準化、trace 階層化、memory_updates quarantine

### 追加 (Phase 5 Authority Layer)
- **authority-layer.md** + 3 schemas (autonomy / approval-workflow / role-matrix)
- **scripts/authority/** 11 scripts: OS Mutation Protocol / RBAC / Approval Workflow engine

### 追加 (Owner Feedback 対応)
- **Session Bootstrap**: SessionStart hook で新規チャット自動 OrgOS モード
- **Cross-Session Consistency**: 単発依頼を進行中タスクに自動バインド（日本語対応）
- **Proactive Manager**: Owner preference を反映した能動提案
- **Self-Improvement Loop**: 日次自動ヘルスチェック + 退行時の自動修正タスク生成

### 追加 (Awareness / Safety)
- **GOALS.yaml**: Vision → Milestone → Project → Task の 4 階層 Work Graph
- **coherence-mode.md**: Silent / Brief / Full Bind の deterministic rubric
- **memory-lifecycle.md**: Memory 6 操作 Iron Law
- **Memory lint**: check-no-plain-secrets / normalize-lint / promote-lint + pre-commit hooks

### 改善
- **CLAUDE.md**: 最高位 Iron Law として request-intake-loop を明記
- **manager.md**: Tick フローを 10 ステップに再編成、未完了時応答停止の Iron Law
- **14 agents**: Iron Law セクション追加（3/15 → 13/15）、Handoff Packet 義務化

### メトリクス (baseline → 最終)
| 指標 | Before | After |
|------|--------|-------|
| repeated_question_rate | 100% | 0.0% ✅ |
| context_miss_rate | 100% | 0.0% ✅ |
| unnecessary_owner_question_rate | 100% | 0.0% ✅ |
| capability_reuse_rate | 0% | 100.0% ✅ |
| owner_delegation_burden | 100% | 5% ✅ |
| decision_trace_completeness | 0% | 100.0% ✅ |

### 参考
- Pro レビュー SSOT: `.ai/DESIGN/CHATGPT_PRO_REVIEW_2026-04-18.md`
- SELFREVIEW-001: 4 並列 Explore による MAOPAS-E 7 本柱評価
- DECISIONS.md: PLAN-UPDATE-016 〜 018、MQ-BASELINE/PROGRESS/COMPLETE/FINAL

---

## v0.22.0 (2026-04-01)

### 追加
- **自律走行モード**: Manager が「提案→承認待ち」から「実行→報告」に変更。人間の介入を最小化
- **ビジネス文脈ヒアリング**: `/org-brief` にペルソナ・動機・参照・成功基準の必須質問を追加
- **参照・競合調査**: DESIGN フェーズで類似サービス調査を必須化（REFERENCES.md テンプレート）
- **MVP→確認→拡張サイクル**: 核となる機能を先に見せて方向確認するインクリメンタルデリバリー
- **外部AIリソーススキャン**: `org-evolve` が GitHub trending / Claude Code コミュニティから革新的パターンを自動発見・取り込み
- **Runbook 機構**: ルーティンワークの手順化・品質安定化（`.ai/RUNBOOKS/`）
- **Iron Law（ファイル衝突防止）**: `allowed_paths` が重複するタスクの並列実行を禁止

### 改善
- **セッション管理簡素化**: 95%超の強制終了のみ残し、途中終了提案を廃止
- **rules/patterns.md 圧縮**: 430行→28行の軽量インデックスに
- **次ステップ案内**: 選択肢提示から自律実行報告へ変更
- **AI ドリブン開発**: Manager の技術判断自律性を明確化

---

## v0.21.0 (2026-03-30)

### 追加
- **スキル 9ファイル新規作成**: web-design-guidelines, refactoring-patterns, requirements-specification, task-breakdown, deployment-planning, security(rules→skills移動), testing(同), review-criteria(同), literacy-reference
- **合理化防止ルール**: `rationalization-prevention.md` - Iron Law（鉄則）、言い訳テーブル、Red Flags チェックリスト（obra/superpowers ベース）
- **Eval 4スクリプト追加**: check-skill-compliance.sh, check-consistency.sh, check-duplicates.sh, check-refs.sh
- **`/org-evolve` コマンド**: OrgOS 自律改善ループ
- **`/org-dashboard` コマンド**: マルチプロジェクト Dashboard 連携（~/.orgos/projects.yaml 登録）
- **`/org-goals` コマンド**: ゴール階層の表示・編集
- **Dashboard 設計**: .ai/DESIGN/DASHBOARD_ARCHITECTURE.md

### 改善
- **二段階レビュー**: org-reviewer を Stage 1（仕様適合）→ Stage 2（設計品質）に再構築
- **サブエージェント報告検証**: agent-coordination にレポート検証プロトコル追加（DONE/DONE_WITH_CONCERNS/NEEDS_CONTEXT/BLOCKED）
- **Iron Law 追加**: testing, security, review-criteria, requirements-specification, task-breakdown の5スキルに Iron Law セクション追加
- **CSO 原則**: CLAUDE.md にスキル description の記述ルール追加
- **スキル強化**: frontend-patterns(+Next.js最適化,React19), backend-patterns(+SQL最適化), security(+CodeQL), testing(+Playwright E2E)
- **コンテキスト最適化**: rules/ から skills/ へ3ファイル移動、CLAUDE.md圧縮、台帳統廃合（DASHBOARD/STATUS/RUN_LOG役割再定義）
- **エージェント責務明確化**: reviewer（設計専任）, planner（architect委任）, scribe（doc-updater委任トリガー）
- **ルール二重定義解消**: performance, ai-driven, next-step, plan-sync, date-awareness の重複排除
- **manifest 更新**: 新規スキル・ルール・eval を publish 対象に追加

### 内部
- **RUNTIME.yaml 新設**: CONTROL.yaml からランタイム状態を分離
- **TASKS_ARCHIVE.yaml 新設**: done タスクのアーカイブ先

---

## v0.20.0 (2026-03-23)

### 追加
- **`/issue` コマンド**: 任意のリポジトリから OrgOS 開発リポジトリに issue を起票
  - バグ報告・機能要望・質問を対話形式でヒアリング
  - OrgOS バージョン・プロジェクトステージを自動収集
  - `gh issue create --repo Yokotani-Dev/OrgOS` で直接起票
  - ラベル（bug / enhancement / question）を自動付与

---

## v0.19.0 (2026-02-13)

### 追加
- **org-tick オートコンティニュー** (T-OS-023): Tick 完了後に条件を満たせば自動的に次の Tick を連続実行
  - batch/manual モードで Owner に毎回返さず連続処理
  - 最大 10 Tick/回、コンテキスト 80% で強制停止
- **全作業 TASKS.yaml 登録必須化** (T-OS-024): ad-hoc 実行を禁止、全作業を TASKS.yaml 経由で管理
  - 割り込みタスク受付フロー追加（allowed_paths 衝突チェック）
  - org-tick Step 2.2「新規依頼のタスク化」を追加

### 改善
- **`/org-start` public OrgOS 自動切断** (T-OS-025): public OrgOS リポジトリをクローンした場合、選択肢を出さず自動で origin を切断
  - FlowA Step 1 に Pattern B（`/OrgOS` URL 判定）を追加
  - Step 3 テンプレートに `is_orgos_dev: false` を明示

### 内部
- **Intelligence パイプライン品質修正** (T-INT-007〜010): orgos-intelligence リポジトリで4件の品質改善
  - T-INT-007: Gemini スコアリング JSON 抽出強化 + OIP 生成改善
  - T-INT-008: HN フィルタリング精度改善（単語境界マッチ + ストップワード除外）
  - T-INT-009: HTML タグ残留修正（stripHtml 2パス処理）
  - T-INT-010: 重複排除強化（URL 正規化 + 単語 Jaccard 0.5）
- **Intelligence Phase 5-6** (T-INT-005〜006): ロールバック機構、Kernel 保護、ソース管理 Slack フロー

---

## v0.18.0 (2026-02-13)

### 追加
- **OS Evals 基盤**: Level 1 自動評価スクリプト群を追加（`.claude/evals/`）
  - `check-schema.sh`: YAML/manifest スキーマ検証
  - `check-kernel-boundary.sh`: Kernel 境界チェック
  - `check-agent-defs.sh`: エージェント定義整合性チェック
  - `check-oip-format.sh`: OIP フォーマット検証
  - `check-security.sh`: セキュリティスキャン
  - `run-all.sh`: 全チェック一括実行
- **Intelligence ディレクトリ**: 運用データ収集の基盤構造を追加（`.ai/INTELLIGENCE/`）

### 修正
- `/org-start` で public clone 時に OrgOS 開発検出が誤発動する問題を修正

---

## v0.17.0 (2026-02-13)

### 改善
- **Codex デフォルトモデル更新**: `gpt-5.2-codex` → `gpt-5.3-codex-spark`（Cerebras 上で 1000+ tok/s の高速推論に対応）
  - `agent-coordination.md`, `org-tick.md` のモデル参照を更新

### 内部
- **OrgOS Intelligence 設計完了**: T-INT-000〜006 タスク追加、設計書（`.ai/DESIGN/ORGOS_INTELLIGENCE.md`）作成
- **Codex Work Order/Logs**: T-OS-019〜021 の実行ログ追加

---

## v0.16.1 (2026-01-30)

### 修正

- **Manager 委任ルール強化**: 小タスクでも必ず TASKS.yaml に記録し、Codex CLI に委任するよう変更
- **Codex CLI パス明記**: `/opt/homebrew/bin/codex` のフルパスを CLAUDE.md に記載し、「見つからない」誤認を防止
- **Manager 実装禁止**: `.ai/` 以外のソースコードを Manager が直接 Edit/Write することを例外なく禁止

---

## v0.1.0 (2026-01-23)

### 初回リリース - MVP

複数の OrgOS プロジェクトを Web ブラウザから一元管理するコンソールの初回リリースです。

### 機能

- **認証**
  - GitHub OAuth ログイン（NextAuth.js v5）
  - JWT セッション管理

- **リポジトリ管理**
  - GitHub リポジトリの登録・削除
  - `.ai/` ディレクトリの自動検出
  - OrgOS プロジェクトの検証

- **ダッシュボード**
  - 登録プロジェクトの一覧表示
  - プロジェクトステータス（Stage, Awaiting Owner）
  - 未読質問数バッジ
  - DASHBOARD.md の内容表示

- **質問・回答**
  - OWNER_INBOX.md の質問一覧
  - 選択肢 / カスタム回答対応フォーム
  - OWNER_COMMENTS.md への書き込み

- **タスク管理**
  - タスク一覧表示
  - 承認・却下ボタン
  - プロジェクト横断タスク優先度ビュー

- **通知**
  - Slack Incoming Webhook 連携
  - Web Push 通知
  - 30秒間隔の自動ポーリング

- **セキュリティ**
  - CSP ヘッダー（環境別設定）
  - レート制限（100 req/min）
  - XSS / CSRF 対策

- **UI**
  - レスポンシブデザイン（モバイル対応）
  - ダークモード対応（Tailwind CSS 4）

### 技術スタック

- Next.js 16.1.4（App Router）
- Tailwind CSS 4
- Prisma 7.2.0 + SQLite（better-sqlite3）
- NextAuth.js v5 beta
- Octokit（GitHub API）

### 使用している OrgOS

- OrgOS v0.11.0

---

## 今後の予定

### Phase 2
- Claude Code SDK 連携による `/org-tick` リモート実行
- リアルタイム WebSocket 更新（ポーリングからの移行）

### その他
- PostgreSQL / MySQL 対応（本番デプロイ用）
- 複数ユーザーでの共同管理
- 権限管理（Admin / Editor / Viewer）
