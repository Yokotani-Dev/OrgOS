# Work Order: T-INT-009

## Task
- ID: T-INT-009
- Title: Intelligence 品質修正: HTML タグ残留の修正
- Role: implementer

## Repository
orgos-intelligence (/Users/youyokotani/Dev/Private/orgos-intelligence)

## Problem Analysis

`src/collector/rss.ts` の `stripHtml` 関数で、HTML エンティティデコードとタグ除去の順序が不適切。

### 処理順序の問題:

現在の `stripHtml` (rss.ts:106-119):
1. `<[^>]+>` でタグを除去
2. HTML エンティティをデコード (`&lt;` → `<`, `&gt;` → `>`, `&amp;` → `&`, `&#NNN;` → 文字)

この順序だと:
```
入力: "&lt;p&gt;Hello&lt;/p&gt;"
Step 1: タグ除去 → "&lt;p&gt;Hello&lt;/p&gt;" (エンティティはタグではないので変化なし)
Step 2: デコード → "<p>Hello</p>" ← タグが残る！
```

### Simon Willison の Atom フィード特有の問題:

Simon Willison のブログは Atom フィード (`https://simonwillison.net/atom/everything/`) で `<content type="html">` 要素を使用。
中身が HTML エンティティエンコードされた HTML になっている。

### 修正内容:

`stripHtml` を2パス処理に変更:
1. まず HTML タグを除去（生のタグ）
2. HTML エンティティをデコード
3. **再度タグ除去**（デコードで生まれた新しいタグを除去）
4. 余分な空白を整理

```typescript
function stripHtml(html: string): string {
  let text = html;
  // Pass 1: 生の HTML タグを除去
  text = text.replace(/<[^>]+>/g, " ");
  // Pass 2: HTML エンティティをデコード
  text = decodeEntities(text);
  // Pass 3: デコードで生まれたタグを再度除去
  text = text.replace(/<[^>]+>/g, " ");
  // 余分な空白を整理
  text = text.replace(/\s+/g, " ").trim();
  return text;
}
```

## Acceptance Criteria
- Simon Willison 等の Atom フィードから HTML タグが除去される
- エンティティデコード後の再タグ除去が実装されている
- TypeScript ビルド通過

## Files to Modify
- src/collector/rss.ts (stripHtml 関数の修正)

## Reference
- 設計書: OrgOS リポジトリの .ai/DESIGN/ORGOS_INTELLIGENCE.md Section 4
