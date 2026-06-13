# OrgOS 課題棚卸し + 改善案 — Claude 独立分析 (T-OS-300 / Phase 1)

> 作成: 2026-05-01 / Explore Agent (Opus)
> 並列で Codex の独立分析が走行中。本文書は Claude 視点 (UX, 概念整合性, ドキュメント品質, ルール間矛盾, 学習コスト, セッション体験) に特化。
> **注**: 本 Phase 1 は「起動時間 + フォルダ統治」を含む網羅分析。Owner からの追加観点で起動時間は降格、Phase 2 (CLAUDE_ANALYSIS_v2.md) にて「人に依存しない自律進化 + 抜本的 UX 改革」に焦点を移す。

---

## 0. Executive Summary

OrgOS は Phase 1-5 (Memory / Optionality / Intake / Handoff / Authority) を完成させ Manager Quality Eval 20/20 を達成した、設計密度が極めて高いシステム。一方で、その設計密度がそのまま **学習コスト・起動時間・フォルダ混乱・ルール重複** という形で Owner 体験を圧迫している。中核ロジックを残したまま、(a) フォルダの責務分離、(b) ルールの階層整理、(c) 起動 UX の段階表示、(d) ドキュメント単一エントリ化、の 4 点を実施すれば本来のポテンシャルが解放される段階。

**致命的 5 課題**: (1) `.ai/` のトップが 30+ ファイル/フォルダで Owner と Manager が同居、(2) ルール 23 本のうち少なくとも 6 ペアが重複/矛盾、(3) `/org-start` が直列 8〜10 ステップ + 4 質問で First Meaningful Response まで数分、(4) `outputs/` の時系列構造が目的別を阻害、(5) 「Owner が触る/触らない」境界が文書化されていない。

**最大インパクト 5 改善**: (1) `.ai/` を `for-owner/` `for-orgos/` `generated/` の 3 区画に再編、(2) ルールを「Iron Law (1) → Step rule (10) → Skill (n)」3 階層に正規化、(3) `/org-start` を **fast path (即起動) → background 質問** に並び替え、(4) `outputs/` を `outputs/by-task/` `outputs/by-purpose/` に再分類、(5) `STARTHERE.md` を作って Onboarding 単一入口化。

---

## 1. Issues (43 件)

