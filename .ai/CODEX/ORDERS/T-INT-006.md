# Work Order: T-INT-006

## Task
- ID: T-INT-006
- Title: Intelligence Phase 6: ソース追加の Slack 対話フロー
- Role: implementer

## Context

orgos-intelligence は Cloudflare Workers + Hono の AI トレンド収集 Bot。
現在のソース管理:
- `src/config/sources.ts` にデフォルトソースがハードコード（tier1/tier2/tier3）
- `src/config/index.ts` で KV キャッシュ（`config:current`）に保存、フォールバックでデフォルト使用
- `src/types.ts` に `Source` 型（id, name, url, tier, type）と `IntelConfig` 型

Phase 6 では Slack からソースの追加・削除・一覧表示を対話的に行えるようにする。

## Acceptance Criteria

1. **Slack からソース追加**
   - パターン: `ソース追加 <URL>` or `add source <URL>`
   - Bot が URL を検証し、name と tier を質問
   - Owner が tier を選択（ボタン or テキスト）
   - KV の `config:current` に追加し、次回収集から反映

2. **Slack からソース削除**
   - パターン: `ソース削除 <名前 or ID>` or `remove source <name or ID>`
   - 削除対象を確認メッセージで表示
   - Owner が確認後に削除

3. **ソース一覧表示**
   - パターン: `ソース一覧` or `list sources`
   - Tier 別にフォーマットして表示

4. **KV に設定が保存され、次回収集に反映される**

## Implementation Guide

### 1. ソース管理コマンドハンドラー（src/slack/source-manager.ts）- 新規作成

Slack メッセージからソース管理コマンドを検出・処理するモジュール。

**コマンドパターン:**

| パターン | アクション |
|----------|-----------|
| `ソース追加 <URL>` / `add source <URL>` | ソース追加フロー開始 |
| `ソース削除 <名前>` / `remove source <name>` | ソース削除フロー開始 |
| `ソース一覧` / `list sources` | ソース一覧表示 |

**ソース追加フロー:**

```
1. URL を受け取る
2. URL の基本バリデーション（https:// で始まるか、到達可能か）
3. Bot がメッセージで質問:
   「ソース名を教えてください（例: Anthropic Blog）」
   → Owner がテキストで回答
4. Bot が tier を質問（ボタン表示）:
   「Tier を選択してください」
   [Tier 1: 公式] [Tier 2: コミュニティ] [Tier 3: 実践知]
5. Owner がボタンをクリック
6. config を KV に保存
7. 完了メッセージ: 「<name> を Tier <N> として追加しました。明日のレポートから反映されます。」
```

**簡易版の実装（推奨）:**

対話フローは複雑なため、1メッセージで全情報を受け取る簡易版を先に実装:

```
パターン: ソース追加 <URL> <名前> <tier1|tier2|tier3>
例: ソース追加 https://example.com/feed Example Blog tier3
```

tier が省略された場合はデフォルトで tier3 を使用。
名前が省略された場合は URL のドメイン名を使用。

### 2. events.ts の拡張

`handleSlackEvent` にソース管理コマンドの検出を追加:

```typescript
// ソース管理コマンドの検出（スレッド外でも動作）
const sourceAddMatch = text.match(/^(ソース追加|add\s+source)\s+(\S+)(.*)$/i);
if (sourceAddMatch) {
  await handleSourceAdd(sourceAddMatch[2], sourceAddMatch[3]?.trim(), channelId, threadTs, env, client);
  return;
}

const sourceRemoveMatch = text.match(/^(ソース削除|remove\s+source)\s+(.+)$/i);
if (sourceRemoveMatch) {
  await handleSourceRemove(sourceRemoveMatch[2].trim(), channelId, threadTs, env, client);
  return;
}

const sourceListMatch = text.match(/^(ソース一覧|list\s+sources)$/i);
if (sourceListMatch) {
  await handleSourceList(channelId, threadTs, env, client);
  return;
}
```

