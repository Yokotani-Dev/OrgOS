---
description: このリポジトリのフォルダ構成を整理する（OrgOS固定物を保護しつつ人間用/機械用に分離、ビルド非破壊）
---

# /org-tidy - リポジトリ構成整理

OrgOS フレームワークとプロジェクト固有ファイルが混在して乱雑になったリポジトリを、
**OrgOS とビルドを壊さずに**「人間が触る場所 / 機械用」へ整理する。git 履歴を保ち、提案→確認→実行で進める。

import 済みの各リポジトリでこのコマンドを実行すれば、毎回プロンプトを貼らずに同じ整理が走る。

---

## 使い方

```
/org-tidy            # 監査 → 提案 → (確認後) 実行
/org-tidy --dry-run  # 監査と提案のみ。移動は一切しない
```

---

## 鉄則（例外なし）

1. **OrgOS 規約固定ファイルは絶対に動かさない**: `CLAUDE.md` `AGENTS.md` `README.md` `.claude/`
   `.github/` `.githooks/` `.gitignore` `.orgos-manifest.yaml` `.pre-commit-config.yaml`
   `.ai/CONTROL.yaml` および kernel 保護ファイル（`.ai/TASKS.yaml` `.ai/DECISIONS.md`
   `.ai/DASHBOARD.md` 等 PROTECTED_STATE_FILES）。Claude Code / OrgOS kernel がパス参照するため移動禁止。
2. **ビルドを壊さない**: 移動後にプロジェクトのビルド/テストが通ること。`src/` 等を動かす場合は
   ビルド設定（tsconfig paths / import / バンドラ / CI）も同時に書き換える。
3. **git 履歴を保つ**: 追跡ファイルは `git mv`、未追跡は `mv`。
4. **提案 → 確認 → 実行**: 破壊的移動の前に before→after マップを提示し Owner の go を得る
   （被参照ゼロ〜LOW のみなら確認なしで実行可）。
5. **push しない**: コミットまで。push は Owner が明示したときだけ。

## Phase 0 — 前提同期

- `scripts/org/migrate-layout.sh` があれば `bash scripts/org/migrate-layout.sh` を実行し、
  `.ai/` の機械用データ（events/leases/queue/sessions/codex/evolution/artifacts 等）を
  `.ai/_machine/` 配下へ収束（冪等・新レイアウトなら no-op）。無ければ旧版 OrgOS として記録しスキップ。
- `git status` クリーン確認（汚れていれば stash か先にコミット）。
- ビルドシステム（`package.json`/`pyproject.toml`/`go.mod`/`Cargo.toml`/`Makefile` 等）と参照パスを把握。

## Phase 1 — 監査と分類（読み取り専用）

トップレベルの全エントリを列挙し分類。各「移動候補」は `grep -rIl '<パス>'` で被参照数を実測する。

| 分類 | 例 | 扱い |
|---|---|---|
| A. OrgOS 規約固定 | 鉄則1の一覧 | **動かさない** |
| B. OrgOS 台帳 (`.ai/`) | Phase 0 で二層化済み | そのまま |
| C. プロジェクト固有・人間用 | `src/` `docs/` 設計書 | 整理対象（慎重に） |
| D. プロジェクト固有・機械用/生成物 | `dist/` `build/` `.next/` `coverage/` `*.log` キャッシュ | gitignore + 集約 |
| E. ゴミ | `.DS_Store` 空ディレクトリ 誤コミット生成物 | gitignore / 除去 |

リスク基準: LOW = 被参照 ≤ 5、MED = 6–20、HIGH = 21+ または kernel/CI/ビルド設定から参照あり。

## Phase 2 — 提案（ONE プラン）

before→after マップ表（現在パス → 新パス / 被参照数 / リスク / 必要な追従修正＝ビルド設定?・import?・CI?）。
原則: **トップレベルで「人間が開く」と「機械用」を分ける**。プロジェクトの慣習・フレームワーク規約を尊重し
機械的に壊さない。要約 + 推奨1案を提示。HIGH/MED を含むなら Owner に go を求める。`--dry-run` ならここで終了。

## Phase 3 — 実行（go 後）

- `git mv` で移動 → **全参照を書き換え**（import / ビルド設定 / tsconfig paths / CI / ドキュメント内リンク）
- ゴミは `.gitignore` に追記（既存行は消さず追加）+ 空ディレクトリ除去
- **A 分類は絶対に動かさない**
- ゲート: プロジェクトのビルド/テストが通る。`tests/kernel/run-kernel-tests.sh` があれば green のまま。

## Phase 4 — 記録

- トップレベル `README.md` に「構成地図」（人間が触る場所 / 機械用）を追記または新設。
- 任意: `.vscode/settings.json` の `files.exclude` で機械用フォルダをエクスプローラー非表示（表示のみ・動作無関係）。
- コミットは OrgOS 正規フロー（`.claude/rules/kernel-write-path.md`：台帳更新は `scripts/org/update-task.py` 等、
  コミットは integrator 経由。kernel が直接編集を deny）。論点ごとに 1 コミット。**push しない**。
- before→after ツリーを報告。

---

## 注意

- このコマンドは OrgOS 導入済みリポジトリ専用。OrgOS が無いリポジトリでは鉄則1の保護対象が無いため、
  一般的なフォルダ整理として Phase 1-4 を適用する。
- 大規模・多数ファイルの移動は worktree + lease 下で行うと安全（`.claude/rules/parallel-session-policy.md`）。
