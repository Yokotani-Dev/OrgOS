# outputs/

> 成果物（Artifacts）専用フォルダ

---

## 目的

このフォルダは、OrgOS プロジェクトで生成される成果物を格納します。

**重要な原則:**
- **資料（resources/）は直接編集しない** → 複製して outputs/ に配置してから編集
- 成果物と資料を明確に区別して管理
- git で履歴を管理（リポジトリに含める）

---

## フォルダ構造

### 日付別

```
outputs/
├── 2026-01-23/
│   ├── sample1.ts
│   ├── sample2.md
│   └── README.md
└── 2026-01-24/
    └── report.pdf
```

**用途:**
- 日常的な作業成果物
- ad-hoc の依頼で生成したファイル
- 特定のタスクに紐付かない成果物

---

### タスクID別

```
outputs/
├── T-OS-004/
│   ├── implementation.ts
│   ├── tests.ts
│   └── README.md
└── T-OS-007/
    └── documentation.md
```

**用途:**
- タスクに紐付く成果物
- 実装コード、テスト、設計ドキュメントなど
- レビュー対象の成果物

---

## 使い方

### Manager による配置

Manager（Claude Code）が自動的に成果物を配置します。

```
1. 資料を複製
   resources/samplecode/example.ts
   → outputs/2026-01-23/example.ts

2. 編集・加工

3. 完成した成果物を outputs/ に配置
```

### Codex worker による配置

Codex worker が実装した成果物は、Work Order の指示に従って outputs/ に配置されます。

```
.ai/CODEX/ORDERS/T-XXX.md の指示例:
- 成果物を outputs/T-XXX/ に配置してください
- 資料は resources/ から複製してください
```

---

## .gitignore

**outputs/ はリポジトリに含めます（.gitignore に追加しない）**

理由:
- 成果物の履歴が残る
- チーム間で共有できる
- バックアップとして機能する

一時ファイルやビルド成果物のみを除外する場合:

```gitignore
# 一時ファイルのみ除外
outputs/**/*.tmp
outputs/**/*.log
outputs/**/node_modules/
```

---

## 参考

- [CLAUDE.md](../CLAUDE.md) - 成果物管理ルール
- [.claude/agents/AGENTS.md](../.claude/agents/AGENTS.md) - Codex worker の資料複製フロー
