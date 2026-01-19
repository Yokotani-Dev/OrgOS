---
description: 要件/設計/契約/タスクDAGを作る（並列開発の土台）
---

以下を実行：
1) `.ai/PROJECT.md` を読み、要件を明確化
2) 受入基準（DoD）を明文化し、`.ai/PROJECT.md` に反映
3) Contract（API/スキーマ/IF）を定義し、設計ドキュメントの置き場所を決める
4) タスクをDAG化して `.ai/TASKS.yaml` に落とす
5) 危険/不確実性は `.ai/RISKS.md` と `.ai/DECISIONS.md` に入れる（B2はOwner Reviewへ）

Owner判断が必要なら `.ai/OWNER_INBOX.md` を更新し、CONTROL.yaml の awaiting_owner を true にする。
