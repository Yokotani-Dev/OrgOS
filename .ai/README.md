# .ai/ — OrgOS 台帳（人間が開くゾーン）

**`.ai/` 直下 = 人間（Owner / Manager）が開く台帳・文書。**
機械が読み書きする実行時データは [`.ai/_machine/`](_machine/README.md) に集約されています（人間は通常開きません）。

この二分原則（two-zone principle）の SSOT は `.ai/DESIGN/ORGOS_TOBE_V3.md` §4.1 です。

## ゾーン分けの原則（ORGOS_TOBE_V3.md §4.1）

1. **トップレベルで二分する**: `.ai/` 直下は「Owner / Manager が読む文書」だけ。実行時データは `.ai/_machine/` へ（`_` プレフィックス = 「人間は通常開かない」の視覚シグナル + ソート先頭）
2. **kernel が literal path で保護するファイルは動かさない**（`PROTECTED_STATE_FILES` 等）
3. **日次ジャーナルはリポジトリ外**（`~/.orgos/activity/` が SSOT。入口は `/org-journal`）
4. **`_machine/` 配下は小文字スネークケースに統一**

## .ai/ 直下に置かれているもの

| 種類 | ファイル / ディレクトリ | 内容 |
|---|---|---|
| プロジェクト定義 | `BRIEF.md` `PROJECT.md` `GOALS.yaml` `JOURNEYS.yaml` | 何を・なぜ作るか |
| 状態台帳 | `TASKS.yaml` `DASHBOARD.md` `DECISIONS.md` `RISKS.md` | 今どうなっているか・何を決めたか |
| Owner 連絡 | `OWNER_INBOX.md` `OWNER_COMMENTS.md` | Owner との非同期やりとり |
| 制御 | `CONTROL.yaml` | フェーズ・権限フラグ |
| 設計・監査 | `DESIGN/` `AUDIT/` | 設計文書・構造監査 |
| 運用知識 | `RUNBOOKS/` `TEMPLATES/` `OIP/` | 手順書・雛形・改善提案 |
| 参照資料 | `RESOURCES/` | Owner 提供のインプット（**read-only**） |
| 機械ゾーン | [`_machine/`](_machine/README.md) | 実行時データ（人間は通常開かない） |

## 書き込みルール

台帳（TASKS.yaml / DECISIONS.md / DASHBOARD.md 等）は手で編集せず、必ず正規の書込パス（org-tools）を通します。
詳細: [.claude/rules/kernel-write-path.md](../.claude/rules/kernel-write-path.md)
