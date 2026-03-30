# 共通パターン

> プロジェクト全体で使用する共通パターンのインデックス。詳細は各スキルファイルを参照。

---

## パターン一覧

| パターン | 参照先 | 概要 |
|----------|--------|------|
| API レスポンス形式 | [backend-patterns.md](../skills/backend-patterns.md) | `ApiResponse<T>` 統一フォーマット |
| リポジトリパターン | [backend-patterns.md](../skills/backend-patterns.md) | `Repository<T, ID>` インターフェース |
| カスタムフック | [frontend-patterns.md](../skills/frontend-patterns.md) | useDebounce, useFetch, useLocalStorage |
| エラーハンドリング | [backend-patterns.md](../skills/backend-patterns.md) | AppError 階層、Result 型 |
| バリデーション | [backend-patterns.md](../skills/backend-patterns.md) | Zod スキーマ定義 |
| 状態管理 | [frontend-patterns.md](../skills/frontend-patterns.md) | Context + useReducer |
| コーディング規約 | [coding-standards.md](../skills/coding-standards.md) | 命名規則、ファイル構成 |
| リファクタリング | [refactoring-patterns.md](../skills/refactoring-patterns.md) | コードスメル検出、改善手法 |

---

## 適用ルール

- 新規実装時は該当パターンのスキルファイルを参照してから実装する
- パターンからの逸脱がある場合は DECISIONS.md に理由を記録する
- プロジェクト固有のパターンが確立されたら、このインデックスに追加する
