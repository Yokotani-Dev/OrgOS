---
description: 資料（pptx/見せるmd）を表現規約に従って作成・編集する。着手前に必ず presentation-material-standards を全文読み込む
argument-hint: [作成・編集したい資料の内容や指示]
---

# /org-material — 資料作成（表現規約 強制適用）

社内・クライアント向けの資料（`.pptx` / 見せる `.md`）を、表現規約に必ず従って作成・編集する。
**このコマンドは、コンテキストの状態に関わらず、着手前に表現規約を強制的に読み込む。**

---

## Iron Law（最優先・例外なし）

1. **最初に** `.claude/rules/presentation-material-standards.md` を **Read ツールで全文読み込む**。
   - 「もうコンテキストにある」と仮定しない。毎回必ず読む。
2. 読み込んだ表現規約（基本文体・タイトル/本文ルール・禁止表現・曖昧語・記号・出力前の内部チェック10項目）を全面適用する。
3. 入力に混在する「顧客に見せる内容」と「作業指示・背景説明」を区別し、作業指示は資料に表示しない。
4. 出力前に「出力前の内部チェック」10項目を全件確認し、該当箇所を修正する（チェック結果や修正過程は出力しない）。

---

## 引数

- `$ARGUMENTS` — 作成・編集したい資料の内容や指示（省略時は対話でヒアリング）

---

## 実行手順

1. **表現規約を読む（ブロッキング）**
   - `Read .claude/rules/presentation-material-standards.md`（全文）。これを完了するまで資料に着手しない。

2. **入力リソースの取り込み**
   - Owner から既存資料（pptx / pdf / 画像 等）を受領していれば、[resource-intake-triage.md](../rules/resource-intake-triage.md) と [output-management.md](../rules/output-management.md) に従い `.ai/RESOURCES/` へ取り込む（移動 → 台帳登録 → リネーム）。

3. **OrgOS フローに載せる**
   - 資料作成を `scripts/org/update-task.py` でタスク登録（[kernel-write-path.md](../rules/kernel-write-path.md)）。

4. **作成・編集**
   - 表現規約を適用して資料を作成/編集する。生成物の配置は [output-management.md](../rules/output-management.md) に従う（`outputs/` 配下が原則）。

5. **出力前の内部チェック**
   - 表現規約の「出力前の内部チェック」10項目を全件適用し、該当箇所を修正する。

6. **報告**
   - 生成物のパスと、適用した主要な規約ポイントを簡潔に報告する。

---

## 参照

- `.claude/rules/presentation-material-standards.md` — 表現規約（SSOT・本コマンドの根拠）
- `.claude/rules/output-management.md` — 生成物の配置ルール
- `.claude/rules/resource-intake-triage.md` — 入力ファイルの取り込み
