# OIP-008: Codex CLI を実装エンジンとして統合

> Status: APPROVED
> Author: Owner
> Date: 2026-01-28

---

## 背景

OrgOS の `org-implementer` エージェントは現在 Claude Code のサブエージェントとして動作しているが、
Owner から「OpenAI Codex CLI の方が実装品質が高い」というフィードバックがあった。

Codex CLI (`codex exec`) はローカルにインストール済みで、非インタラクティブ実行が可能。

## 提案

`org-implementer` の実装エンジンとして Codex CLI を選択可能にする。

### アーキテクチャ

```
Manager (Claude Code)
  ├── 設計・計画・レビュー → Claude Code サブエージェント（従来通り）
  └── 実装 → Codex CLI (codex exec)
       ├── Work Order を prompt として渡す
       ├── sandbox: workspace-write（CONTROL.yaml で設定済み）
       └── 結果を Manager が検証・台帳に記録
```

### 実行フロー

1. Manager が Work Order（実装指示）を生成
2. `codex exec -s workspace-write "Work Order の内容"` を Bash 経由で実行
3. Codex が実装を実行
4. Manager が結果を検証（ビルド、テスト、レビュー）
5. 台帳を更新

### CONTROL.yaml の既存設定を活用

```yaml
codex:
  auto_exec: false          # true にすると Manager が自動実行
  sandbox: "workspace-write"
  approval: "on-request"
```

## メリット

- 実装品質の向上（Owner の実感に基づく）
- Claude Code の強み（設計・レビュー・台帳管理）と Codex の強み（実装）を組み合わせ
- 既存の CONTROL.yaml 設定を活用できる

## デメリット・リスク

- OpenAI API キーが必要（コスト増）
- 2つの LLM を使うことによる一貫性の課題
- Codex の出力が OrgOS の規約に沿わない可能性
- デバッグが複雑化する可能性

## 実装計画

### Phase 1: 検証
- Codex CLI の `exec` コマンドで実装タスクを実行し、品質を検証
- Work Order → codex exec のパイプラインを構築

### Phase 2: 統合
- `org-implementer` エージェントを更新し、Codex CLI を呼び出す仕組みを追加
- CONTROL.yaml の `codex.auto_exec` フラグで自動実行を制御

### Phase 3: 最適化
- Work Order のフォーマット最適化
- エラーハンドリングの強化
- レビューフローとの統合

## 参考

- 既存の Codex 設定: CONTROL.yaml `codex` セクション
- 既存の owner_role: `codex-implementer`（TASKS.yaml で既に使用中）
