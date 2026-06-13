# OrgOS 理想形批評 — 第3 AI 視点

> 回答者: GPT-5.5 Pro
> 受領日: 2026-05-14
> 入力 prompt: `.ai/REVIEW/T-OS-400/external-ai-prompt.md`
> 注意: Manager 視点 (`manager-vision.md`) は読まれていない前提で書かれている

---

## 自己紹介

私は GPT-5.5 Pro。基礎知識は 2025-08 までだが、本回答は 2026-05-14 の依頼文と、必要な範囲の公式資料確認を踏まえて書く。Manager 側の視点ドキュメントは読んでいない前提で、OrgOS の外部 reviewer として率直に評価する。

## Q1. patch-on-patch の根本原因

根本原因は「事故対応が甘い」ではない。OrgOS はそもそも、制御すべき対象を取り違えている。

第一に、policy と enforcement を混同している。Markdown rule に「Codex は commit してはいけない」と書くのは、社員規則に「金庫を開けてはいけない」と書くのに近い。意味はあるが、鍵ではない。AI agent は自然言語 policy を確率的に参照する実行主体であり、権限境界そのものではない。OrgOS は「ルールを読んだ LLM が従う」ことを中核制御に置きすぎている。これは OS ではなく、願望を書いた運用マニュアルである。

第二に、状態と並行性が first-class ではない。事故 A/B は branch consistency の局所バグではなく、「複数 session / 複数 worker / 共有 repo / mutable branch / 自動 commit」という並行システムを、逐次システムの拡張として扱った結果だ。タスクは `.ai/TASKS.yaml` に存在するが、作業ディレクトリ、branch、path lease、commit 権限、heartbeat、所有者、競合範囲が一体の transactional resource として扱われていない。つまり task は管理されているが、task が占有する現実の資源は管理されていない。

第三に、Manager が「司令塔」「実行者」「監査者」「記録者」を兼ねている。これは組織論としてもシステム設計としても危険である。判断した主体が実行し、実行した主体が検証し、検証した主体が ledger を更新するなら、失敗時にどこで保証が破れたか分からない。LLM は柔軟な planner としては有用だが、safety kernel には向かない。

第四に、incident-driven design になっている。事故が起きるたびに「その事故を防ぐ rule」を追加するため、設計が一般化されない。今回の T-OS-390〜399 も、個別には妥当なものがある。しかし束にした瞬間、「また制御面を厚くしているだけ」に見える。必要なのは「main 直 commit 禁止」「allowed_paths 衝突 pre-flight」より上位の原則、例えば「worker は commit 権限を持たない」「session は共有 worktree を持たない」「状態遷移は LLM ではなく broker が実行する」である。

第五に、OrgOS は自律性を過大評価し、調停を過小評価している。複数 AI を協調させるシステムでは、賢い agent よりも、馬鹿でも破れない境界のほうが重要だ。Manager が優秀でも、worker が優秀でも、共有 mutable state に対する排他制御が弱ければ事故は起きる。

## Q2. OS アナロジーの妥当性

「OS」というアナロジーは、野心としては分かる。process、permission、scheduler、filesystem、syscall、audit log のような概念は、複数 agent 運用に確かに対応する。しかし現状の OrgOS を OS と呼ぶのはかなり危うい。OS と名乗るなら、kernel に相当する強制境界が必要だ。現状は markdown + YAML + shell script + LLM discipline の集合であり、実態は「agent orchestration harness」または「AI 開発運用 framework」に近い。

より適切なアナロジーは 3 つある。

一つ目は agent harness。agent にどの tool を渡すか、どの directory を触らせるか、どの成果物を返させるかを管理する実行枠である。このアナロジーなら、設計上の主語は「ルール」ではなく「capability」になる。

二つ目は workflow engine。intent を plan に変換し、task を schedule し、worker に投げ、検証し、merge する。これなら state machine、lease、retry、compensation、audit が主役になる。

三つ目は control plane。Owner intent を受け取り、worker execution plane に安全な命令だけを流す。Kubernetes 的な比喩に近いが、OrgOS の場合も「望ましい状態」と「実行中の状態」を分けるほうがよい。

アナロジーを変えると設計選択も変わる。OS と名乗るなら、Iron Law を増やすのではなく、kernel boundary を作る必要がある。framework と見るなら、拡張性よりも最小 API と失敗時の復旧性を優先する。workflow engine と見るなら、YAML を人間が編集するのではなく、状態遷移を database transaction として扱う。control plane と見るなら、Manager は実行者ではなく desired-state compiler になる。

