# OrgOS とは何か — Claude Code 単体との違い

> 作成: 2026-04-28 / Manager (Claude Opus 4.7)
> 想定読者: OrgOS を初めて知る人、Claude Code は使ったことがある人
> 関連: [ORGOS_TOBE.md](ORGOS_TOBE.md) (アーキテクチャ転換の本体設計)

---

## 1. 一言で言うと

**OrgOS は「Claude Code を Chief of Staff (参謀長) として動かすための OS レイヤー」**です。

```mermaid
flowchart LR
    A[Owner] -->|依頼| B[Claude Code<br/>= エンジン]
    B -.->|単体だと忘れる<br/>全体像を見ない<br/>毎回手段を再探索| C[作業者止まり]

    A2[Owner] -->|依頼| D[OrgOS<br/>= 参謀長 OS]
    D --> E[Claude Code<br/>= エンジン]
    D -.->|記憶 / 全体像 / 手段台帳<br/>判断記録 / 自律提案| F[Chief of Staff]

    style B fill:#fff3cd
    style D fill:#d4edda
    style C fill:#f8d7da
    style F fill:#cce5ff
```

Claude Code はそのままでは「賢い外注作業者」止まりです。OrgOS はその上に **記憶・全体像把握・手段台帳・構造化対話・追跡可能性** を載せて、Owner (あなた) の参謀長として継続稼働させます。

---

## 2. 全体アーキテクチャ — 1 枚絵

```mermaid
flowchart TB
    Owner([Owner])

    subgraph OrgOS["OrgOS Layer (.ai/ + .claude/)"]
        direction TB

        subgraph Intake["Request Intake Loop (10 ステップ)"]
            S1[Intake<br/>依頼原文固定]
            S2[Memory<br/>USER_PROFILE 参照]
            S3[Bind<br/>GOALS / TASKS]
            S4[Capability<br/>CAPABILITIES 探索]
            S5[Risk 分類]
            S6[Decide<br/>act/ask/defer/refuse]
            S7[Execute + Trace]
            S8[Verify]
            S9[Update 台帳]
            S10[Report<br/>Coherence Mode]
        end

        subgraph Ledgers["Ledgers (永続記憶)"]
            UP[USER_PROFILE.yaml<br/>Memory]
            CAP[CAPABILITIES.yaml<br/>Optionality]
            GO[GOALS.yaml<br/>Awareness]
            TA[TASKS.yaml<br/>Work Graph]
            DE[DECISIONS.md<br/>Accountability]
        end

        subgraph Agents["Agents (役割分離)"]
            MGR[Manager<br/>判断]
            IMP[Codex Implementer<br/>実装]
            REV[Reviewer / Security<br/>検証]
        end
    end

    CC[Claude Code<br/>Engine]

    Owner -->|依頼| Intake
    Intake <--> Ledgers
    Intake --> Agents
    Agents -->|tool 呼出| CC
    Agents -->|更新| Ledgers
    Intake -->|応答| Owner

    style Owner fill:#e7f3ff
    style OrgOS fill:#f0f7ff
    style Ledgers fill:#fff9e6
    style Agents fill:#e8f5e9
    style CC fill:#fff3cd
```

---

## 3. なぜ Claude Code 単体では足りないのか

```mermaid
flowchart TD
    Q[Owner: 同じ依頼を別セッションで] --> CC1[Claude Code 単体]
    Q --> OS1[OrgOS]

    CC1 --> CC2[セッション内記憶のみ]
    CC2 --> CC3[認証情報を再質問]
    CC2 --> CC4[CLI を再探索]
    CC2 --> CC5[全体像を再構築]
    CC3 & CC4 & CC5 --> CC6[Owner 負担増]

    OS1 --> OS2[USER_PROFILE 参照]
    OS1 --> OS3[CAPABILITIES 参照]
    OS1 --> OS4[GOALS / TASKS 参照]
    OS2 & OS3 & OS4 --> OS5[既存資産で即実行]

    style CC6 fill:#f8d7da
    style OS5 fill:#d4edda
```

