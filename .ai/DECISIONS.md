# DECISIONS

> 意思決定の記録。Manager が更新する。
> Owner は OWNER_COMMENTS.md 経由で決定を伝える。

---

## Decision Types

- **B1 (info-gap)**: 情報不足で決められない → 調査タスクで解決
- **B2 (tradeoff)**: トレードオフがあり Owner 判断が必要

---

## Pending (Owner Review)

(なし)

<!--
決定待ちの例：
- ID: D-001
  Title: 認証方式の選択
  Type: B2 (tradeoff)
  Context: ユーザー認証の実装方式を決める必要がある
  Options:
    1. JWT + Cookie（シンプル、既存実装あり）
    2. OAuth2（拡張性高い、実装コスト高）
    3. Firebase Auth（マネージド、ベンダーロック）
  Recommendation: Option 1（既存資産活用）
  Blocked tasks: T-003, T-004
  Owner decision: (待ち)
-->

---

## Decided

- ID: D-001
  Title: 成果物格納ディレクトリの標準化
  Decision: `.ai/ARTIFACTS/` を新設し、サブディレクトリで分類
  Decided by: Owner
  Date: 2026-01-20
  Rationale: 入力(RESOURCES)と出力(ARTIFACTS)を明確に分離し、成果物の配置場所を標準化

<!--
決定済みの例：
- ID: D-001
  Title: 認証方式の選択
  Decision: Option 1 (JWT + Cookie)
  Decided by: Owner
  Date: 2026-01-18
  Rationale: 既存実装を活用し、開発速度を優先
-->

---

## PLAN-UPDATE-001: タスク追加（上司レビューモード + 引き継ぎ機能）(2026-01-23)

### 変更内容
- 追加: T-OS-004（上司レビューモード機能）
- 追加: T-OS-005（プロジェクト引き継ぎ機能）

### 理由
- 部下がOrgOSを使う際の課題に対応
  - 判断能力が低く、何でもYesYesと言ってブラックボックス化
  - やりたいことと計画がずれる
- 上司が進捗・判断をレビューしやすくする
- 上司が途中まで進めて部下に引き継ぐパターンに対応

### 機能概要（T-OS-004: 上司レビューモード）
1. /org-start 時に「作業者」「上司レビュー要否」を質問
2. 重要な判断時に上司レビュー用ドキュメント自動生成
3. 計画乖離（BRIEF.mdとのずれ）を自動検知
4. 上司承認待ち状態で停止

### 3つのモード
- 自分 + レビューあり: 重要な判断で上司レビューをリマインド
- 自分のみ: 上司レビューなし
- 部下 + スーパーバイザー: 部下が作業、上司レビュー必須

### 機能概要（T-OS-005: 引き継ぎ機能）
1. 引き継ぎ情報を CONTROL.yaml に記録（誰から誰へ、どこまで完了）
2. 引き継ぎドキュメント（.ai/HANDOFF.md）自動生成
3. git pull 後の SessionStart で引き継ぎを検知
4. 引き継ぎ時の注意事項を表示

### 依存関係
- T-OS-005 は T-OS-004 完了後に実装（CONTROL.yaml の supervisor_review を活用）

---

## PLAN-UPDATE-002: タスク追加（ゴール階層管理機能）(2026-01-23)

### 変更内容
- 追加: T-OS-006（ゴール階層管理・動的計画再構築機能）
- OIP-006 を作成

### 理由
- Owner の実際のニーズから生まれた機能
  - 依頼に応じてゴールが変化する（小さなゴール → 大きなゴールへ）
  - 例: 「ECサイトを作る」→「ジビエブランド全体を立ち上げる」
  - OrgOS が初期ゴールに固執し、全体整合が取れなくなる課題
- 計画の全体整合性を保つために重要
- 他の機能（スーパーバイザーレビュー、引き継ぎ）の基盤になる

### 機能概要（T-OS-006: ゴール階層管理）
1. Vision → Milestone → Project → Task の4階層でゴール管理
2. `.ai/GOALS.yaml` でゴール構造を永続化
3. 新規依頼の位置づけを自動判断（既存ゴールの一部 or 新しいゴール）
4. Milestone 達成時・新規依頼が乖離時・20タスク完了ごとに見直し提案
5. `/org-goals` コマンドでゴール可視化・編集
6. DASHBOARD.md / PROJECT.md にゴール階層を表示

### 実装内容
- 新規ファイル: `.ai/GOALS.yaml`
- 新規コマンド: `/org-goals`
- 変更: `CLAUDE.md`, `/org-start`, `/org-tick`, `DASHBOARD.md`, `PROJECT.md.template`

### メリット
- ゴールの柔軟な変更が可能（小→大への拡大、新規依頼の統合）
- 全体整合性の維持（Vision からの一貫性）
- 進捗の可視化（どの Milestone まで完了しているか）
- Owner の判断を最小化（Manager が自動で位置づけ判断）

### デメリット・対策
- 複雑性の増加 → `/org-goals` で可視化・編集をサポート
- 既存プロジェクトの移行 → `/org-start` で自動変換
- 学習コスト → リテラシー適応ルールで説明を調整

### 実装優先度
- P1（高優先度）

### 実装スケジュール
- 約6日（Phase 1-6）

### 参考
- `.ai/OIP/OIP-006-goal-hierarchy-management.md`

---

## PLAN-UPDATE-003: タスク追加（成果物管理機能）(2026-01-23)