私の結論は、OrgOS は「OS」を名乗るにはまだ enforcement が弱すぎる。名前を変えるか、名前に見合う kernel を作るべきだ。

## Q3. 状態管理: 複数 YAML/MD vs 別解

7 個以上の SSOT がある、という時点で SSOT ではない。Single Source of Truth は単数だから SSOT なのであって、「それぞれ別の真実を持つファイル群」は distributed notes である。YAML/Markdown は可読性に優れるが、transaction、locking、query、schema migration、concurrent update には弱い。52 active task と数百 archive task の規模では、手動 + script による整合性維持は長期的に破綻する。

別解として、私は「operational state は SQLite、audit は append-only event log、YAML/Markdown は generated view」を推す。

案 A は SQLite 中心。`tasks`, `runs`, `workers`, `leases`, `artifacts`, `decisions`, `events` のような table を持ち、Manager も Codex も直接 YAML を書かず、CLI 経由で状態遷移を発行する。SQLite は単一ファイルで扱いやすく、WAL mode も公式に提供されており、ローカル repo 内の軽量 DB として現実的である。SQLite の WAL は database file 側の journal mode として扱われ、複数 connection の運用にも向く。([SQLite][1]) 欠点は、Markdown より実装コストが上がることと、migration 設計が必要になること。

案 B は event sourcing。すべての変化を `TaskCreated`, `LeaseAcquired`, `WorkerStarted`, `PatchProposed`, `VerificationPassed`, `CommitIntegrated` のような event として append-only に記録し、現在状態は projection として生成する。Event sourcing の基本は、状態変化を event object として記録し、それを再処理して状態を再構築できるようにすることだ。([martinfowler.com][2]) これは OrgOS の監査性と相性がよい。欠点は、projection のバグ、event schema の versioning、replay の運用が増えること。

案 C は GitHub Issues / Linear / 専用 task DB に寄せること。人間の UX は改善するが、local agent execution との密結合が必要な OrgOS では、branch/worktree/allowed paths/locks まで一体管理しにくい。

案 D は「元に戻す」、つまり active task を 10 個以下に絞り、単一 YAML だけで運用すること。これは意外に有力だ。複数 agent 並列を本気でやらないなら、DB 化よりスコープ削減のほうが正しい。ただし Owner の真のニーズが「複数 AI 協調」なら、この案は目標を諦める選択である。

推奨は、SQLite + append-only event log の二層構成。`.ai/TASKS.yaml`, `.ai/DASHBOARD.md`, `.ai/DECISIONS.md` は読み物として生成する。人間も LLM も、生成物を編集してはならない。

## Q4. AI エージェントへの信頼境界

AI agent に対する natural language policy は、行動誘導としては有効だが、権限制御としては信用してはいけない。特に git commit、branch checkout、secret access、network access、filesystem write のような不可逆・高リスク操作は、policy ではなく capability boundary で縛るべきだ。

使い分けは単純である。

低リスクで可逆な判断、例えば「報告文を簡潔にする」「Handoff Packet をこの schema で書く」は markdown policy でよい。中リスクの判断、例えば「この path に write してよいか」「この task は approval required か」は policy-as-code にする価値がある。高リスク操作、例えば `git commit`, `git checkout main`, `rm -rf`, secret 読み取り、本番 deploy は物理的・機械的に拒否すべきである。

物理境界としては、per-task worktree、read-only mount、allowed path 以外の write deny、worker からの `.git` 操作遮断、git binary wrapper、commit 権限を持つ integrator の単一化が必要だ。Git worktree は公式にも、同一 repository に複数 working tree を持ち、複数 branch を同時に checkout できる仕組みとして説明されている。([Git][3]) 並列 agent には、共有 working tree ではなく worktree isolation が自然である。

Git hook は有用だが、最後の砦ではない。Git hooks は workflow の特定地点で実行される program であり、`core.hooksPath` でも場所を変更できる。([Git][4]) ただし client-side hook は環境依存で、無効化・迂回の余地がある。したがって「worker 側 hook」だけでなく、「worker には commit 権限を渡さない」「commit は integrator process だけが行う」という構造にする必要がある。