| 症状 (Claude Code 単体) | 原因 | OrgOS の解決 |
|------------------------|------|--------------|
| 同じ質問を毎セッション繰り返される | セッションを越えた構造化記憶がない | `USER_PROFILE.yaml` で fact / preference / secret pointer を永続化 |
| CLI で取れる情報も「GUI で取って」と言われる | 使える手段が台帳化されていない | `CAPABILITIES.yaml` で 58+ ツールの利用可否を台帳化 |
| 単発依頼で進行中プロジェクト文脈が無視される | 全体像と個別依頼を結ぶ仕組みがない | `bind-request.sh` が依頼を進行中タスクへ自動バインド |
| 「次どうする？」と毎回聞かれる | 自律提案の基盤がない | `suggest-next.sh` が Owner preference を考慮した P0/P1/P2 候補を提示 |
| 何を誰がいつ決めたか追えなくなる | 決定の永続記録がない | `DECISIONS.md` に PLAN-UPDATE / ISSUE 番号で永続記録 |

---

## 4. 比較表 — Claude Code 単体 vs OrgOS

| 観点 | Claude Code 単体 | OrgOS |
|------|------------------|-------|
| **記憶** | セッション内のみ | `USER_PROFILE.yaml` で永続化 |
| **手段の把握** | 毎回 `which xxx` で探索 | `CAPABILITIES.yaml` で台帳化 |
| **プロジェクト全体像** | 都度 `Read` で再構築 | Vision → Milestone → Project → Task の 4 階層 Work Graph |
| **依頼の文脈付け** | なし | 進行中タスクへ自動バインド |
| **判断記録** | チャット履歴のみ | `DECISIONS.md` に永続記録 |
| **実装と判断の分離** | 1 エージェントが全部 | Manager + Codex Implementer + Reviewer |
| **次手の提案** | Owner 指示まで停止 | Owner preference を考慮した能動提示 |
| **権限境界** | プロンプト次第 | Autonomy Level (silent/report/ask/owner_only) を機械判定 |
| **委譲プロトコル** | 自由形式 | Handoff Packet スキーマ強制 |
| **品質の自己評価** | なし | Manager Quality Eval (6 指標 × 20 ケース) |
| **セッション横断の継続** | チャット閉じたらリセット | 7 台帳が SessionStart hook で自動再ロード |

---

## 5. OrgOS の核 — Chief of Staff モデル (MAOPA)

```mermaid
mindmap
  root((MAOPA<br/>Chief of Staff))
    Memory<br/>忘れない
      USER_PROFILE.yaml
      memory-lifecycle.md
      capture / normalize / scope
      retrieve / validate / retire
    Awareness<br/>全体を見る
      GOALS.yaml
      coherence-mode.md
      Silent / Brief / Full Bind
    Optionality<br/>手段を持つ
      CAPABILITIES.yaml
      capability-preflight.md
      CLI / API / MCP / Script
    Partnership<br/>巻き込む
      構造化質問 1-3 問
      推奨付き選択肢
      owner-task-minimization.md
    Accountability<br/>責任を負う
      DECISIONS.md
      Handoff Packet
      Audit log
```

### 各柱の対応表

| 柱 | 意味 | 主要ファイル |
|----|------|--------------|
| **M**emory | Owner の資産・会話・好みを永続保持 | `USER_PROFILE.yaml`, `memory-lifecycle.md` |
| **A**wareness | 単発依頼でも全体像にバインド | `GOALS.yaml`, `coherence-mode.md` |
| **O**ptionality | Owner に依頼する前に手段を総当たり | `CAPABILITIES.yaml`, `capability-preflight.md` |
| **P**artnership | Owner を戦略パートナーとして扱う | `owner-task-minimization.md` |
| **A**ccountability | 全判断・実行に追跡可能な記録 | `DECISIONS.md`, `handoff-protocol.md` |

---

## 6. 依頼処理の流れ — Request Intake Loop

OrgOS Manager は **すべての依頼** を以下 10 ステップで処理します (Iron Law)。

