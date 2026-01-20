# ARTIFACTS - 成果物格納ディレクトリ

> プロジェクト実行中に生成される成果物を格納する場所。

---

## ディレクトリ構成

```
ARTIFACTS/
  README.md       # この説明
  designs/        # 設計成果物（Contract, アーキテクチャ図, インターフェース定義等）
  plans/          # 実装計画・タスク分割結果・見積もり
  outputs/        # 最終成果物（生成コード, ビルド成果物, エクスポート等）
  reports/        # テスト結果・レビュー要約・分析レポート
```

---

## RESOURCES/ との違い

| ディレクトリ | 役割 | 例 |
|-------------|------|-----|
| `RESOURCES/` | **入力**（参照資料） | 既存API仕様書, Figmaデザイン, 参考コード |
| `ARTIFACTS/` | **出力**（生成した成果物） | 設計書, 実装計画, テスト結果 |

---

## 使い方

### 1. 設計成果物 → `designs/`

```bash
# Contract定義
.ai/ARTIFACTS/designs/auth-contract.md

# アーキテクチャ図
.ai/ARTIFACTS/designs/system-architecture.md
```

### 2. 実装計画 → `plans/`

```bash
# タスク分割結果
.ai/ARTIFACTS/plans/task-breakdown-20260120.md

# 実装計画
.ai/ARTIFACTS/plans/implementation-plan.md
```

### 3. 最終成果物 → `outputs/`

```bash
# 生成したコードのスナップショット
.ai/ARTIFACTS/outputs/generated-api-client/

# ビルド成果物
.ai/ARTIFACTS/outputs/build-20260120/
```

### 4. レポート → `reports/`

```bash
# テスト結果
.ai/ARTIFACTS/reports/test-results-20260120.md

# レビュー要約
.ai/ARTIFACTS/reports/review-summary.md
```

---

## 命名規則

- 日付を含める場合: `{name}-YYYYMMDD.md`
- タスクに紐づく場合: `{task-id}-{name}.md`
- 例: `T001-auth-contract.md`, `test-results-20260120.md`

---

## 注意事項

- **秘匿情報を含むファイルは配置しない**（.env, credentials 等）
- 大きなバイナリファイルは Git LFS の利用を検討
- プロジェクト完了後、必要に応じて `_archive/` へ移動