### 変更内容
- 追加: T-OS-007（成果物管理機能）

### 理由
- Owner 依頼: 成果物を資料（samplecode など）から分離したい
- 資料は直接編集せず、複製して outputs/ に配置
- 成果物と資料を明確に区別して管理

### 決定内容
- プロジェクトルートに `outputs/` フォルダを作成（3つの選択肢から Owner が選択）
- 構造:
  ```
  outputs/
  ├── 2026-01-23/       # 日付別
  │   ├── sample1.ts
  │   └── README.md
  └── T-OS-004/         # タスクID別
      └── implementation.ts
  ```

### 実装内容
- `outputs/` フォルダ構造の設計・実装
- `.gitignore` に outputs/ の扱いを追加（Owner に確認）
- `CLAUDE.md` に成果物管理ルールを追加
- `AGENTS.md`（Codex worker）に資料複製→outputs/ 配置のフローを追加
- `outputs/README.md` 作成（フォルダ説明）

### メリット
- 成果物とプロジェクトファイルを明確に分離
- Owner が成果物を確認しやすい（プロジェクトルートに配置）
- 資料を汚さない（複製してから編集）
- git で管理するか選択可能

### git 管理の判断
- **決定**: outputs/ をリポジトリに含める（`.gitignore` に追加しない）
- **理由**:
  - 成果物の履歴が残る
  - チーム間で共有できる
  - バックアップとして機能する
- **Owner 承認**: あり（2026-01-23）

---

## RELEASE-001: v0.11.0 公開 (2026-01-23)

### 決定内容
- OrgOS v0.11.0 を公開リポジトリにリリース

### 公開内容
- AI ドリブン開発ルール追加
  - `.claude/rules/ai-driven-development.md`
  - Manager が技術判断を主導、Owner はビジネス判断のみ
- 評価ループルール追加
  - `.claude/rules/eval-loop.md`
- manifest 更新（上記2ファイルを追加）

### 技術的判断
- HTTPS を使用（gh CLI の認証情報を利用）
  - 理由: SSH 接続がサンドボックスで制限される可能性があるため
- `public` リモートを HTTPS に変更

### 公開先
- リポジトリ: https://github.com/Yokotani-Dev/OrgOS
- コミット: 394f24e
- タグ: v0.11.0
- ファイル数: 52


---

## RELEASE-003: v0.12.0 リリース (2026-01-23)

### リリース内容

**4つの主要機能を追加:**

1. **T-OS-004: 上司レビューモード（スーパーバイザーレビュー機能）**
   - 3つのモード: `self_only` / `self_with_reminder` / `subordinate_with_supervisor`
   - 重要な判断時にレビュードキュメントを `.ai/SUPERVISOR_REVIEW/` に自動生成
   - 計画乖離検知機能（30%以上乖離で警告）
   - CONTROL.yaml に `supervisor_review` セクション追加

2. **T-OS-005: プロジェクト引き継ぎ機能**
   - 3つの引き継ぎパターン: 上司→部下 / 部下→上司（レビュー） / チームメンバー間
   - SessionStart hook で引き継ぎ検知
   - `.ai/HANDOFF.md` テンプレート追加
   - CONTROL.yaml に `handoff` セクション追加

3. **T-OS-006: ゴール階層管理機能**
   - Vision/Milestone/Project/Task の4階層管理
   - `/org-goals` コマンド追加（表示・追加・拡大・見直し・履歴）
   - Milestone 達成確認・見直し提案機能
   - `.ai/GOALS.yaml.template` 追加

4. **T-OS-007: 成果物管理機能**
   - `outputs/` フォルダ構造（日付別・タスクID別）
   - 資料（`resources/`）は直接編集せず、`outputs/` にコピーしてから編集
   - `.claude/agents/AGENTS.md` 追加（Codex worker ガイドライン）

### アーキテクチャ改善

- **Manager 仕様の分離**: `.claude/agents/manager.md` に詳細仕様を移動
- **運用ルールの分離**: `.claude/rules/` 配下に以下を追加
  - `project-flow.md` - OrgOS フロー優先、スコープ制限
  - `session-management.md` - セッション管理、コンテキスト管理
  - `next-step-guidance.md` - 次のステップ案内ルール
  - `plan-sync.md` - 計画の継続的更新
- **CLAUDE.md の簡潔化**: 詳細は各専門ファイルに委譲

### リリース情報

- **コミット**: 1ab5454
- **タグ**: v0.12.0
- **変更ファイル数**: 26
- **追加行数**: 4262
- **削除行数**: 618
- **公開日**: 2026-01-23

### 技術的判断

- 4つの機能を1つのリリースにまとめた
  - 理由: 全て相互に関連し、OrgOS の協調開発機能を強化するため
- SessionStart hook を追加
  - 理由: セッション開始時に引き継ぎやセッション学習を自動ロード
- .gitignore に `.DS_Store` を追加
  - 理由: macOS の不要なファイルを除外

### 影響範囲

- **上位互換**: 既存プロジェクトは影響なし（新機能は `/org-start` で設定）
- **新規プロジェクト**: `/org-start` で新機能の設定が追加される
- **マイグレーション不要**: 既存の CONTROL.yaml は自動拡張される

### 次のステップ

- 実際のプロジェクトでの動作確認
- フィードバックに基づく改善
- T-001（要件収集）、T-002（設計）の実装