```mermaid
flowchart TD
    Start([Owner からの依頼]) --> S1[1. Intake<br/>原文を固定]
    S1 --> S2[2. Load Memory<br/>USER_PROFILE 参照]
    S2 --> S3[3. Bind Work Graph<br/>GOALS / TASKS / CONTROL]
    S3 --> S4[4. Discover Capabilities<br/>CAPABILITIES 探索]
    S4 --> S5[5. Classify Risk<br/>reversibility / cost / security]
    S5 --> S6{6. Decide}

    S6 -->|低リスク+可逆| Act1[act silent]
    S6 -->|中リスク| Act2[act + report]
    S6 -->|不可逆 or 高| Ask[ask Owner]
    S6 -->|外部承認待ち| Defer[defer]
    S6 -->|破壊的| Refuse[refuse]

    Act1 & Act2 --> S7[7. Execute<br/>+ trace_id 発行]
    Ask --> S7
    S7 --> S8[8. Verify<br/>期待値照合 / 副作用確認]
    S8 --> S9[9. Update<br/>TASKS / DECISIONS / MEMORY]
    S9 --> S10[10. Report<br/>Coherence Mode]
    S10 --> End([Owner への応答])

    style S6 fill:#fff3cd
    style Refuse fill:#f8d7da
    style End fill:#d4edda
```

スキップは各 Step の明示条件がある場合のみ許可されます (Iron Law)。

---

## 7. Before / After シーケンス — 認証情報の再利用

```mermaid
sequenceDiagram
    participant O as Owner
    participant CC as Claude Code 単体
    participant M as OrgOS Manager
    participant UP as USER_PROFILE.yaml
    participant CAP as CAPABILITIES.yaml
    participant SB as supabase CLI

    Note over O,CC: ❌ Claude Code 単体
    O->>CC: DB 接続設定して
    CC->>O: URL と認証情報を教えて
    O-->>CC: (内心: 前にも教えたのに...)

    Note over O,SB: ✅ OrgOS
    O->>M: DB 接続設定して
    M->>UP: 関連 fact 検索
    UP-->>M: Supabase project_abc123<br/>(2026-03-15 共有)
    M->>CAP: 利用可能ツール検索
    CAP-->>M: supabase CLI: verified
    M->>SB: supabase link + テスト接続
    SB-->>M: OK
    M->>O: project_abc123 で設定完了。<br/>別 DB の場合のみ教えてください。
```

---

## 8. Before / After — 単発依頼の文脈バインド

### Claude Code 単体

```mermaid
flowchart LR
    A[依頼: ログから error 抽出] --> B[grep 実行]
    B --> C[結果表示]
    C --> D[終了]
    style D fill:#f8d7da
```

### OrgOS

```mermaid
flowchart LR
    A[依頼: ログから error 抽出] --> B[bind-request.sh]
    B --> C{進行中タスクと一致?}
    C -->|YES: T-OS-121| D[文脈バインド明示]
    D --> E[grep 実行]
    E --> F[結果を T-OS-121 の<br/>acceptance 観点で分析]
    F --> G[3 件中 1 件は別タスク化推奨]
    G --> H[Owner に提案付き報告]
    style H fill:#d4edda
```

---

## 9. ファイル構成 — どこに何があるか

```mermaid
flowchart TB
    subgraph ai[".ai/ — Owner と Manager の対話面"]
        UP[USER_PROFILE.yaml<br/>Owner プロファイル]
        CAP[CAPABILITIES.yaml<br/>利用可能ツール]
        GO[GOALS.yaml<br/>Vision/Milestone/Project]
        TA[TASKS.yaml<br/>Task DAG]
        CO[CONTROL.yaml<br/>ゲート制御]
        DE[DECISIONS.md<br/>判断ログ]
        DA[DASHBOARD.md<br/>1 枚絵]
        OI[OWNER_INBOX.md<br/>Manager から Owner]
        OC[OWNER_COMMENTS.md<br/>Owner から Manager]
    end

    subgraph claude[".claude/ — Manager の振る舞い"]
        R[rules/<br/>Iron Law]
        AG[agents/<br/>サブエージェント]
        CMD[commands/<br/>スラッシュコマンド]
        SK[skills/<br/>技術スキル]
        EV[evals/<br/>品質評価]
    end

    subgraph scripts["scripts/ — OS の実装層"]
        SE[session/bootstrap.sh<br/>台帳ロード]
        CS[capabilities/scan.sh<br/>ツール検出]
        GS[goals/<br/>active_graph 更新]
        AU[authority/<br/>権限判定]
        ME[memory/<br/>Memory lint]
    end

    style ai fill:#fff9e6
    style claude fill:#e8f5e9
    style scripts fill:#e7f3ff
```