OPA / Cedar のような policy-as-code は中間解として有力だ。OPA は policy decision-making を software から切り出す general-purpose policy engine として設計されている。([Open Policy Agent][5]) Cedar も authorization policy と decision のための言語である。([Cedar Policy Language Reference Guide][6]) ただし重要なのは、policy engine は decision point であって enforcement point ではないということだ。LLM が raw shell で policy engine を迂回できるなら意味がない。tool broker がすべての危険操作の入口になり、そこで OPA/Cedar を呼ぶ場合にだけ価値がある。

AWS IAM のように default deny と explicit deny の概念を採用するのは良い。AWS IAM でも request context に対して applicable policies を評価し、許可・拒否を決める構造がある。([AWS Documentation][7]) OrgOS も「原則すべて拒否、task capability で明示許可、危険操作は明示拒否優先」に寄せるべきだ。

## Q5. 30+ ルールの帰結

30+ ルールが単調増加し、consolidation 機構がないなら、それは rule debt である。健全ではない。問題は数そのものではなく、誰がどう評価し、どこで強制され、いつ削除されるかが定義されていないことだ。

ルール体系は 4 層に分けるべきだ。

第一層は constitutional invariants。5〜7 個でよい。例: worker は commit しない、session は shared worktree を使わない、state transition は broker 経由、Owner approval required な操作は自動実行しない、generated state は手編集しない。

第二層は machine-enforced policies。OPA/Cedar や Python policy で判定できるものだけを置く。各 policy には test が必要。

第三層は procedures。事故時の復旧手順、レビュー手順、handoff 書式など。これは OS の規則ではなく運用 playbook である。

第四層は documentation。背景、思想、例外の説明。LLM に読ませるのはよいが、これを enforcement と呼ばない。

「ルールが多い OS」と「ルールが少ない OS」のどちらが望ましいか。人間や LLM が逐次読む前提なら少ないほうがよい。機械が評価する前提なら多くてもよいが、形式化・テスト・優先順位・削除手順が必要だ。Linux kernel の coding style も、目的は readability と maintainability だと明示している。([Kernelドキュメント][8]) つまりルールは数ではなく、保守性のために存在する。OrgOS の現状は、保守性を上げるためのルールが、逆に保守対象を増やしている。

AWS IAM は複雑でも成立しているが、それは評価ロジックが機械化されているからだ。法律体系は巨大でも成立しているが、それは裁判所・手続き・解釈権限があるからだ。OrgOS にはそのどちらも薄い。だから自然言語ルールを増やすほど危険になる。

## Q6. Manager (LLM) の責務範囲

現状の Manager 責務は広すぎる。意図解釈、状態 bind、リスク分類、判断、実行、検証、ledger 更新、報告を 1 LLM turn で行うのは、便利だが脆い。LLM は「一貫した物語」を作るのが得意で、「全 precondition を漏れなく検査する」のは苦手である。

工学的には次で切るべきだ。

Planner: Owner intent を plan candidate に変換する。LLM が得意。

Scheduler / Lease Manager: task、branch、worktree、path lock、worker assignment を決める。これは deterministic program がやる。

Executor: worker に実装させる。AI でよいが capability は限定する。

Verifier: test、lint、diff budget、schema check、policy check を実行する。これは script と CI が主役。

Integrator: commit、merge、push を行う唯一の主体。LLM ではなく、承認された patch を取り込む gatekeeper。

Ledger Writer: event から DB を更新する。LLM が Markdown を直接編集してはいけない。

Reporter: Owner に要点を返す。LLM が得意。

「LLM が忘れる / 飛ばす」を防ぐには、LLM に思い出させるのではなく、忘れても進めない構造にする。具体的には、状態遷移を API 化し、precondition が満たされないと tool call が失敗するようにする。checklist は prompt ではなく program にする。Handoff Packet は自己申告ではなく、repo diff、test result、DB event から生成する。

Manager は kernel ではなく、planner 兼 narrator に降格させるべきだ。これは能力を疑う話ではない。役割を間違えると、優秀な LLM ほど説得力のある誤作動をするからである。

## Q7. Owner の認知負荷

Owner が `CONTROL.yaml` を直接編集し、`/org-tick` の意味を理解し、phase 遷移を把握する必要があるなら、それは UX として失敗している。Owner は OS の user であって、init system の operator ではない。

理想の抽象は「Intent を述べたら Plan Contract が返る」である。

Owner: 「ads orchestrator の衝突を避けつつ、billing 修正と並列で進めたい」

