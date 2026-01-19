# OrgOS 変更履歴

このファイルはOrgOSの各バージョンで何が変わったかを日本語で記録します。

---

## v0.2.0 (2025-01-19)

### 追加
- **`/org-release`**: ワンコマンドでOrgOSをリリース（変更自動検出、VERSION/CHANGELOG自動更新、バージョン選択）

---

## v0.1.0 (2025-01-19)

### 追加
- **`/org-export`**: OrgOSのコア部分を他プロジェクトにエクスポートするコマンド
- **`/org-import`**: エクスポートしたOrgOSを別プロジェクトにインポートするコマンド
- **バージョン管理**: `VERSION.yaml`で内部管理、`CHANGELOG.md`で変更履歴を追跡

### 含まれる機能
- `/org-start`: OrgOSプロジェクトの初期化
- `/org-brief`: 対話形式でBRIEF.mdを整形
- `/org-kickoff`: プロジェクト開始時のヒアリング
- `/org-plan`: 要件→設計→タスクDAG作成
- `/org-tick`: 1Tick進行（台帳更新→タスク分配→レビュー→次の手）
- `/org-review`: Review Packet + diff を用いたレビュー
- `/org-integrate`: マージ順制御してmainへ統合
- `/org-os-retro`: OrgOSの運用を振り返り、改善提案（OIP）を作る

---

## 今後の予定
- プロジェクト固有設定とOrgOSコアの分離改善
- インポート時の差分マージ機能
