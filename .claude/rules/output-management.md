# 生成物配置ルール

> 生成物（コード、ドキュメント、設計書等）の配置場所を統一する

---

## 原則

**生成物は必ず決められた場所に配置する。場所が不明な場合はルールに従って判断する。**

---

## RESOURCES への書き込み禁止 (Iron Law)

- `.ai/RESOURCES/` 配下は **read-only**
- Owner が手動編集した元ファイルが格納されており、AI が上書きすると復元不可
- 成果物を修正する場合は `outputs/` にバージョンを上げて出力
- `.ai/RESOURCES/` はあくまで参照元として Read するだけ

## インプットリソース受領時のフロー (Iron Law)

> Owner が **どこに置いても** Manager が拾い上げて取り込む運用は [resource-intake-triage.md](resource-intake-triage.md) を参照（毎 Tick の triage 走査を含む）。本セクションは受領時の 3 ステップ手順の SSOT。

Owner からファイルを受け取ったら、以下の 3 ステップを即座に実行:

### Step 1: 台帳登録

`.ai/RESOURCES/README.md` の「外部インプットファイル管理台帳」に追加:

| ファイル名 | 配置先 | 提供元 | 用途 | 受領日 |
|-----------|--------|--------|------|--------|

### Step 2: サブディレクトリ配置

- ドキュメント類 → `.ai/RESOURCES/docs/inputs/`
- デザイン類 → `.ai/RESOURCES/designs/`
- スキル素材 → `.ai/RESOURCES/skills/`

### Step 3: リネーム (必要時)

- 日本語ファイル名はそのまま可
- 日付未含なら `YYYYMMDD_` プレフィックス推奨
- バージョン番号はそのまま保持

---

## 配置先の決定フロー

```
生成物の種類は？
│
├─ プロジェクトのソースコード（src/, lib/ 等）
│   → プロジェクトのソースディレクトリに直接配置
│   → 例: src/auth/login.ts, lib/utils.ts
│
├─ 設計ドキュメント
│   → .ai/DESIGN/ に配置
│   → 例: .ai/DESIGN/ARCHITECTURE.md, .ai/DESIGN/API_CONTRACT.md
│
├─ OrgOS 台帳
│   → .ai/ に配置（既存ファイルを更新）
│   → 例: .ai/TASKS.yaml, .ai/DECISIONS.md
│
├─ テストコード
│   → テストディレクトリに配置（tests/, __tests__/, *.test.ts 等）
│   → プロジェクトの規約に従う
│
├─ 参考資料のカスタマイズ版（サンプルコードの改変等）
│   → outputs/ に配置
│   → 日付別: outputs/YYYY-MM-DD/
│   → タスク別: outputs/T-XXX/
│
├─ 一時的な調査・分析結果
│   → outputs/YYYY-MM-DD/research/ に配置
│
└─ 上記に該当しない
    → Owner に配置先を確認
    → デフォルト: outputs/YYYY-MM-DD/
```

---

## 禁止事項

- プロジェクトルートに直接ファイルを散らかさない
- .ai/ 以外の場所に OrgOS 関連ファイルを作らない
- outputs/ に入れるべきファイルをプロジェクトルートに置かない
- 同じ種類のファイルを異なる場所に置かない（一貫性を保つ）

---

## エージェント向けチェックリスト

ファイルを生成する前に確認:

1. このファイルはどのカテゴリに属するか？
2. 既存のファイルと同じカテゴリのファイルはどこに配置されているか？
3. 配置先のディレクトリは存在するか？（なければ作成）
4. ファイル名は規約に従っているか？
5. Owner からファイルを受け取った場合、台帳登録 → 配置 → リネームを先に実行したか？
6. `.ai/RESOURCES/` を edit/write していないか？

---

## 参考資料

- [outputs/README.md](../../outputs/README.md) - 成果物管理ガイド
- [.claude/agents/CODEX_WORKER_GUIDE.md](../agents/CODEX_WORKER_GUIDE.md) - Codex worker の資料管理フロー
