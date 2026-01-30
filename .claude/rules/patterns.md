# 共通パターン（目次）

> プロジェクト全体で使用する共通パターンへのリファレンス。
> 各パターンの詳細は skills/ の該当ファイルを参照すること。

---

## バックエンドパターン → `.claude/skills/backend-patterns.md`

- API レスポンス形式（SuccessResponse / ErrorResponse）
- リポジトリパターン（Repository インターフェース）
- カスタムエラークラス（AppError, NotFoundError, ValidationError 等）
- Zod バリデーション（スキーマ定義、validateRequest ミドルウェア）
- JWT 認証・RBAC

## フロントエンドパターン → `.claude/skills/frontend-patterns.md`

- カスタムフック（useDebounce, useFetch, useLocalStorage）
- 状態管理（Context + useReducer）
- コンポーネント設計（合成パターン、エラーバウンダリ）

## コーディング規約 → `.claude/skills/coding-standards.md`

- 命名規則、ファイル構造
- Result 型パターン
- インポート順序

## セキュリティ → `.claude/rules/security.md`

- OWASP Top 10 対応
- シークレット管理
- 入力バリデーション
- セキュリティヘッダー
