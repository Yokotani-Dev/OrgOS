# リポジトリ構成整理プロンプト（OrgOS 導入済みリポジトリ用）

> 使い方: 整理したいリポジトリで Claude Code（OrgOS）を開き、下の `===` で囲まれた本文を**そのまま貼り付け**ます。
> どのプロジェクト種別（Web / API / CLI / ライブラリ等）でも動くよう、エージェントがまず中身を調べてから提案します。
> 安全設計: OrgOS の規約固定ファイルは動かさない / ビルドを壊さない / git 履歴を保つ / 提案→確認→実行。

---

===（ここから貼り付け）===

あなたはこのリポジトリの **OrgOS Manager** です。このリポジトリは OrgOS フレームワークと
プロジェクト固有ファイルが混在し、フォルダ構成が乱雑になっています。
**OrgOS とプロジェクトのビルドを壊さずに**、トップレベルを「人間が触る場所 / 機械用」に分け、
構成を明瞭で保守しやすい形に整理してください。

## 鉄則（例外なし）
1. **OrgOS 規約固定ファイルは絶対に動かさない**: `CLAUDE.md` `AGENTS.md` `README.md` `.claude/`
   `.github/` `.githooks/` `.gitignore` `.orgos-manifest.yaml` `.pre-commit-config.yaml`
   `.ai/CONTROL.yaml` および kernel 保護ファイル群（`.ai/TASKS.yaml` `.ai/DECISIONS.md`
   `.ai/DASHBOARD.md` 等）。これらは Claude Code / OrgOS kernel がパスで参照するため移動禁止。
2. **ビルドを壊さない**: 移動後にプロジェクトのビルド/テストが通ること。`src/` 等を動かす場合は
   ビルド設定（tsconfig paths / import / バンドラ設定 / CI）も同時に書き換える。
3. **git 履歴を保つ**: 追跡ファイルは `git mv`。未追跡は `mv`。
4. **提案 → 確認 → 実行**: 破壊的な移動の前に before→after マップを提示し、Owner の go を得る
   （参照ゼロ〜LOW リスクのみなら確認なしで実行してよい）。
5. **push しない**: コミットまで。push は Owner が明示したときだけ。

## Phase 0 — 前提同期（最初に実行）
- `scripts/org/migrate-layout.sh` が存在すれば `bash scripts/org/migrate-layout.sh` を実行し、
  `.ai/` の機械用データ（events/leases/queue/sessions/codex/evolution/artifacts 等）を
  `.ai/_machine/` 配下へ収束させる（冪等。新レイアウトなら no-op）。
  存在しなければ OrgOS が旧版なので、その旨を記録してスキップ（.ai は手で動かさない）。
- `git status` がクリーンか確認（汚れていれば stash か、まず現状をコミットしてから着手）。
- ビルドシステムを特定（`package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml` / `Makefile` 等）と、
  それがどのパスを参照しているかを把握。

## Phase 1 — 監査と分類（読み取り専用）
トップレベルの全エントリを列挙し、次に分類する。各「移動候補」は
`grep -rIl '<パス>'` で**被参照数**を実測する（リスク判定の根拠）。

| 分類 | 例 | 扱い |
|---|---|---|
| A. OrgOS 規約固定 | 鉄則1の一覧 | **動かさない** |
| B. OrgOS 台帳 (`.ai/`) | Phase 0 で二層化済み | そのまま |
| C. プロジェクト固有・人間用 | `src/` `docs/` 設計書・README 類 | 整理対象（慎重に） |
| D. プロジェクト固有・機械用/生成物 | `dist/` `build/` `.next/` `coverage/` `*.log` キャッシュ | gitignore + まとめる |
| E. ゴミ | `.DS_Store` 空ディレクトリ 誤コミットされた生成物 | gitignore / 除去 |

リスク基準: LOW = 被参照 ≤ 5、MED = 6–20、HIGH = 21+ または kernel/CI/ビルド設定から参照あり。

## Phase 2 — 提案（ONE プラン）
before→after の移動マップ表を出す（現在パス → 新パス / 被参照数 / リスク / 必要な追従修正＝
ビルド設定?・import?・CI?）。原則は **トップレベルで「人間が開く」と「機械用」を分ける**こと。
（例: 生成物・ログ・キャッシュは `.gitignore` で隠す or 1 箇所へ集約、ドキュメントは `docs/` へ集約など。
ただしそのプロジェクトの慣習・フレームワーク規約を尊重し、機械的に壊さない。）
要約 + 推奨を簡潔に提示し、HIGH/MED を含むなら Owner に go を求める。

## Phase 3 — 実行（go 後）
- `git mv` で移動 → **全参照を書き換え**（import / ビルド設定 / tsconfig paths / CI / ドキュメント内リンク）
- ゴミは `.gitignore` に追記（既存行は消さず追加）+ 空ディレクトリ除去
- **A 分類は絶対に動かさない**
- ゲート: プロジェクトのビルド/テストが通る。`tests/kernel/run-kernel-tests.sh` があれば
  `bash tests/kernel/run-kernel-tests.sh` が green のまま（OrgOS を壊していない確認）。

## Phase 4 — 記録
- トップレベルの `README.md` に「構成地図」（人間が触る場所 / 機械用）を追記または新設。
- 任意: `.vscode/settings.json` の `files.exclude` で機械用フォルダをエクスプローラー非表示に
  （表示のみの設定。ファイルや動作には無関係）。
- コミットは OrgOS の正規フローで（`.claude/rules/kernel-write-path.md` 参照。
  台帳更新は `scripts/org/update-task.py` 等、コミットは integrator 経由。kernel が直接編集を deny する）。
  論点ごとに 1 コミット。**push はしない**。
- 最後に before→after のツリーを報告。

まず Phase 0→1 を実行し、Phase 2 の提案を提示してください。

===（ここまで貼り付け）===

---

## 補足

- **複数リポジトリに一括適用したい場合**: 各リポジトリで Claude Code を開いて上記を貼るのが基本です。
  この作業を 2 回以上繰り返すなら、OrgOS の正式コマンド `/org-tidy` 化を推奨します（下記）。
- **`/org-tidy` コマンド化**: OrgOS 本体にコマンドとして登録すれば、再 import 済みリポジトリでは
  `/org-tidy` と打つだけで同じ処理が走ります（このプロンプトを毎回貼る必要がなくなる）。
  Manager に「org-tidy をコマンド化して」と指示すれば実装します。
