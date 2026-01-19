---
description: 統合担当がマージ順制御してmainへ統合（ゲート遵守）
---

Integratorとして以下を行う：
- review済みタスクのみ対象
- merge順序を制御（クリティカルパス優先）
- squash merge推奨
- mainへのpushは CONTROL.yaml の allow_push_main=true が必要
- main統合前に Owner Reviewポリシー（always_before_merge_to_main等）を確認し、必要なら awaiting_owner=true にして止める
