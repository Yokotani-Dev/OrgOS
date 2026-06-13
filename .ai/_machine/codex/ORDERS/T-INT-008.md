# Work Order: T-INT-008

## Task
- ID: T-INT-008
- Title: Intelligence 品質修正: HN フィルタリング精度改善
- Role: implementer

## Repository
orgos-intelligence (/Users/youyokotani/Dev/Private/orgos-intelligence)

## Problem Analysis

`src/collector/hackernews.ts` の `isAiRelated` 関数がキーワードの部分一致（`titleLower.includes(kw)`）で判定しているため、AI 無関係の記事が大量に通過している。

### 具体的な問題:

1. **"ai" の部分一致**: `"email"`, `"fair"`, `"repair"`, `"maintain"`, `"ukraine"` 等に一致
2. **"agent" の部分一致**: `"reagent"` 等に一致
3. **"prompt" の部分一致**: `"prompted"`, `"impromptu"` 等に一致
4. **"rag" の部分一致**: `"outrage"`, `"storage"`, `"garage"` 等に一致
5. **watchTopics のトークン化** (`hackernews.ts:103-108`): `split(/[\/\s,]+/)` で分割し3文字以上のトークンを部分一致検索。`"patterns"`, `"code"`, `"testing"` 等の一般語が通過してしまう

### 修正内容:

1. **AI_KEYWORDS の短いキーワードに単語境界マッチを適用**:
   - 4文字以下のキーワード (`"ai"`, `"llm"`, `"rag"`, `"mcp"`) は `\b` 付き正規表現で判定
   - 5文字以上のキーワード (`"machine learning"`, `"anthropic"`) は部分一致のまま（十分に specificity がある）

2. **watchTopics のストップワードリスト導入**:
   - 除外する一般語: `"code"`, `"testing"`, `"patterns"`, `"review"`, `"safety"`, `"driven"`, `"development"` 等
   - トークン長の最小値を3→5に引き上げるか、ストップワードリストで除外

3. **HN スコアの最低閾値を引き上げ**:
   - 現在の閾値を確認し、低スコアの記事（ノイズ）を除外

## Acceptance Criteria
- AI 無関係の HN 記事が除外される
- "ai" 等の短いキーワードが単語境界マッチに変更されている
- watchTopics のトークン化でストップワードが除外されている
- TypeScript ビルド通過

## Files to Modify
- src/collector/hackernews.ts (isAiRelated 関数の改善)

## Reference
- 設計書: OrgOS リポジトリの .ai/DESIGN/ORGOS_INTELLIGENCE.md Section 4