**重要:** スレッド外（thread_ts がない）のメッセージでもソース管理コマンドは処理する必要がある。
現在の events.ts は `if (!payload.event.thread_ts) { return; }` でスレッド外を無視している。
ソース管理コマンドはこのチェックの前に配置するか、thread_ts なしでも動作するようにする。

### 3. Block Kit for tier 選択

ボタンによる tier 選択を提供する場合は `src/slack/blocks.ts` に追加:

```typescript
export function buildTierSelectBlocks(url: string, name: string): Block[] {
  return [
    {
      type: "section",
      text: { type: "mrkdwn", text: `*${name}* (${url}) の Tier を選択してください:` },
    },
    {
      type: "actions",
      elements: [
        { type: "button", text: { type: "plain_text", text: "Tier 1: 公式" }, action_id: `source_tier_tier1_${encodeId(url)}`, value: JSON.stringify({ url, name, tier: "tier1" }) },
        { type: "button", text: { type: "plain_text", text: "Tier 2: コミュニティ" }, action_id: `source_tier_tier2_${encodeId(url)}`, value: JSON.stringify({ url, name, tier: "tier2" }) },
        { type: "button", text: { type: "plain_text", text: "Tier 3: 実践知" }, action_id: `source_tier_tier3_${encodeId(url)}`, value: JSON.stringify({ url, name, tier: "tier3" }) },
      ],
    },
  ];
}
```

### 4. interactions.ts の拡張

`source_tier_` で始まるアクションの処理を追加:

```typescript
if (action.action_id.startsWith("source_tier_")) {
  const { url, name, tier } = JSON.parse(action.value);
  await handleSourceTierSelect(url, name, tier, channelId, threadTs, env, client);
}
```

### 5. ソース一覧の Block Kit

```
📡 情報ソース一覧

*Tier 1 (公式)* — 5件
  • Anthropic Blog (RSS)
  • OpenAI Blog (RSS)
  • ...

*Tier 2 (コミュニティ)* — 2件
  • Hacker News (API)
  • ...

*Tier 3 (実践知)* — 2件
  • Simon Willison's Blog (RSS)
  • ...

合計: 9件
```

### 6. config/index.ts の拡張

ソース追加・削除のヘルパー関数を追加:

```typescript
export async function addSource(kv: KVNamespace, source: Source): Promise<void> {
  const config = await getConfig(kv);
  const tierKey = source.tier; // "tier1" | "tier2" | "tier3"

  // 重複チェック（URL ベース）
  const allSources = getAllSources(config);
  if (allSources.some(s => s.url === source.url)) {
    throw new Error(`ソース ${source.url} は既に登録されています`);
  }

  config.sources[tierKey].push(source);
  await saveConfig(kv, config);
}

export async function removeSource(kv: KVNamespace, idOrName: string): Promise<Source | null> {
  const config = await getConfig(kv);

  for (const tierKey of ["tier1", "tier2", "tier3"] as const) {
    const index = config.sources[tierKey].findIndex(
      s => s.id === idOrName || s.name.toLowerCase() === idOrName.toLowerCase()
    );
    if (index !== -1) {
      const [removed] = config.sources[tierKey].splice(index, 1);
      await saveConfig(kv, config);
      return removed;
    }
  }

  return null;
}
```

## 注意事項

- TypeScript ビルドが通ること（`npx tsc --noEmit`）
- 既存の Phase 1-5 の機能を壊さないこと
- URL のバリデーション（https:// 必須、長さ制限）
- ソース ID はURL から自動生成（ドメイン + パスのスラッグ）
- エラーハンドリング（KV 失敗、不正な URL 等）
- 入力のサニタイズ（Slack メッセージからの入力）

## Reference

- 設計書: OrgOS リポジトリの .ai/DESIGN/ORGOS_INTELLIGENCE.md（Section 4, 6.2）
- 既存実装: src/config/sources.ts, src/config/index.ts
