# User Journey Mapping Skill

> REQUIREMENTS で業務フローを `draft -> confirmed` にするためのスキル。

## When To Use

- `/org-start` または `/org-brief` 後、REQUIREMENTS で DESIGN に進む前
- 追加機能依頼が既存の操作手順、判断順序、例外対応、確認ポイントを変えるとき
- Owner が「何を作るか」より「何を実現したいか」をすり合わせたいとき

## Output

`.ai/JOURNEYS.yaml` に `.claude/schemas/journey.yaml` 準拠の Journey を作る。

## Framework

### 1. As-Is を聞く

Owner が今どう進めているかを、実際の業務手順として聞く。

- 誰が始めるか
- 最初に見る情報は何か
- どこで判断するか
- どこで詰まるか
- 手戻りや二重入力はどこにあるか

### 2. To-Be を作る

OrgOS または対象システム導入後の自然な手順に変換する。

- Owner が最初に何をするか
- システムが代行することは何か
- Owner が確認するポイントはどこか
- 完了の見え方は何か
- 例外時に止めるか、代替手順に進むか

### 3. happy_path を 3-5 ステップにする

通常成功する流れだけを短く固定する。

- 3 ステップ未満なら業務として粗すぎる可能性がある
- 5 ステップを超えるなら複数 Journey に分ける
- UI 名や実装名ではなく、Owner の業務行動で書く

### 4. error_paths を 2-3 件にする

代表的な失敗条件と handling を決める。

- 入力不足
- 権限不足または capability 不足
- 既存データや進行中タスクとの衝突

### 5. Owner 合意を取る

Owner が To-Be と happy_path / error_paths を確認するまで `confirmed` にしてはならない。

合意後に設定する値:

- `sync_status: confirmed`
- `confirmed_at: YYYY-MM-DD`
- `confirmed_by: Owner`

## Additional Feature Flow

追加機能では、まず既存 Journey への影響を判定する。

- `target_flow` 不変: 関連 Journey を task に紐づけて続行
- `target_flow` 変更あり: After Journey を作り、Owner 合意後に実装
- 既存 Journey と矛盾: 既存を `superseded` にし、新 Journey を作る

## Good Journey Criteria

- milestone と紐づいている
- current_flow に痛点がある
- target_flow が Owner の実現したい業務成果に向いている
- happy_path が 3-5 ステップで読める
- error_paths が 2-3 件あり、止める条件と扱いが明確
- `confirmed` は Owner 確認後だけ使われている

## Anti-Patterns

- 機能リストになっている
- 画面遷移図になっている
- コンポーネント設計になっている
- Owner 未確認なのに `sync_status=confirmed`
- As-Is の痛点を聞かずに To-Be を作る
- 追加機能で UX を変えるのに Journey を更新しない

## Minimal Owner Prompt

Owner への質問は 3 問以内に抑える。

1. 今はこの業務をどんな順番で進めていますか。
2. システム導入後は、どの手順になれば「実現したいこと」に近いですか。
3. 失敗時や情報不足時は、止める・確認する・代替手順に進むのどれが自然ですか。

## Handoff

後続タスクに渡すときは次を明記する。

- Journey ID
- related_milestone
- target_flow の要約
- confirmed / draft / superseded の状態
- 実装タスクが守るべき happy_path と error_paths
