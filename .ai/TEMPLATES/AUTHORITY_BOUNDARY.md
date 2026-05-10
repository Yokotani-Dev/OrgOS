# Authority Boundary

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

- Protected resources:
  - `TODO: tables / endpoints / functions / storage buckets`
- Public resources:
  - `TODO`
- External actors:
  - `TODO: webhook provider / integration / cron / service role`
- Out of scope:
  - `TODO`

## Roles

| Role | Description | Auth Source | Allowed Scope | Notes |
|---|---|---|---|---|
| `system_admin` | `TODO: internal operator / owner admin` | `TODO` | `TODO: all tenants / admin console only` | `TODO` |
| `authenticated_user` | `TODO: signed-in end user` | `TODO: session token` | `TODO: own resources only` | `TODO` |
| `anonymous` | `TODO: unauthenticated visitor` | `none` | `TODO: public read only / none` | `TODO` |
| `service_role` | `TODO: backend job or trusted function` | `TODO: server-only secret` | `TODO: explicit functions only` | `Never expose to client` |

## Resource Permission Matrix

Use `allow`, `deny`, or `conditional:<condition>`.

| Resource | Action | anonymous | authenticated_user | system_admin | service_role | Enforcement |
|---|---|---|---|---|---|---|
| `TODO: table/resource` | `create` | `deny` | `conditional: own user_id` | `allow` | `conditional: server-only` | `TODO: RLS / API guard / RPC` |
| `TODO: table/resource` | `read` | `deny` | `conditional: own user_id` | `allow` | `conditional: server-only` | `TODO` |
| `TODO: table/resource` | `update` | `deny` | `conditional: own user_id and state` | `allow` | `conditional: server-only` | `TODO` |
| `TODO: table/resource` | `delete` | `deny` | `conditional: own user_id and policy` | `allow` | `conditional: server-only` | `TODO` |

## RLS Policies

Postgres / Supabase policy list. If RLS is not used, document the alternative enforcement and reason.

| Table | Policy Name | Command | Role | USING | WITH CHECK | Purpose | Test |
|---|---|---|---|---|---|---|---|
| `TODO: table_name` | `TODO: policy_name` | `select/insert/update/delete/all` | `TODO` | `TODO: auth.uid() = user_id` | `TODO` | `TODO` | `TODO: cross-user denied` |

## RPC / Function Permissions

| Function / RPC | Caller Roles | Security Mode | Inputs Validated | Uses Service Role? | Side Effects | Audit Log | Test |
|---|---|---|---|---|---|---|---|
| `TODO: function_name` | `TODO: authenticated_user/system_admin/service_role` | `invoker/definer/API guard` | `yes/no` | `yes/no` | `TODO: tables changed / external call` | `yes/no` | `TODO` |

## Authentication Boundaries

| Boundary | Public Side | Authenticated Side | Enforcement Point | Failure Response | Test |
|---|---|---|---|---|---|
| `TODO: route group / API prefix / function` | `TODO` | `TODO` | `TODO: middleware / server action / RPC guard` | `TODO: 401 / redirect / deny` | `TODO: anonymous denied` |

## Session Management

| Topic | Decision | Implementation Point | Test / Verification |
|---|---|---|---|
| Token lifetime | `TODO` | `TODO` | `TODO` |
| Refresh strategy | `TODO` | `TODO` | `TODO` |
| Revocation strategy | `TODO` | `TODO` | `TODO` |
| Logout behavior | `TODO` | `TODO` | `TODO` |
| Session fixation / rotation | `TODO` | `TODO` | `TODO` |
| Cross-device behavior | `TODO` | `TODO` | `TODO` |

## Secrets And Service Credentials

| Secret / Credential | Used By | Storage | Client Exposure Allowed? | Rotation | Audit |
|---|---|---|---|---|---|
| `TODO` | `TODO` | `TODO: env / secret manager` | `no` | `TODO` | `TODO` |

## Audit Log Requirements

| Event | Actor | Resource | Required Fields | Retention | Alert? |
|---|---|---|---|---|---|
| `TODO: permission change / admin action / destructive action` | `TODO` | `TODO` | `TODO: actor_id, resource_id, before, after, request_id` | `TODO` | `yes/no` |

## Boundary Tests

| Test ID | Scenario | Expected Result | Covers |
|---|---|---|---|
| `AUTH-001` | `anonymous reads protected resource` | `401/403` | `authn boundary` |
| `AUTH-002` | `user A reads user B resource` | `403 / empty result` | `RLS / authz` |
| `AUTH-003` | `authenticated user calls admin RPC` | `403` | `RPC permission` |

## Open Questions

| Question | Owner | Blocker? | Decision Needed By |
|---|---|---|---|
| `TODO` | `TODO` | `yes/no` | `YYYY-MM-DD` |

## Sign-off

- Roles complete: `yes/no`
- CRUD permission matrix complete: `yes/no`
- RLS / alternative enforcement complete: `yes/no`
- RPC / Function permissions complete: `yes/no`
- Authentication boundaries complete: `yes/no`
- Session management complete: `yes/no`
- Audit log requirements complete: `yes/no`
- Confirmed at: `YYYY-MM-DD`
