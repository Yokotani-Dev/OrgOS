# Work Order: T-OS-181F

## Task
- ID: T-OS-181F
- Title: bind-request.sh の日本語 multibyte 処理バグ修正
- Role: implementer
- Priority: P0 (動作不能バグ)

## Allowed Paths
- `scripts/session/bind-request.sh` (編集)
- `scripts/session/similarity-score.sh` (存在すれば編集)
- `.ai/CODEX/RESULTS/T-OS-181F.md`

## Dependencies
- T-OS-181: done (本修正対象)

## Context

### 発見したバグ
```
echo "このログから error 抽出して" | bash scripts/session/bind-request.sh
# → -:18: invalid multibyte char (US-ASCII) (大量)
```

Ruby が UTF-8 encoding を認識していない。日本語入力を含む依頼は全て動作不能。
これが修正されないと OrgOS 真髄 (T-OS-182) が機能しない。

## Acceptance Criteria

### F1: multibyte 対応修正
- Ruby の `magic comment` を追加: `# encoding: utf-8` (スクリプト冒頭)
- または `ruby -E utf-8` で呼び出し
- または `LC_ALL=en_US.UTF-8 ruby ...` で環境変数設定
- または Python3 への書き換え (より堅牢)

### F2: 検証
```bash
# 日本語入力
echo "このログから error 抽出して" | bash scripts/session/bind-request.sh
# 期待: JSON 出力 (エラーなし)

echo "T-OS-180 の設計を確認したい" | bash scripts/session/bind-request.sh
echo "新しいサービス X を作りたい" | bash scripts/session/bind-request.sh
```

3 ケース全てで適切な JSON 出力を確認。

### F3: 退行防止
既存 ASCII 入力も引き続き動作:
```bash
echo "check the status" | bash scripts/session/bind-request.sh
```

### F4: エラーハンドリング改善
- 入力が空の時の graceful handling
- 壊れた YAML 読込時の対応
- TASKS.yaml 未存在時の fallback

## Instructions

1. scripts/session/bind-request.sh を読む
2. encoding 設定を修正
3. 3 ケースでテスト
4. **重要**: 他ファイル編集禁止

## Report

1. 修正内容 (encoding 設定の方法)
2. 3 ケースの実行サンプル
3. ステータス: DONE / DONE_WITH_CONCERNS / BLOCKED