| ID | Sev | Category | Title | Evidence | Impact | Proposed direction |
|---|---|---|---|---|---|---|
| ISS-CLD-001 | P0 | governance-gap | `.ai/` の責務不明 — Owner 編集物・Manager 生成物・AI 一時物・テンプレが同階層 | `.ai/` 直下 30+ entries | Owner がどれを編集してよいか自明でない。誤編集事故リスク。 | 3 区画 (for-owner / for-orgos / generated) に分離 |
| ISS-CLD-002 | P0 | governance-gap | ルートに分散ファイル (requirements.md 38KB, ORGOS_QUICKSTART.md, README.md, AGENTS.md, CLAUDE.md) | ルート ls | Onboarding でどれを読むか不明 | docs/ 配下集約 + STARTHERE.md 入口化 |
| ISS-CLD-003 | P0 | rule-overlap | next-step-guidance.md と proactive-mode.md が重複 | 134行 vs 112行 | SSOT 不明 | proactive-mode を起動時挙動に限定 |
| ISS-CLD-004 | P0 | rule-overlap | session-bootstrap.md と session-management.md が同名で別概念 | 2 ファイル | 名前で混乱 | session-startup / session-context-budget にリネーム |
| ISS-CLD-005 | P0 | doc-clarity | CLAUDE.md (562 行) が Iron Law と実装サイクルとリテラシーを混載 | CLAUDE.md | 読了 10 分以上 | Iron Law インデックスのみ ≤80 行に縮約 |
| ISS-CLD-006 | P0 | rule-overlap | Iron Law が 4 本 (request-intake-loop / session-bootstrap / memory-lifecycle / rationalization-prevention) で並立 | 各ファイル冒頭 | 階層機能不全 | request-intake-loop に集約、他は Step N の下位 Iron Law と明示 |
| ISS-CLD-007 | P1 | naming-inconsistency | org-implementer (DEPRECATED) と codex-implementer 併存 | .claude/agents/ | 新規参加者が誤用 | Deprecated agent を物理削除 |
| ISS-CLD-008 | P1 | rule-overlap | project-flow.md と CLAUDE.md が「OrgOS フロー優先」を二重記述 | 同内容 50 行 | 同期負債 | CLAUDE.md から削除し project-flow に SSOT |
| ISS-CLD-009 | P1 | rule-overlap | session-management.md と performance.md がコンテキスト使用率テーブルを二重記述 | L20-34 vs L13-22 | 80%/90%/95% threshold 二重メンテ | performance.md から削除 |
| ISS-CLD-010 | P1 | doc-clarity | coherence-mode.md 内に未実装スクリプト設計が混入 | L150-187 | ルールと未来設計が混在 | 別ファイル (.ai/DESIGN/scripts/) に分離 |
| ISS-CLD-011 | P1 | onboarding | /org-start が直列 + Owner Q&A 5-6 回 | org-start.md 754 行 | FMR 2-7 分 | Step 0-3 を non-blocking parallel、Step 4 質問を defer |
| ISS-CLD-012 | P1 | onboarding | SessionStart hook が 2 本走る | settings.json | 重複起動・デバッグ困難 | bootstrap.sh が python helper を呼ぶ形に統合 |
| ISS-CLD-013 | P1 | onboarding | SessionStart の文言が Manager 向け命令文 | session_start_context.py L107-113 | Owner にも見える | Manager 命令と Owner 表示を分離 |
| ISS-CLD-014 | P1 | doc-clarity | README.md (117 行) に実在しないコマンド (/org-os-retro, /org-kickoff) | README.md L78 | First impression 損失 | docs/COMMANDS.md SSOT 化 |
| ISS-CLD-015 | P1 | naming-inconsistency | STATUS.md / RUN_LOG.md / sessions/*.md の境界不明確 | manager.md Step 9 | 3 ファイルに同情報重複 | RUN_LOG.md SSOT、STATUS.md 集約ビュー |
| ISS-CLD-016 | P2 | rule-overlap | cross-session-consistency.md が request-intake-loop Step 3 を再記述 | 全体 | Step 3 責務分散 | リンクのみに |
| ISS-CLD-017 | P2 | doc-clarity | .ai/DESIGN/ 8 ファイル粒度バラバラ | DESIGN 下 | 設計と説明と過去レビュー混在 | architecture/reviews/explainers に 3 分割 |
| ISS-CLD-018 | P2 | observability | .ai/sessions/ 24 ファイル中 20+ が 351 byte placeholder | sessions/ ls | 学び抽出機能不全 | session-end hook で実体化 |
| ISS-CLD-019 | P2 | scalability | .ai/CODEX/RESULTS/ に 76 ファイル平坦蓄積 | RESULTS ls | 検索性悪化 | archive/<YYYY-MM>/ 階層化 |
| ISS-CLD-020 | P2 | scalability | TASKS.yaml 1418 行, DECISIONS.md 1418 行, CAPABILITIES.yaml 1813 行 | wc -l | パース時間+人間可読性劣化 | status 別 / 月別 / カテゴリ別 split |
| ISS-CLD-021 | P2 | naming-inconsistency | BRIEF/PROJECT/GOALS/VISION の関係が説明文書のみ | WHAT_IS_ORGOS.md | スキーマ強制無し | STARTHERE.md にファイル責務 1 枚絵 |
| ISS-CLD-022 | P2 | doc-clarity | エージェント定義の 1/3 がスケルトン (org-integrator, org-os-maintainer 等 30 行) | agents/*.md | 中身ゼロの枠 | 削除 or 実装 |
| ISS-CLD-023 | P2 | onboarding | .orgos-manifest.yaml が 23 rule 中 9 のみ列挙 | manifest L69-81 | 14 rule が /org-import で配布されない | 全 23 本 or core/extension 2 階層化 |
| ISS-CLD-024 | P2 | doc-clarity | DASHBOARD.md に OrgOS-dev のメタ情報が混入 | DASHBOARD L17-130 | 一般プロジェクトと用途乖離 | OrgOS-dev / 一般用テンプレ分離 |
| ISS-CLD-025 | P2 | rule-overlap | MVP→確認→拡張サイクルが CLAUDE.md / manager.md / plan-sync で 3 重定義 | 3 ファイル | 3 重メンテ | manager.md SSOT |
| ISS-CLD-026 | P2 | rule-overlap | Codex CLI 起動規約が agent-coordination.md と manager.md で二重 | L221-296 | platform 分岐の片側更新リスク | manager.md はリンクのみ |
| ISS-CLD-027 | P2 | governance-gap | .ai/RESOURCES/ は read-only Iron Law だが SELF_REVIEW 等 AI 自己生成物が混入 | RESOURCES/ ls | Iron Law と実態の乖離 | 運用ルールを実態に合わせる or 分離格納 |
| ISS-CLD-028 | P2 | observability | Manager Quality Eval が継続実行されている形跡薄 | METRICS/ 3 ファイル | 20/20 が古い断面値の可能性 | schedule で daily 自動実行 + alert |
| ISS-CLD-029 | P2 | doc-clarity | awaiting_owner の Owner 視点説明が DASHBOARD のみ | CONTROL.yaml コメント | Owner が「答える状態」を直感把握できない | INBOX 連携強化 + 未回答件数即視 |
| ISS-CLD-030 | P2 | onboarding | BRIEF.md テンプレ (1551 byte) が抽象的 | TEMPLATES/BRIEF.md | TBD 連発で密度薄 | BRIEF.example.md の good/bad 例併置 |
| ISS-CLD-031 | P2 | integration-fragility | bootstrap.sh が Ruby 依存 | bootstrap.sh L48-95 | Ruby 未環境で起動失敗 | Python 統一 or graceful skip |
| ISS-CLD-032 | P2 | learning-cost | ルール総量 = 23 ファイル × 平均 200 行 = 約 4350 行 | wc -l | Manager 起動時に全部読むのは非現実 | 3 階層化 + 必須/推奨/オンデマンド分類 |
| ISS-CLD-033 | P3 | naming-inconsistency | OWNER_INBOX/COMMENTS の方向が直感的でない | 2 ファイル名 | Owner がどっちに書くか迷う | inbox/{from-manager,from-owner}.md |
| ISS-CLD-034 | P3 | observability | .ai/AUDIT/ にログがあるが Owner はその存在を知らない | AUDIT/*.log | 監査機能未可視化 | DASHBOARD に audit summary |
| ISS-CLD-035 | P3 | scalability | outputs/ の時系列構造は 2 ヶ月分 2 件のみ | outputs/2026-01-{28,30}/ | 機能していない証拠 | by-task / by-purpose に再編 |
| ISS-CLD-036 | P3 | doc-clarity | Schemas (8 ファイル) と rule の対応索引なし | schemas/ ls | 影響範囲読めない | schemas/INDEX.md (rule ↔ schema ↔ runtime) |
| ISS-CLD-037 | P3 | governance-gap | .ai/_archive/ 命名規則・ライフサイクル未定義 | .gitignore L4 | サイズ無制限増加リスク | retention policy + 命名規則 |
| ISS-CLD-038 | P3 | doc-clarity | Iron Law violation 検出が分散 | eval/check-*.sh | 一本テスト不可 | eval/run-all.sh に集約 |
| ISS-CLD-039 | P3 | learning-cost | 専門用語が日英混在 (intake/capability/autonomy/handoff) | 各 rule | beginner literacy に壁 | GLOSSARY.md 作成 |
| ISS-CLD-040 | P3 | integration-fragility | DESIGN/ が「読み取り専用設計書」と「LLM 更新ファイル」のどちらか不明 | output-management vs design-documentation | 用途矛盾 | archive/ と working/ に分割 |
| ISS-CLD-041 | P3 | observability | Phase 1-5 完了の定義一覧が無い | DASHBOARD/DECISIONS | 即断不可 | .ai/DESIGN/PHASES.md 1 枚 |
| ISS-CLD-042 | P3 | scalability | USER_PROFILE.yaml/CAPABILITIES.yaml gitignored だが無いと bootstrap warning | .gitignore L9-10 | 新規 clone で warning (UX 悪化) | .example.yaml をシード |
| ISS-CLD-043 | P3 | doc-clarity | requirements.md (38KB) ルートに死蔵 | ルート | 死蔵ドキュメント | docs/legacy/ 移動 or 削除 |

## 2. Improvements (25 件)

| ID | Priority | Area | Proposal | Rationale | Effort | Risk |
|---|---|---|---|---|---|---|
| IMP-CLD-001 | P0 | ルール階層 | Iron Law を request-intake-loop.md 1 本に統合 | 4 ヶ所「Iron Law」自称解消、deterministic に | M | 小 |
| IMP-CLD-002 | P0 | フォルダ統治 | .ai/ を for-owner/ for-orgos/ generated/ の 3 区画に再編 | 触っていい/だめ境界の物理化 | L | 中 |
| IMP-CLD-003 | P0 | 起動 UX | /org-start を fast path (30 秒) + deferred path に分割 | FMR 短縮 | M | 中 |
| IMP-CLD-004 | P0 | ドキュメント | STARTHERE.md ルートに作成 (≤200 行) | 単一エントリポイント | S | 低 |
| IMP-CLD-005 | P0 | ルール総量 | 23 本を 3 階層 (Iron Law=1 / Step Rules=10 / Auxiliary=12) に再構成 | bootstrap 必読量半減 | M | 小 |
| IMP-CLD-006 | P1 | outputs 分類 | 時系列廃止、by-task/T-OS-XXX/ + by-purpose/{reports,exports,research}/ | 目的で探せる | S | 低 |
| IMP-CLD-007 | P1 | Onboarding | BRIEF.example.md (3 種) と BRIEF.template.md 併置 | 何を書けばいいか解消 | S | 低 |
| IMP-CLD-008 | P1 | Bootstrap | SessionStart hook を 1 本に統合 + Owner/Manager メッセージ分離 | clean welcome | S | 低 |
| IMP-CLD-009 | P1 | 命名 | OWNER_INBOX/COMMENTS を inbox/{from-manager,from-owner}.md に | 方向性が名前から読める | S | 中 |
| IMP-CLD-010 | P1 | Manager 起動 | /org-tick の Step 1 をキャッシュ可能に | tick レスポンス短縮 | M | 中 |
| IMP-CLD-011 | P1 | エージェント定義 | Deprecated agent を物理削除 | 二重系統解消 | S | 低 |
| IMP-CLD-012 | P1 | DASHBOARD | OrgOS-dev / 一般用テンプレ分離 | Owner が自分のプロジェクト即把握 | S | 低 |
| IMP-CLD-013 | P1 | コマンド | /org-status (read-only サマリ 30 秒) 新設 | tick 前の状況把握 | S | 低 |
| IMP-CLD-014 | P1 | rule SSOT 化 | コンテキスト使用率 / Codex 起動規約 / MVP サイクルの 3 重複解消 | メンテ負債削減 | S | 低 |
| IMP-CLD-015 | P1 | 用語 | .ai/GLOSSARY.md 新設 | beginner literacy に届く | S | 低 |
| IMP-CLD-016 | P2 | TASKS.yaml | status 別ファイル分割 or Active のみ TASKS.yaml | 1418 行保守性 | M | 中 |
| IMP-CLD-017 | P2 | DECISIONS | 月別アーカイブ (DECISIONS/2026-04.md) | 検索性向上 | M | 中 |
| IMP-CLD-018 | P2 | DESIGN | architecture/ reviews/ explainers/ に 3 分割 | 役割分離 | S | 低 |
| IMP-CLD-019 | P2 | Schema 索引 | schemas/INDEX.md (schema ↔ rule ↔ runtime path) | 影響範囲特定容易 | S | 低 |
| IMP-CLD-020 | P2 | Eval | Manager Quality Eval を schedule で daily 自動実行 + DASHBOARD 表示 | 数値の鮮度保証 | M | 低 |
| IMP-CLD-021 | P2 | Sessions | session-end hook で「学び抽出」実装、placeholder 廃止 | 24 ファイル実体化 | M | 中 |
| IMP-CLD-022 | P2 | Onboarding 動画 | STARTHERE.md に 30 秒 screencast URL | 視覚化 | S | 低 |
| IMP-CLD-023 | P2 | CAPABILITIES | Capability 検出を lazy load に | 起動時間短縮 | M | 中 |
| IMP-CLD-024 | P2 | CODEX RESULTS | archive/<YYYY-MM>/ への自動移動 (30 日経過分) | 平坦化防止 | S | 低 |
| IMP-CLD-025 | P2 | Iron Law violation | eval/run-all.sh に 23 本の violation lint 集約 | 違反検出散在解消 | M | 中 |

## 3. New Features (20 件)

| ID | Priority | Area | Proposal | Value 軸 | Dependency | Effort |
|---|---|---|---|---|---|---|
| FEAT-CLD-001 | P0 | UX | STARTHERE.md + /org-help コマンド | 認知負荷↓ | なし | S |
| FEAT-CLD-002 | P0 | UX | /org-status (read-only サマリ) | 観測性↑ | なし | S |
| FEAT-CLD-003 | P0 | 自律性 | /org-resume — 既存プロジェクトを 0 質問で再開 | 自律性↑ | /org-start | M |
| FEAT-CLD-004 | P0 | 観測性 | DASHBOARD Live Health Card | 観測性↑ | manager-quality-runner | M |
| FEAT-CLD-005 | P1 | 認知 | OWNER_INBOX を質問形式 [A][B][C] 推奨マーク付き UI | 認知負荷↓ | next-step-guidance | S |
| FEAT-CLD-006 | P1 | 観測性 | DASHBOARD Capability Map カード | 観測性↑ | CAPABILITIES | S |
| FEAT-CLD-007 | P1 | 自律性 | Auto Brief — README + package.json から BRIEF 自動提案 | 自律性↑ | research-skill | M |
| FEAT-CLD-008 | P1 | 自律性 | Question Budget Counter (3/turn 超過抑制) | 自律性↑ | request-intake-loop Step 6 | M |
| FEAT-CLD-009 | P1 | 観測性 | Decision Trace Visualizer (mermaid graph) | 観測性↑ | DECISIONS schema | M |
| FEAT-CLD-010 | P1 | 認知 | Daily Digest (1 日 1 通 5 行) | 認知負荷↓ | suggest-next | M |
| FEAT-CLD-011 | P2 | 自律性 | Memory Auto-Promote (confidence ≥0.9 + 3 回参照で自動昇格) | 自律性↑ | memory-lifecycle | M |
| FEAT-CLD-012 | P2 | 観測性 | Phase Tracker (1-5 進捗バー) | 観測性↑ | TASKS + phase mapping | M |
| FEAT-CLD-013 | P2 | UX | /org-glossary <term> | 認知負荷↓ | GLOSSARY.md | S |
| FEAT-CLD-014 | P2 | 自律性 | Capability Self-Healing (auth_status=expired で自動 re-auth) | 自律性↑ | capability scan | L |
| FEAT-CLD-015 | P2 | 観測性 | Iron Law Compliance Dashboard | 観測性↑ | eval/run-all | L |
| FEAT-CLD-016 | P2 | 認知 | Project DNA Card (1 行で自プロジェクト記憶) | 認知負荷↓ | BRIEF analysis | S |
| FEAT-CLD-017 | P2 | 自律性 | Adaptive Literacy (Owner 応答から自動推定) | 自律性↑ | literacy-adaptation | M |
| FEAT-CLD-018 | P2 | 観測性 | Trust Score (Manager 自己採点) | 観測性↑ | manager-quality | L |
| FEAT-CLD-019 | P3 | 自律性 | /org-skill add <url> 外部 skill 取り込み | 自律性↑ | skills/ governance | L |
| FEAT-CLD-020 | P3 | UX | Onboarding Wizard (TUI 1 画面 5 質問) | 認知負荷↓ | /org-brief | M |

## 4. Removal/Simplification (12 件)

| ID | 対象 | 理由 | Action |
|---|---|---|---|
| REM-CLD-001 | .claude/agents/org-implementer.md (DEPRECATED) | Codex Worker 移行済 | 削除 |
| REM-CLD-002 | .claude/agents/org-os-maintainer.md (31 行スケルトン) | placeholder のみ | 削除 or org-architect 統合 |
| REM-CLD-003 | outputs/2026-01-{28,30}/ | 時系列分類が機能していない | 削除し outputs/archive/ |
| REM-CLD-004 | requirements.md (38KB ルート) | 参照されない死蔵 | docs/legacy/ or 削除 |
| REM-CLD-005 | coherence-mode.md L150-187 (update-active-graph 設計) | ルールに別 task 設計が混入 | 分離移動 |
| REM-CLD-006 | cross-session-consistency.md ↔ request-intake-loop Step 3 重複 | SSOT 化 | リンク化 |
| REM-CLD-007 | session-management.md ↔ performance.md 同テーブル | 二重 | performance.md から削除 |
| REM-CLD-008 | .ai/STATUS.md (3.3KB) | RUN_LOG.md と DASHBOARD.md の中間で曖昧 | 廃止 |
| REM-CLD-009 | .ai/sessions/*.md placeholder 群 (20+) | 中身ゼロ | 実体化 or gitignore |
| REM-CLD-010 | .ai/OS/ (BACKLOG 48B / CHANGELOG 100B) | 実質空 | .ai/CHANGELOG.md に統合 |
| REM-CLD-011 | ORGOS_QUICKSTART.md (8KB) | README と重複多 | README に統合 |
| REM-CLD-012 | CLAUDE.md 内の自律実行/課題対応/セッション管理/Plan Sync 記述 | 各 rule と完全二重 | リンクのみに |

## 5. Folder Governance (Owner 最重要観点 1)

### 5.1 現状フォルダ責務マトリクス

`.ai/` 直下に Owner編集 (BRIEF / OWNER_COMMENTS / RESOURCES) と Manager専用 (TASKS / DECISIONS / RUN_LOG) と AI生成 (CAPABILITIES / METRICS / AUDIT) と一時退避 (BACKUPS / _archive) が混在。30+ entries が責務未分離。

### 5.2 混在/責務不明箇所の実証

- **Iron Law と実態の矛盾**: `.ai/RESOURCES/` は read-only Iron Law (output-management.md L14) なのに `.ai/RESOURCES/SELF_REVIEW_2026-04-18.md` (7KB) は AI 生成
- **DESIGN/ 目的混在**: ChatGPT_Pro_Review (個別レビュー) / ORGOS_TOBE (構想) / WHAT_IS_ORGOS (説明) / DASHBOARD_ARCHITECTURE (設計) フラット
- **空フォルダ群**: .ai/OS/ (BACKLOG 48B + CHANGELOG 100B), .ai/LEARNED/ (.gitkeep のみ), .ai/LEARNINGS/ (README のみ)
- **placeholder 山**: .ai/sessions/ 24 ファイル中 20 が 351 byte 同一サイズ
- **outputs/ 死蔵**: 2 ヶ月で 2 件のみの時系列フォルダ

### 5.3 outputs/ 時系列廃止 → 目的別

```
outputs/
├── by-task/              # タスクID単位 (一次配置)
│   ├── T-OS-029/
│   ├── T-OS-300/
│   └── T-INT-005/
├── by-purpose/           # 二次目的別ビュー (シンボリックリンク or 索引)
│   ├── reports/
│   ├── exports/
│   ├── research/
│   └── deliverables/
└── archive/              # 90 日経過分
    └── 2026-Q1/
```

### 5.4 推奨ディレクトリツリー (3 階層以内)

```
OrgOS/
├── STARTHERE.md                    ← 単一エントリ (新設)
├── README.md                       ← Project ID card
├── CLAUDE.md                       ← Manager Iron Law インデックスのみ ≤80 行
├── AGENTS.md                       ← Worker constitution
├── docs/                           ← 旧 ORGOS_QUICKSTART, requirements 集約
│   ├── ARCHITECTURE.md
│   ├── COMMANDS.md
│   ├── GLOSSARY.md
│   └── legacy/
├── .claude/                        ← Manager 振る舞い (OrgOS専用)
│   ├── rules/
│   │   ├── _IRON_LAW.md           ← 単一最高位
│   │   ├── steps/                  ← Step 1-10
│   │   ├── auxiliary/
│   │   └── INDEX.md
│   ├── agents/ skills/ commands/ schemas/ evals/ settings.json
├── .ai/                            ← Owner / Manager 対話面
│   ├── for-owner/                  ← Owner 編集可
│   │   ├── BRIEF.md INBOX_FROM_OWNER.md RESOURCES/ GOALS.yaml
│   ├── for-orgos/                  ← Manager 専用 (Owner read-only)
│   │   ├── DASHBOARD INBOX_FROM_MANAGER PROJECT CONTROL TASKS DECISIONS RUN_LOG RISKS RUNBOOKS DESIGN/{architecture,reviews,explainers}/ OIP CODEX REVIEW METRICS
│   ├── generated/                  ← gitignored / lazy
│   │   ├── USER_PROFILE CAPABILITIES BACKUPS AUDIT APPROVALS sessions
│   ├── TEMPLATES/ README.md
├── outputs/ (by-task / by-purpose / archive)
├── scripts/
└── .githooks/ .github/
```

### 5.5 移行計画 (破壊度最小)

- **段階 0**: 参照グラフ書き出し (1 日)
- **段階 1**: 旧→新 symlink 設置 (2 日)
- **段階 2**: ツール側参照を新パスに更新 (1 週間)
- **段階 3**: 旧パスへの直接アクセスに warning (1 週間)
- **段階 4**: symlink 撤去 (任意)
- **互換性 Iron Law**: gitignored 実体パスは絶対変えない

### 5.6 命名規則 + README 配置

- フォルダ名は kebab-case 単数形
- 各ディレクトリに README.md 必置 (≤30 行で「ここは何 / 誰が書く / どこから参照」)
- 索引は 3 ヶ所: ルート STARTHERE.md / .ai/README.md / .claude/rules/INDEX.md

### 5.7 「ここを編集していい/だめ」境界線可視化

各 README 冒頭に 3 色バッジ:
- 🟢 OWNER_EDITABLE
- 🟠 ORGOS_ONLY
- 🔴 READ_ONLY (RESOURCES, archives)

pretool_policy.py に path ベース編集ガード追加。

## 6. Onboarding & Startup UX (Owner 観点 2)

### 6.1 /org-start ステップ分解

ファイル: .claude/commands/org-start.md (754 行)。新規フローは 12 ステップ + Owner Q&A 5-6 回。

### 6.2 ボトルネック

| Step | 推定時間 | 原因 |
|---|---|---|
| Step 1 | 5-30s | Owner Q&A 2 回 (URL + push) |
| Step 4-0 / 4-0b | 30s-2min | Owner Q&A 2 回 (literacy / review_policy) |
| Step 4-1〜4-6 | 1-3min | /org-brief 対話 6 ステップ |
| Step 4-10 | 30s | Owner Q&A 1-2 回 (worker / supervisor) |
| **合計新規** | **2-7 分** | Q&A シリアル 5-6 回 |
| **合計再開** | **5-15 秒** | I/O のみ |

### 6.3 FMR 目標値

| 状況 | 現状 | 目標 |
|---|---|---|
| 新規 (clone 直後) | 2-7 分 | 30 秒で「次やること」可視化 |
| 既存再開 | 5-15 秒 | 3 秒以内 |
| 単発依頼 | 5-10 秒 | 2 秒以内 |

### 6.4 並列化 / 遅延ロード / キャッシュ提案

- bootstrap.sh の 7 台帳読込を parallel I/O 化
- CAPABILITIES scan を lazy (初回利用時のみ probe)
- session-bootstrap で USER_PROFILE/GOALS/TASKS のみ即読、DECISIONS/CAPABILITIES は遅延
- bootstrap 結果を session-state.yaml キャッシュ、Tick 連続で再読込せず diff のみ

### 6.5 進捗インジケータ案

```
🚀 OrgOS 起動中...
[████████░░] 80% — Capability scan
  ✓ 台帳読込 (7/7)
  ✓ Memory ロード
  ⏳ Capability scan (15/58)
  ☐ GOALS bind
```

### 6.6 ZTI (Zero-to-Insight) 体験 — 90 秒以内

```
[T+0s]  $ git clone ... && cd ... && claude
[T+5s]  $ /org-start
        ⚙️ 環境検出 (1s)... ✓ macos
        📚 台帳初期化 (3s)... ✓ 12 ファイル展開
        ❓ プロジェクト概要を 1 行で:
        > ジビエの EC サイト
[T+45s] ✓ BRIEF.md 生成 (例から自動補完)
        ✓ Vision: ジビエをオンライン販売
        📋 次にやること (推奨順):
        [1] /org-tick で要件確定 (推奨)
        [2] BRIEF.md を編集
        [3] /org-settings でレビュー頻度変更
```

質問 1 つだけ。他は default + 後変更可と明示。

### 6.7 SessionStart hook 改善

1. 1 本化: bootstrap.sh が python helper を呼ぶ
2. silent 化: session-state.yaml に書くだけ、Owner には DASHBOARD 1 行サマリのみ
3. Manager 命令 / Owner 表示 分離
4. 学び表示は本当に学びがある時のみ (351 byte placeholder 除外)
5. 失敗時 graceful degradation

## 7. Cross-cutting Themes (5 テーマ)

### Theme 1: Iron Law インフレーション
4 ヶ所が「最高位 Iron Law」を自称 → 心理的に「全部優先」と扱えず希薄化。3 階層化 (Iron Law=1 / Step Rule=10 / Auxiliary=12) で解消。

### Theme 2: 設計密度 vs 体験密度の逆転
MAOPA 5 軸の緻密さが Owner 側に漏れている (literacy / review_policy / supervisor を初回全質問)。「設計密度は Manager 責任 / Owner には透明」を Iron Law 化、defaults で起動 → 使いながら override が原則。

### Theme 3: テキスト中心の自己完結性 — 視覚化不在
23 rule × 13 agent × 14 command すべて Markdown のみ。DASHBOARD/RUN_LOG/STATUS に視覚要素なし。DASHBOARD に mermaid live render (Phase tracker / Decision graph / Capability map / Iron Law compliance) 4 カード配置。

### Theme 4: Manager 専用 vs Owner 用 vs AI 生成 vs Tmp の境界混在
Owner 観点 1 と直結。Iron Law レベルで「ファイル責務分類」欠落、後付けで output-management.md 等で補強している現状。3 区画化で根本解決。

### Theme 5: Phase 完了の証明と現在運用の乖離
DASHBOARD「Manager Quality 20/20」「Phase 1-5 完遂」と派手だが、placeholder 大量 / outputs/ 死蔵 / .ai/OS/ 空ファイルが示す通り運用が回っていない領域多数。Manager Quality Eval を daily 自動 + DASHBOARD live、未使用フォルダ/placeholder の週次レポート。

## 8. Suggested Tasks (T-OS-301 以降, P0)

| Task ID | Title | Dep | Effort | 主な ISS / IMP / FEAT |
|---|---|---|---|---|
| T-OS-301 | フォルダ 3 区画化 段階 1 (symlink) | なし | M | ISS-001, IMP-002 |
| T-OS-302 | STARTHERE.md 新設 + ルートドキュメント整理 | なし | S | ISS-005, IMP-004, FEAT-001 |
| T-OS-303 | Iron Law 階層化 + INDEX.md 整備 | なし | M | ISS-003,004,006, IMP-001,005 |
| T-OS-304 | /org-start Fast Path 実装 | T-OS-302 | M | ISS-011, IMP-003 |
| T-OS-305 | SessionStart hook 統合 + silent 化 | なし | S | ISS-012,013, IMP-008 |
| T-OS-306 | outputs/ 構造刷新 + 移行スクリプト | T-OS-301 | M | ISS-035, IMP-006 |
| T-OS-307 | /org-status 新コマンド | T-OS-302 | S | FEAT-002 |
| T-OS-308 | DASHBOARD Live Health Card | T-OS-303 | M | ISS-028, FEAT-004,006,009 |
| T-OS-309 | ルール重複解消 (6 ペア) | T-OS-303 | M | ISS-003,004,008,009,016,025,026 |
| T-OS-310 | Deprecated agent 削除 + manifest 全 23 rule 再生成 | なし | S | ISS-007,023, REM-001,002 |
| T-OS-311 | BRIEF.example.md + GLOSSARY.md | T-OS-302 | S | ISS-030,039, IMP-007,015 |
| T-OS-312 | session-end hook 学び抽出実装 | なし | M | ISS-018, REM-009, IMP-021 |

---

**Phase 1 統計**: Issues 43 / Improvements 25 / Features 20 / Removals 12 / Themes 5 / Suggested Tasks 12。総文字数 約 22,000。
