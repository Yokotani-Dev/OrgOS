---
description: Review Packet + diff を用いたレビューを実行する（実装と分離）
---

Reviewerとして以下を行う：
- `.ai/REVIEW/REVIEW_QUEUE.md` と Review Packet（`.ai/REVIEW/PACKETS/`）を読み、レビューする
- 指摘は「修正指示」としてTASKに戻す（あなたが直接編集しない）
- セキュリティ/品質/境界逸脱/テスト不足を重点的に確認
- 重大リスクや方針逸脱があれば `.ai/OWNER_INBOX.md` に上げる