System: 「以下の plan を提案します。Task A は worktree A、branch `task/ads-orchestrator-fix`、allowed paths は X。Task B は worktree B、branch `task/billing-fix`、allowed paths は Y。共有 path なし。commit は integrator のみ。Owner approval が必要なのは schema migration のみ。承認しますか」

Owner が触るべきものは、approve / reject / modify priority / pause / resume / inspect diff だけでよい。YAML flag 編集は廃止する。Dashboard は編集対象ではなく表示対象。phase は内部状態であり、Owner には「waiting for approval」「running」「blocked by conflict」「ready for review」程度に圧縮して見せる。

認知負荷はかなり下げられる。ただしゼロにはできない。Owner が設計判断、リスク許容、仕様曖昧性、merge conflict の優先順位を決める必要は残る。下げるべき負荷は「OS 操作の知識」であり、残すべき負荷は「意思決定」である。

## Q8. もし白紙から作り直すなら

白紙から作るなら、OrgOS は次の 10 要素にする。

1. Intent Intake
   Owner の自然言語 intent を受ける。出力は plan candidate。ここは LLM でよい。

2. Plan Compiler
   intent を task graph に変換する。各 task に目的、成果物、allowed paths、risk、approval requirement、依存関係を持たせる。

3. State Store
   SQLite + append-only events。operational state は DB、監査は event log、Markdown/YAML は生成 view。

4. Scheduler / Lease Manager
   branch、worktree、path、worker slot を lease として管理する。heartbeat が切れたら reclaim する。

5. Worktree Factory
   task ごとに isolated worktree を作る。共有 worktree は使わない。branch 命名、base commit、cleanup を標準化する。

6. Tool Broker
   全 tool call の入口。filesystem write、git 操作、network、secret access を capability で制限する。OPA/Cedar または簡易 policy engine をここで呼ぶ。

7. Worker Agents
   実装だけを担当する。commit しない。ledger を更新しない。自分の allowed paths だけ触る。

8. Verifier
   test、lint、typecheck、diff inspection、schema validation、policy regression test を実行する。AI の報告ではなく実測を信じる。

9. Integrator
   唯一 commit できる主体。verified patch だけを main/develop に統合する。conflict resolution はここに集約する。

10. Owner Console
    Plan Contract、進捗、approval request、diff summary、rollback option だけを表示する。内部 YAML は見せない。

状態管理は、event log を真実、SQLite projection を現在状態、Markdown dashboard を表示にする。AI への制約は prompt ではなく capability で行う。worker は「できないこと」を policy で禁じるのではなく、実際にできない環境に置く。

想定 failure mode と対策はこうだ。

並列衝突: path lease と per-task worktree で事前に防ぐ。
意図しない branch checkout: worker に checkout 権限を渡さない。
自動 commit: worker に commit 権限を渡さない。
stale task: heartbeat expiry と lease reclaim。
LLM の状態誤認: DB から状態を読む。自然言語記憶を信用しない。
検証漏れ: verifier を script 化し、最低限の regression suite を持つ。
policy bypass: raw shell を制限し、危険操作は broker 経由にする。
Owner への過剰質問: approval threshold を定義し、それ以下は自動、以上は Plan Contract で聞く。

現 OrgOS との最大の違いは、Manager の賢さを中核にしないことだ。中核は小さな deterministic control plane。LLM はその上で plan と説明を担う。

## Q9. 短期 / 中期 / 長期アクション提案

| 優先 | アクション                                   | 目的                    | 難度  | 期待効果           | リスク             |
| -: | --------------------------------------- | --------------------- | --- | -------------- | --------------- |
|  1 | 新規 rule 追加を一時凍結する                       | patch-on-patch を止める   | S   | 思考の散逸を止める      | 一時的に不安になる       |
|  2 | 「worker は commit しない」を即時物理化する           | 最大事故面を閉じる             | S/M | 誤 commit が激減   | 既存 flow が詰まる    |
|  3 | 共有 worktree での並列実行を禁止する                 | branch 衝突を構造的に防ぐ      | S   | 事故 A/B の再発防止   | worktree 管理が増える |
|  4 | Integrator だけが commit する gate を作る       | 実装と統合を分離する            | M   | 監査性が上がる        | 初期運用は遅くなる       |
|  5 | task/path/branch/worker lease table を作る | 資源管理を first-class にする | M   | 並列安全性が上がる      | DB/CLI 実装が必要    |
|  6 | active state を SQLite に移す               | 複数 SSOT を解消する         | M/L | 整合性と query が改善 | migration 失敗    |
|  7 | YAML/MD を generated view に降格する          | 手編集による不整合を消す          | M   | 状態監査が容易        | 既存慣習の破壊         |
|  8 | 30+ rule を 4 層に再分類し、半分削る                | rule debt を減らす        | M   | Manager の負荷低下  | 消した rule への不安   |
|  9 | Owner UX を Plan Contract 方式にする          | Owner の操作負荷を下げる       | M   | 承認判断に集中できる     | UI/文面設計が必要      |
| 10 | 並列事故の regression test を作る               | 再発防止を検証可能にする          | M   | 修正の有効性が測れる     | test が形骸化する     |