---

## 10. 使うべき場面 / 使わないべき場面

```mermaid
flowchart LR
    subgraph use["✅ OrgOS を使うべき"]
        U1[継続的な開発<br/>数日〜数ヶ月]
        U2[複数の専門タスクを<br/>分業させたい]
        U3[判断の根拠と履歴を<br/>残したい]
        U4[Owner の認知負荷を<br/>AI に最適化させたい]
    end

    subgraph skip["❌ 使わなくていい"]
        S1[1 回限りの<br/>簡単な質問]
        S2[探索的な対話だけ<br/>アイデアブレスト]
        S3[Claude Code を<br/>そのまま信頼している]
    end

    style use fill:#d4edda
    style skip fill:#fff3cd
```

OrgOS は「セットアップとルール遵守のオーバーヘッド」を払う代わりに、「**Owner が Owner にしかできないことに集中できる時間**」を返す投資です。

---

## 11. 始め方

```mermaid
flowchart LR
    A[既存リポジトリに導入] --> A1[claude]
    A1 --> A2[/org-import latest]
    A2 --> A3[/org-start]

    B[新規プロジェクト] --> B1[git clone OrgOS]
    B1 --> B2[remote 切り替え]
    B2 --> B3[claude]
    B3 --> B4[/org-start]

    A3 --> Z[初期化完了]
    B4 --> Z

    style Z fill:#d4edda
```

### 既存リポジトリに導入

```bash
cd <your-project>
claude
/org-import latest
/org-start
```

### 新規プロジェクトとして開始

```bash
git clone https://github.com/Yokotani-Dev/OrgOS.git my-project
cd my-project
git remote remove origin
git remote add origin <your-repo-url>
claude
/org-start
```

詳細は [README.md](../../README.md) を参照。

---

## 12. もっと深く知るには

```mermaid
flowchart TB
    START([さらに深く]) --> Q1{何を知りたい?}

    Q1 -->|設計思想| D1[ORGOS_TOBE.md]
    Q1 -->|評価指標| D2[ORGOS_EVALS.md]
    Q1 -->|自律改善ループ| D3[ORG_EVOLVE.md]
    Q1 -->|全依頼に適用される<br/>Iron Law| D4[request-intake-loop.md]
    Q1 -->|権限境界| D5[authority-layer.md]
    Q1 -->|記憶の操作| D6[memory-lifecycle.md]
    Q1 -->|サブエージェント間<br/>引き渡し| D7[handoff-protocol.md]
```

| 知りたいこと | 参照 |
|--------------|------|
| 設計思想の本体 | [ORGOS_TOBE.md](ORGOS_TOBE.md) |
| 評価指標と回帰検出 | [ORGOS_EVALS.md](ORGOS_EVALS.md) |
| 自律改善ループ | [ORG_EVOLVE.md](ORG_EVOLVE.md) |
| 全依頼に適用される Iron Law | [request-intake-loop.md](../../.claude/rules/request-intake-loop.md) |
| 権限境界モデル | [authority-layer.md](../../.claude/rules/authority-layer.md) |
| 記憶の操作プロトコル | [memory-lifecycle.md](../../.claude/rules/memory-lifecycle.md) |
| サブエージェント間の引き渡し | [handoff-protocol.md](../../.claude/rules/handoff-protocol.md) |

---

## まとめ

```mermaid
flowchart LR
    CC["Claude Code<br/>(エンジン)"]
    OS["OrgOS<br/>(車体・ナビ・サスペンション)"]
    DEST["継続稼働する<br/>Chief of Staff"]

    CC --> OS
    OS --> DEST

    style CC fill:#fff3cd
    style OS fill:#cce5ff
    style DEST fill:#d4edda
```

- **Claude Code** = 強力な汎用 AI コーディングエージェント (作業者)
- **OrgOS** = それを Chief of Staff として継続稼働させるための OS レイヤー (参謀長)

両者は競合しません。**OrgOS は Claude Code の上に乗る**ものです。Claude Code がエンジンなら、OrgOS は車体・サスペンション・ナビゲーションシステムにあたります。
