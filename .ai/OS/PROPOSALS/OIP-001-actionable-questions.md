# OIP-001: OWNER_INBOX の質問をアクショナブルに

## Status: Proposed

## Problem

OWNER_INBOX に質問が届いた際、「何を確認するか」は書いてあるが「どうやって確認するか」が書かれていない。

例（改善前）:
```
Azure AD Conditional Access Policyの確認
Teams管理センターでApplication Access Policyの設定確認
Function AppのOutbound IPがブロックされていないか確認
```

Owner は「何をどう確認すればいいか」を自分で調べる必要があり、時間がかかる。

## Solution

質問テンプレートに **How to Check（確認手順）** セクションを追加する。

## Proposed Template

```markdown
### Q-XXX: [質問タイトル]

**Context**: [背景・なぜこの確認が必要か]

**Question**: [具体的な質問]

**How to Check**: [確認手順を具体的に記載]
1. [URL or コマンド] にアクセス
2. [クリックする場所 or 実行コマンド]
3. [確認すべき値・状態]

**Options**: [選択肢がある場合]
1. ...
2. ...

**Recommendation**: [Managerの推奨がある場合]

**Blocked**: [この決定待ちのタスク]
```

## Example (After)

```markdown
### Q-003: Azure AD Conditional Access Policy の確認

**Context**: Teams Graph API の呼び出しが403エラーで失敗しています。
Conditional Access Policy がアプリケーションアクセスをブロックしている可能性があります。

**Question**: 以下のポリシーが Function App のアクセスをブロックしていないか確認してください。

**How to Check**:
1. Azure Portal (https://portal.azure.com) にアクセス
2. Azure Active Directory > Security > Conditional Access に移動
3. 有効なポリシー一覧を確認
4. 「All cloud apps」または「Microsoft Graph」を対象にしたポリシーを探す
5. そのポリシーの「Conditions > Client apps」で「Other clients」がブロックされていないか確認

**Expected Result**:
- ポリシーがない → OK
- ポリシーがあるが Function App の IP/サービスプリンシパルが除外されている → OK
- ポリシーがあり除外されていない → 除外設定が必要

**Blocked**: T-007 (Teams連携機能)
```

## Files to Update

1. `.ai/TEMPLATES/OWNER_INBOX.md` - テンプレート更新
2. `.ai/OWNER_INBOX.md` - 現在のファイル更新（コメント例）
3. `CLAUDE.md` - Manager への指示に「確認手順を具体的に書く」を追加

## Impact

- Owner の確認作業が効率化
- 質問への回答が早くなり、タスクのブロック時間が短縮

---

**Proposed by**: Manager (via Owner feedback)
**Date**: 2026-01-21