この順番が重要である。DB 化より先に、自動 commit と共有 worktree を止めるべきだ。状態管理を改善しても、worker が commit できる限り事故は残る。

## Q10. 「やめるべきこと」リスト

まず、自然言語 rule を追加すれば安全になる、という発想をやめるべきだ。Markdown は設計意図の置き場であって、権限境界ではない。

次に、複数の SSOT をやめるべきだ。`.ai/TASKS.yaml`, `.ai/GOALS.yaml`, `.ai/CONTROL.yaml`, `.ai/DECISIONS.md`, `.ai/DASHBOARD.md` がそれぞれ真実を持つ構造は、規模が増えるほど破綻する。表示用ファイルと状態ファイルを混ぜてはいけない。

worker の自動 commit はやめるべきだ。これは最優先で止める。実装 worker と commit integrator を分けない限り、どれだけ rule を足しても同型事故は起きる。

同一 repo / 同一 worktree で複数 session を走らせるのもやめるべきだ。並列をやるなら worktree isolation が最低条件である。

Owner に `CONTROL.yaml` を編集させるのはやめるべきだ。それは UX ではなく内部配線の露出である。Owner は intent と approval を扱うべきで、flag 操作を覚えるべきではない。

Manager に ledger を直接書かせるのもやめるべきだ。ledger は event から生成する。LLM が「やった」と書いたことと、実際に repo / tests / DB が示すことを分けるべきである。

Iron Law を増やすのもやめるべきだ。Iron Law は増えた瞬間に iron ではなくなる。5 個前後の constitutional invariants に絞り、それ以外は machine policy か procedure に落とす。

「全 task を登録してから実行」という思想を、YAML 登録儀式として運用するのもやめるべきだ。必要なのは登録ではなく lease と capability の発行である。task が DB に存在し、資源が確保され、worker に能力が渡されて初めて実行可能、という形に変えるべきだ。

Handoff Packet を信頼源にするのもやめるべきだ。Handoff は説明であって証拠ではない。証拠は diff、test result、policy decision log、event log である。

最後に、OrgOS を巨大化すること自体を一度やめるべきだ。今の状態で機能を増やすと、制御対象も制御規則も増え、Owner の認知負荷も増える。まず最小 kernel を作り、その kernel で守れない機能は追加しない、という姿勢に戻すべきだ。

## Summary

OrgOS の問題は、個別 rule の不足ではなく、自然言語 policy を実行境界と誤認していることにある。理想形は、賢い Manager を中心にした markdown OS ではなく、小さな deterministic control plane と、capability で縛られた worker 群である。YAML/Markdown は state ではなく view に降格し、commit・branch・worktree・path lease は機械的に管理するべきだ。次の一手は **全 worker の自動 commit を止め、per-task worktree + single integrator commit gate を先に作ること**。

[1]: https://sqlite.org/wal.html?utm_source=chatgpt.com "Write-Ahead Logging"
[2]: https://martinfowler.com/eaaDev/EventSourcing.html?utm_source=chatgpt.com "Event Sourcing"
[3]: https://git-scm.com/docs/git-worktree?utm_source=chatgpt.com "Git - git-worktree Documentation"
[4]: https://git-scm.com/docs/githooks?utm_source=chatgpt.com "githooks Documentation"
[5]: https://openpolicyagent.org/docs?utm_source=chatgpt.com "Open Policy Agent (OPA)"
[6]: https://docs.cedarpolicy.com/?utm_source=chatgpt.com "What is Cedar? | Cedar Policy Language Reference Guide"
[7]: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html?utm_source=chatgpt.com "Policy evaluation logic - AWS Identity and Access ..."
[8]: https://docs.kernel.org/process/coding-style.html?utm_source=chatgpt.com "Linux kernel coding style"
