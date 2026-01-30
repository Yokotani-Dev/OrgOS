# パフォーマンスルール

> Claude Code のパフォーマンス最適化と効率的な使用方法

---

## モデル選択ガイダンス

モデル選択（Haiku/Sonnet/Opus）の詳細は [.claude/rules/agent-coordination.md](agent-coordination.md) の「モデル選択ガイダンス」セクションを参照。

---

## コンテキストウィンドウの最適化

コンテキスト使用率の監視・セッション終了提案の詳細は [.claude/rules/session-management.md](session-management.md) を参照。

### 読み込みの効率化

```
❌ 悪い例: 全ファイルを読み込む
Read("src/components/")  // ディレクトリ全体

✅ 良い例: 必要なファイルだけ読む
Glob("src/components/**/*.tsx")  // まず一覧取得
Read("src/components/Button.tsx")  // 必要なものだけ
```

### 大きなファイルの扱い

```typescript
// 大きなファイルは分割して読む
Read({
  file_path: "src/large-file.ts",
  offset: 100,  // 100行目から
  limit: 50     // 50行だけ
});
```

---

## レスポンス時間の最適化

### 並列実行の活用

```typescript
// 独立したタスクは並列で
Task({ subagent_type: "org-reviewer", prompt: "src/auth/" });
Task({ subagent_type: "org-reviewer", prompt: "src/api/" });
Task({ subagent_type: "org-reviewer", prompt: "src/utils/" });
// → 3つ同時に実行、合計時間は最長のタスク分のみ
```

### バックグラウンド実行

```typescript
// 長時間タスクはバックグラウンドで
Task({
  subagent_type: "org-e2e-runner",
  prompt: "全E2Eテスト実行",
  run_in_background: true
});

// 他の作業を続行可能
```

### 早期終了

```
不要な作業は早めに切り上げる:
- 明らかにスコープ外の調査は中止
- 答えが見つかったら深掘りしない
- 完璧を求めず「十分良い」で進む
```

---

## コスト最適化

### モデル選択によるコスト削減

```
Opus 1回 ≈ Sonnet 4回 ≈ Haiku 20回

最適化の例:
1. まず Haiku で情報収集
2. Sonnet で実装
3. Opus は本当に必要な時だけ
```

### 無駄を減らす

```yaml
# 避けるべきパターン
- 同じファイルを何度も読む → キャッシュを活用
- 不要な詳細を出力 → 必要な情報だけ返す
- 全てに Opus を使う → タスクに応じて使い分け

# 推奨パターン
- 事前に必要なファイルを特定してから読む
- 回答は簡潔に
- 複雑なタスクのみ Opus を使用
```

---

## パフォーマンス監視

### 気をつけるべき兆候

```
⚠️ 遅くなっている兆候:
- 同じファイルを何度も読んでいる
- 不要な探索を繰り返している
- Opus を頻繁に使っている

⚠️ コストが増えている兆候:
- 長い出力を繰り返し生成
- 全てのタスクで Opus を使用
- 不要な並列実行
```

### 最適化のヒント

```
1. タスクを明確に定義 → 無駄な探索を防ぐ
2. 適切なモデルを選択 → コストとのバランス
3. 結果をキャッシュ → 同じ処理を繰り返さない
4. 並列実行を活用 → 待ち時間を削減
```

---

## 参考資料

- [.claude/rules/agent-coordination.md](agent-coordination.md) - エージェント協調パターン
- [.claude/commands/org-tick.md](../commands/org-tick.md) - 自動選択ロジック
