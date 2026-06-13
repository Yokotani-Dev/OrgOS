# レイアウト移行の後方互換設計 (T-OS-497)

> Owner 懸念 (2026-06-13):「フォルダ構成が変わって、org-import 時に既存リポジトリで不整合が起きないか」
> → 的中。`/org-import` にデータ移行が無く、既存リポジトリは旧レイアウト。対策を本書で固定する。

## 1. 失敗モード（対策しない場合）

既存リポジトリ（旧: `.ai/events` `.ai/CODEX` 等がルート）が新コードを取り込むと、
新コードは `.ai/_machine/*` を見るが既存データは `.ai/` 直下に残り、**状態が分裂**する:
- events ハッシュチェーン断絶 / lease 無効 / queue 孤立 / Evidence-Gated Done 破綻

## 2. 自然な安全ゲート（現時点では未拡散）

新レイアウトは**まだどの外部リポジトリにも届いていない**:
- push は Owner 制御、`/org-publish` 未実行、各リポジトリの `/org-import` 未実行
- → **本互換層を入れてから publish すれば、既存リポジトリは安全に移行できる**

Iron Law: **本互換層が完成するまで新レイアウトを `/org-publish` しない。**

## 3. 対策 — 2 重の仕組み

### 機構1: 冪等な移行スクリプト `scripts/org/migrate-layout.sh`（主対策）

- 旧レイアウト検出 → `.ai/<DIR>` を `.ai/_machine/<dir>` へ `git mv`（追跡）/ `mv`（非追跡）
- **冪等**: 既に移行済みなら no-op。途中状態（一部だけ旧）も安全に収束
- events は移行後もチェーン連続（ファイル移動はハッシュに影響しない）を移行後 verify
- 衝突時（新旧両方存在）: 旧を `_machine` 配下にマージ、衝突ファイルは `_from_legacy` suffix
- 起動経路: (a) `/org-import` の最終ステップ、(b) **SessionStart bootstrap**（git pull だけで更新したリポジトリも次セッションで自己治癒）

### 機構2: 中央パス解決ヘルパー（安全網）

- `scripts/org/resolve-machine-dir.{sh,py}`: `machine_dir(name)` →
  `.ai/_machine/<name>` が在ればそれ、無く旧 `.ai/<NAME>` が在れば旧（legacy）、どちらも無ければ新を作成
- kernel hook（policy_core leases/CODEX）・append-event.py・check-task-done.py・integrator を順次これ経由に
- 効果: 移行スクリプト実行前の一瞬や部分状態でも新コードが旧データを正しく読む（belt-and-suspenders）

## 4. `/org-import`・`/org-publish` の更新

- `org-import.md`: コピー後に `migrate-layout.sh` を実行する手順を追加
- `.orgos-manifest.yaml`: `migrate-layout.sh` / `resolve-machine-dir.*` を publish + create_dirs に `_machine` 系を追加
- `org-publish.md`: 「互換層 (T-OS-497) 未配備なら新レイアウトを publish しない」プリフライト

## 5. テスト (tests/kernel/test-layout-migration.sh)

1. 旧レイアウトの fake repo → migrate-layout.sh → 全 dir が `_machine` 配下・旧空
2. 冪等性: 2 回目実行で no-op・差分ゼロ
3. events チェーン: 移行後も prev_hash 連続
4. 部分状態（一部だけ旧）→ 残りだけ移行
5. resolve-machine-dir: 新在り/旧在り/両無しの 3 分岐
6. 衝突: 新旧同名 → マージ + suffix、データ消失なし

## 6. 実行順序

1. **現行 repo-clarity-migration ワークフロー完了を待つ**（OrgOS 開発リポジトリ自身の移行 + コミット）
   - 同一ファイル群を編集中のため、並行実行は競合する
2. 本互換層 T-OS-497 を実装（機構1+2 + import/publish 更新 + テスト）
3. 互換層 green 確認後に初めて `/org-publish` 可能化
