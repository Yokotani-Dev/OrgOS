# Resource Intake Triage — Iron Law

> Owner が参照ファイル・参考ファイルをどこに置いても、Manager が `.ai/RESOURCES/` の適切な場所へ取り込む（移動 + 台帳登録 + リネーム）。放置しない。例外なし。

本ルールは [output-management.md](output-management.md) の「インプットリソース受領時のフロー」を拡張し、**「Owner が正しい場所に置く」前提を捨て、「どこに置かれても Manager が拾い上げる」** 運用に変える。

---

## Iron Law

1. Owner が追加した参照・参考ファイル（プロジェクトの input / 素材 / 調査元）は、置かれた場所に関わらず `.ai/RESOURCES/` 配下の適切なサブディレクトリへ取り込む。
2. 取り込みは **移動（git mv）→ 台帳登録（`.ai/RESOURCES/README.md`）→ リネーム** の 3 ステップを必ず実行する。
3. 取り込み後の `.ai/RESOURCES/` は read-only（[output-management.md](output-management.md) の RESOURCES 書込禁止 Iron Law を継承）。
4. 分類が曖昧なファイルは放置せず、Owner に「開けるファイル + 短文」で確認する。技術的な選択肢は並べない。
5. 固定構造物（下記 Protected Zones）は対象外。絶対に移動しない。

---

## docs/ と .ai/RESOURCES/ の役割境界

| 置場 | 何を置くか | 誰が開くか |
|------|-----------|-----------|
| `docs/` | Owner が**直接開いて読む人間向け資料**のみ | 人間（Owner） |
| `.ai/RESOURCES/` | プロジェクトの **input / 参考 / 調査元素材**（AI・作業が参照する） | AI・作業（read-only 参照） |
| `.ai/_machine/` | 機械・開発者向けの運用ログ・生成物 | 機械・Manager |

> kernel 運用ログのような機械/開発者向け記録は `docs/` ではなく `.ai/_machine/` に置く（PLAN-UPDATE-507）。

---

## Triage Source Zones（拾い上げ対象）

毎 Tick 開始時、および Owner ファイル受領時に以下を走査する。

- リポジトリルート直下の **非固定** ファイル（Protected Zones の固定文書を除く）
- `docs/` 配下で、Owner 直接参照資料に該当しない input / 素材ファイル
- その他、想定外の場所に置かれた参照・参考ファイル

---

## Protected Zones（絶対に動かさない）

- ルート固定文書: `CLAUDE.md` `AGENTS.md` `README.md` `ORGOS_QUICKSTART.md`
- `.ai/` `.claude/` `scripts/` `tests/` `.github/` `.githooks/` `outputs/`
- VCS / harness 設定: `.gitignore` `.pre-commit-config.yaml` `.orgos-manifest.yaml` `.worktrees/`

---

## 分類 → 配置先

| ファイル種別 | 配置先 |
|-------------|--------|
| ドキュメント類（仕様・記事・PDF・議事録） | `.ai/RESOURCES/docs/inputs/` |
| デザイン類（pptx・画像・Figma export） | `.ai/RESOURCES/designs/` |
| コードサンプル・参考実装 | `.ai/RESOURCES/code-samples/` |
| 調査・参照リンク集・外部資料 | `.ai/RESOURCES/references/` |
| スキル素材 | `.ai/RESOURCES/skills/` |
| 上記に当てはまらない | Owner に確認（開けるファイル + 短文） |

---

## 取り込み手順

```
1. 移動: git mv <元パス> .ai/RESOURCES/<サブディレクトリ>/<新ファイル名>
   - 履歴を保持するため git mv を使う（リポジトリ管理下のとき）

2. 台帳登録: .ai/RESOURCES/README.md の「外部インプットファイル管理台帳」に追加
   | ファイル名 | 配置先 | 提供元 | 用途 | 受領日 |

3. リネーム:
   - 日本語ファイル名はそのまま可
   - 日付未含なら YYYYMMDD_ プレフィックス（受領日 = Today's date 環境変数）
   - バージョン番号は保持
```

---

## Tick 連携

`/org-tick` の整合性チェック（Step 5 系）に triage 走査を含める。

1. Triage Source Zones を走査
2. 取り込み対象があれば 3 ステップで取り込み
3. 取り込み結果をイベント記録（`append-event.py`）し、簡潔に報告
4. 曖昧ファイルがあれば Owner 確認に回す（放置しない）

> 自動化スクリプト（走査 + 提案）は T-OS-508 の実装対象。スクリプト未配線でも、Manager は本ルールに従って毎 Tick 手動 triage する。

---

## Red Flags

- Owner が docs/ やルートに置いた input ファイルを `.ai/RESOURCES/` へ取り込まず放置している
- 取り込み時に台帳登録・リネームを省略している
- `.ai/RESOURCES/` を上書き編集している（read-only 違反）
- Protected Zones のファイルを移動しようとしている
- 分類が曖昧なまま、確認も取り込みもせず放置している

---

## 参考資料

- [output-management.md](output-management.md) - 生成物配置ルール（本ルールの親）
- [.ai/RESOURCES/README.md](../../.ai/RESOURCES/README.md) - 外部インプットファイル管理台帳
- [.ai/DESIGN/REPO_LAYOUT_V1.md](../../.ai/DESIGN/REPO_LAYOUT_V1.md) - リポジトリ全体レイアウト設計
