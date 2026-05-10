# Acceptance Checklist

> Manager が新 task 作成時に使う pre-write checklist。
> 空欄は禁止。該当しない場合は `N/A` と理由を明示する。

## Task Metadata

- Task ID:
- Task Title:
- Milestone:
- Owner Role:
- Codex Role: implementer | reviewer
- Work Order Path:
- Final Acceptance Destination: `.ai/TASKS.yaml` `acceptance` array

## Quality Contract Reference

- QC ID:
- quality_level:
- sync_status: confirmed | draft | superseded
- definition_of_done source:
- out_of_scope:
- N/A reason if no Quality Contract applies:

## DoD Axis: Functionality

- Applicability: applicable | N/A
- Source fields:
- Required behavior:
- Explicit non-goals:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

## DoD Axis: Error Handling

- Applicability: applicable | N/A
- Source fields:
- Error classes to handle:
- Recovery behavior:
- User-visible / operator-visible result:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

## DoD Axis: Security

- Applicability: applicable | N/A
- Source fields:
- Security boundary:
- Authn / authz / RLS expectations:
- Sensitive data handling:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

## DoD Axis: Performance

- Applicability: applicable | N/A
- Source fields:
- Smoke check / threshold:
- Resource bounds:
- Known non-goals:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

## DoD Axis: Observability

- Applicability: applicable | N/A
- Source fields:
- Structured log fields:
- Metrics / eval inputs:
- Failure visibility:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

## DoD Axis: Documentation

- Applicability: applicable | N/A
- Source fields:
- Required docs / reports:
- Consumer of the doc:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

## Threat Categories

### 1. Race Condition

- Applicability: applicable | N/A
- Related flow / table / endpoint / job / UI action:
- Threat or failure scenario:
- Mitigation expectation:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

### 2. Duplicate / Missing Idempotency

- Applicability: applicable | N/A
- Related flow / table / endpoint / job / UI action:
- Threat or failure scenario:
- Idempotency key / dedupe expectation:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

### 3. Authorization Leak / RLS / Authz

- Applicability: applicable | N/A
- Related resource / role / tenant / owner scope:
- Threat or failure scenario:
- Mitigation expectation:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

### 4. Authentication Bypass / Authn

- Applicability: applicable | N/A
- Related boundary / callback / middleware:
- Threat or failure scenario:
- Mitigation expectation:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

### 5. Data Leakage / PII / Secret

- Applicability: applicable | N/A
- Related data / log / cache / export:
- Threat or failure scenario:
- Mitigation expectation:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

### 6. Resource Exhaustion / Runaway

- Applicability: applicable | N/A
- Related loop / job / payload / query:
- Threat or failure scenario:
- Bound / backpressure / rate-limit expectation:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

### 7. Input Validation / Injection / XSS

- Applicability: applicable | N/A
- Related input / parser / renderer / path:
- Threat or failure scenario:
- Validation / sanitization expectation:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

### 8. Silent Failure / Error Hiding

- Applicability: applicable | N/A
- Related catch / retry / partial success / monitor:
- Threat or failure scenario:
- Failure surfacing expectation:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

## Data Model Source

### Invariants

- Applicability: applicable | N/A
- Source artifact / section:
- Invariants:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

### Transactions

- Applicability: applicable | N/A
- Source artifact / section:
- Transaction boundary:
- Atomicity / rollback expectation:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

### Idempotency

- Applicability: applicable | N/A
- Source artifact / section:
- Idempotency key / dedupe strategy:
- Retry behavior:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

## Authority Source

### RLS

- Applicability: applicable | N/A
- Source artifact / section:
- Tables / policies:
- Expected allow / deny cases:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

### Authz

- Applicability: applicable | N/A
- Source artifact / section:
- Roles / permissions:
- Owner / tenant / admin boundary:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

## Domain Constraint Source

### Prohibited Practices

- Applicability: applicable | N/A
- Domain Constraint ID:
- Prohibited practices:
- Enforcement expectation:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

### Required Practices

- Applicability: applicable | N/A
- Domain Constraint ID:
- Required practices:
- Implementation / operation expectation:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

## Journey Source

### Happy Path

- Applicability: applicable | N/A
- Journey ID:
- Target flow / happy_path steps:
- Expected success state:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

### Error Paths

- Applicability: applicable | N/A
- Journey ID:
- Error paths:
- Expected handling:
- Verification method:
- Acceptance candidates:
  - 
- N/A reason:

## Final Acceptance Array

Deduplicate the candidates above. Each item must be verifiable, single-purpose, and traceable to at least one source.

```yaml
acceptance:
  - "[source: quality_contract.functionality] ..."
  - "[source: quality_contract.error_handling] ..."
  - "[source: quality_contract.security] ..."
  - "[source: quality_contract.performance] ..."
  - "[source: quality_contract.observability] ..."
  - "[source: quality_contract.documentation] ..."
  - "[source: threat_model.category_N] ..."
  - "[source: data_model.invariants] ..."
  - "[source: data_model.transactions] ..."
  - "[source: data_model.idempotency] ..."
  - "[source: authority_boundary.rls] ..."
  - "[source: authority_boundary.authz] ..."
  - "[source: domain_constraint.prohibited] ..."
  - "[source: domain_constraint.required] ..."
  - "[source: journey.happy_path] ..."
  - "[source: journey.error_paths] ..."
```

## Manager Pre-Delegation Check

- [ ] Every section above is filled with `applicable` details or `N/A` plus reason.
- [ ] Quality Contract DoD 6 axes are covered or explicitly marked N/A.
- [ ] Threat Categories 1-8 are covered or explicitly marked N/A.
- [ ] Data Model invariants / transactions / idempotency are covered or explicitly marked N/A.
- [ ] Authority RLS / authz are covered or explicitly marked N/A.
- [ ] Domain prohibited / required practices are covered or explicitly marked N/A.
- [ ] Journey happy_path / error_paths are covered or explicitly marked N/A.
- [ ] Final acceptance array has no duplicate items.
- [ ] Final acceptance array has no vague terms such as "適切に", "十分に", "必要に応じて", "考慮する".
- [ ] Codex Work Order includes the final acceptance array verbatim.
