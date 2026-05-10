# Threat Model

## Metadata

| Field | Value |
|---|---|
| Project / Milestone | `TODO` |
| Related Journey | `TODO: JOURNEY-ID / flow name` |
| Related Quality Contract | `TODO: QC-ID` |
| Author | `TODO` |
| Reviewers | `TODO` |
| Status | `draft / confirmed / superseded` |
| Last Updated | `YYYY-MM-DD` |

## Scope

- In scope:
  - `TODO: flow / feature / subsystem`
- Out of scope:
  - `TODO: explicitly excluded area`
- Trust boundaries:
  - `TODO: browser -> API -> DB -> external service`
- Sensitive assets:
  - `TODO: PII / secret / credential / internal business data`

## Threat Coverage Matrix

| # | Category | Applies? | Covered By Section | Open Risk |
|---|---|---|---|---|
| 1 | Race condition (同時更新) | `yes/no` | [1](#1-race-condition-同時更新) | `TODO` |
| 2 | 重複 (idempotency 不在) | `yes/no` | [2](#2-重複-idempotency-不在) | `TODO` |
| 3 | 権限漏れ (RLS / authz) | `yes/no` | [3](#3-権限漏れ-rls--authz) | `TODO` |
| 4 | 認証回避 (authn) | `yes/no` | [4](#4-認証回避-authn) | `TODO` |
| 5 | データ漏洩 (PII / secret) | `yes/no` | [5](#5-データ漏洩-pii--secret) | `TODO` |
| 6 | 暴走 (無限ループ / リソース枯渇) | `yes/no` | [6](#6-暴走-無限ループ--リソース枯渇) | `TODO` |
| 7 | 入力検証欠落 (injection / XSS) | `yes/no` | [7](#7-入力検証欠落-injection--xss) | `TODO` |
| 8 | エラー隠蔽 (silent failure) | `yes/no` | [8](#8-エラー隠蔽-silent-failure) | `TODO` |

## 1. Race condition (同時更新)

| Required Field | Answer |
|---|---|
| 該当箇所 | `TODO: flow / table / endpoint / job / UI action` |
| 攻撃シナリオ / 失敗シナリオ | `TODO: 同時 submit、並列 job、二重更新などの具体例` |
| 対策 | `TODO: transaction、row lock、unique constraint、optimistic lock、state transition guard` |
| 検証方法 | `TODO: concurrent request test、transaction rollback test、constraint test` |
| 残リスク | `TODO: none / accepted risk / follow-up task` |

## 2. 重複 (idempotency 不在)

| Required Field | Answer |
|---|---|
| 該当箇所 | `TODO: create endpoint / webhook / retryable job / payment-like operation` |
| 攻撃シナリオ / 失敗シナリオ | `TODO: double click、network retry、webhook retry、worker retry による重複 insert` |
| 対策 | `TODO: idempotency key、unique index、upsert rule、dedupe table、retry-safe response` |
| 検証方法 | `TODO: same key replay test、duplicate payload test、retry test` |
| 残リスク | `TODO` |

## 3. 権限漏れ (RLS / authz)

| Required Field | Answer |
|---|---|
| 該当箇所 | `TODO: table / RLS policy / endpoint / RPC / admin operation` |
| 攻撃シナリオ / 失敗シナリオ | `TODO: 他 user / 他 tenant の data を read/write できる具体例` |
| 対策 | `TODO: RLS、owner check、tenant scope、service role restriction、policy test` |
| 検証方法 | `TODO: cross-user access test、anonymous denied test、admin-only test` |
| 残リスク | `TODO` |

## 4. 認証回避 (authn)

| Required Field | Answer |
|---|---|
| 該当箇所 | `TODO: route / middleware / callback / webhook / background function` |
| 攻撃シナリオ / 失敗シナリオ | `TODO: token なし、期限切れ token、署名なし webhook、middleware bypass` |
| 対策 | `TODO: auth guard、token validation、signature verification、session expiry handling` |
| 検証方法 | `TODO: unauthenticated request test、expired token test、invalid signature test` |
| 残リスク | `TODO` |

## 5. データ漏洩 (PII / secret)

| Required Field | Answer |
|---|---|
| 該当箇所 | `TODO: response / log / error / export / cache / client state / analytics` |
| 攻撃シナリオ / 失敗シナリオ | `TODO: PII が response や log に出る、secret が client bundle に入る` |
| 対策 | `TODO: field allowlist、redaction、server-only secret、log masking、cache scope` |
| 検証方法 | `TODO: response snapshot、log inspection、bundle/env check、export permission test` |
| 残リスク | `TODO` |

## 6. 暴走 (無限ループ / リソース枯渇)

| Required Field | Answer |
|---|---|
| 該当箇所 | `TODO: loop / recursive job / polling / batch / query / external API call` |
| 攻撃シナリオ / 失敗シナリオ | `TODO: unbounded input、N+1、retry storm、queue backlog、rate limit exhaustion` |
| 対策 | `TODO: limit、timeout、pagination、rate limit、backoff、circuit breaker、batch size` |
| 検証方法 | `TODO: large input test、timeout test、rate limit test、load smoke test` |
| 残リスク | `TODO` |

## 7. 入力検証欠落 (injection / XSS)

| Required Field | Answer |
|---|---|
| 該当箇所 | `TODO: form / API input / URL param / markdown/html / file path / query builder` |
| 攻撃シナリオ / 失敗シナリオ | `TODO: SQL injection、XSS、command injection、path traversal、schema mismatch` |
| 対策 | `TODO: schema validation、escaping、parameterized query、sanitization、content policy` |
| 検証方法 | `TODO: invalid input test、payload fuzz smoke、XSS render test、schema test` |
| 残リスク | `TODO` |

## 8. エラー隠蔽 (silent failure)

| Required Field | Answer |
|---|---|
| 該当箇所 | `TODO: catch block / async job / external API call / transaction / UI action` |
| 攻撃シナリオ / 失敗シナリオ | `TODO: 失敗したのに success 表示、partial write、retry exhaustion が見えない` |
| 対策 | `TODO: typed error、rollback、user-visible message、structured log、alert、dead-letter` |
| 検証方法 | `TODO: forced failure test、rollback test、log assertion、UI error state test` |
| 残リスク | `TODO` |

## Project-Specific Threats

| Threat | 該当箇所 | Scenario | Mitigation | Verification | Owner / Task |
|---|---|---|---|---|---|
| `TODO` | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |

## Sign-off

- All 8 categories evaluated: `yes/no`
- DATA_MODEL_FULL transaction boundaries referenced: `yes/no`
- DATA_MODEL_FULL idempotency keys referenced: `yes/no`
- AUTHORITY_BOUNDARY permissions referenced: `yes/no`
- Open risks accepted by: `TODO: Owner / Manager / N/A`
- Confirmed at: `YYYY-MM-DD`
