# Blueprint 03: Multi-Tenant Data Isolation & Row-Level Security (RLS)

> **Status: PROPOSED — SECURITY REVIEW REQUIRED**
>
> This blueprint is a reference pattern, not a security certification. RLS is one layer of defense. Production safety depends on database roles, transaction handling, application authentication, every tenant-scoped table, and adversarial testing.

## 1. Problem and scope

In a shared-schema SaaS database, a missing tenant filter can expose another customer's records. PostgreSQL Row-Level Security (RLS) can enforce row filtering in the database for roles subject to RLS.

This pattern assumes:
- Each tenant-owned row has a non-null `tenant_id UUID`.
- The application authenticates the user and derives the tenant ID from a verified server-side identity, never from an untrusted request parameter.
- Each request that accesses tenant data runs inside a database transaction.
- The application connects using a dedicated, non-owner, non-superuser role without `BYPASSRLS`.
- The application role cannot execute arbitrary SQL or change its database role.

## 2. Critical PostgreSQL security facts

1. Superusers and roles with `BYPASSRLS` always bypass RLS.
2. Table owners normally bypass RLS; `FORCE ROW LEVEL SECURITY` subjects the table owner to policies, but does not constrain superusers or `BYPASSRLS` roles.
3. RLS does not replace SQL privileges. A role needs ordinary table privileges as well as a matching policy.
4. A missing policy on an RLS-enabled table means default deny for roles subject to RLS.
5. Referential-integrity checks, including unique and foreign-key checks, bypass row security and may create information side channels.
6. A custom setting such as `app.current_tenant_id` is context supplied by the database client. It is not independently authenticated or cryptographically protected by PostgreSQL. If an attacker can execute arbitrary SQL as the application role, they may be able to change a custom setting. Prevent SQL injection and do not treat the setting itself as proof of identity.

## 3. Database role separation

Use separate roles for migrations/ownership and runtime access. The following is an illustrative starting point; adapt grants to the actual schema and deployment process.

```sql
-- Run as a controlled database administrator.
CREATE ROLE app_owner NOLOGIN;
CREATE ROLE app_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

-- The runtime role must not own tenant tables and must not inherit a role
-- that owns them or has BYPASSRLS/SUPERUSER.
-- Grant only the required schema and table privileges.
GRANT USAGE ON SCHEMA public TO app_runtime;

-- Table-level grants are applied after the tenant tables are created (section 4).
```

Do not grant `TRUNCATE`, schema ownership, role membership with elevated privileges, or broad grants unless explicitly required and separately reviewed. Verify effective role membership and attributes in the deployed database.

## 4. Tenant context and policy example

The application must:
1. Validate the authenticated identity and authorize its tenant membership on the server.
2. Begin a transaction.
3. Set the tenant context transaction-locally using a parameterized query.
4. Execute all tenant-scoped queries in that same transaction.
5. Commit or roll back before returning the connection to the pool.

Example transaction setup (use a parameterized value, not string concatenation):

```sql
SELECT set_config('app.current_tenant_id', $1, true);
```

The third argument `true` makes the setting transaction-local. Do not use a session-wide `SET` with pooled connections.

Illustrative table and policy:

```sql
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE customer_invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    invoice_number TEXT NOT NULL,
    total_amount_cents BIGINT NOT NULL CHECK (total_amount_cents >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, invoice_number)
);

-- Assign ownership to the non-login migration/owner role. The runtime role must not own these tables.
ALTER TABLE tenants OWNER TO app_owner;
ALTER TABLE customer_invoices OWNER TO app_owner;

ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_self_access ON tenants
    FOR SELECT
    TO app_runtime
    USING (id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid);

ALTER TABLE customer_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_invoices FORCE ROW LEVEL SECURITY;
CREATE POLICY invoice_tenant_isolation ON customer_invoices
    FOR ALL
    TO app_runtime
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid);

CREATE INDEX customer_invoices_tenant_created_idx
    ON customer_invoices (tenant_id, created_at);

-- Apply only the privileges the runtime application needs.
GRANT SELECT ON tenants TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON customer_invoices TO app_runtime;
```

The example policy is illustrative. Add policies and least-privilege grants for every tenant-scoped table and command actually used by the application. Avoid permissive policies that accidentally broaden access; PostgreSQL combines permissive policies with OR semantics.

## 5. Fail-closed behavior and operational constraints

- If the tenant setting is absent or empty, `current_setting(..., true)` returns NULL (or the `NULLIF` expression returns NULL); the equality predicate is not true, so rows are not visible and writes are rejected by `WITH CHECK`.
- A malformed UUID value raises a cast error. Treat this as a rejected request and investigate; do not describe it as a clean zero-row response.
- Ensure every tenant query, including background jobs, exports, reporting, RPCs, views, and stored procedures, runs under the intended security context.
- Review `SECURITY DEFINER` functions, views, triggers, foreign-key/unique constraint side channels, and administrative/service roles separately.
- For transaction pooling, set tenant context inside the transaction using transaction-local configuration.
- Never expose a service role, database owner, superuser, or `BYPASSRLS` credential to browsers or ordinary application requests.

## 6. Verification checklist

Do not mark this blueprint verified until tests run against the actual deployed PostgreSQL version and runtime role.

| Test | Expected result |
|---|---|
| Runtime role reads its own tenant rows | Only its tenant's rows are visible |
| Runtime role reads another tenant's row by ID | No row is returned |
| Runtime role inserts/updates a row with another tenant ID | Rejected by RLS |
| Tenant context is absent | No tenant rows visible; tenant writes rejected |
| Tenant context is malformed | Statement fails; request is rejected safely |
| Two tenants reuse a pooled connection sequentially | No tenant context leaks between transactions |
| Runtime role attempts to set another tenant context | Must be prevented by the trusted application boundary; explicitly test SQL injection/arbitrary SQL threat model |
| Runtime role attributes are inspected | Not superuser, not table owner, no `BYPASSRLS`, no elevated inherited role |
| Every tenant-scoped table is enumerated | RLS enabled and policies reviewed for all applicable commands |
| Admin, backup, and migration paths are tested | Explicitly authorized and isolated from normal runtime credentials |

A test executed as a superuser or privileged table owner is not evidence that the application runtime role is protected.

## 7. Assumptions, trade-offs, and limitations

- Shared-schema RLS is not a substitute for dedicated databases where contractual or regulatory isolation requires physical separation.
- Index tenant filter columns and measure query plans with realistic data volumes.
- Review foreign-key and unique-constraint behavior for cross-tenant information leakage.
- Do not claim compliance with GDPR, SOC 2, ISO 27001, or any other framework solely because RLS is enabled.
- Record the PostgreSQL version, runtime role, migration owner, transaction-pooling mode, policies, test evidence, reviewer, and review date for each implementation.

## 8. Evidence and maturity

**Current maturity: PROPOSED.** The SQL and checklist above are reference guidance. They have not been executed against a production database as part of this repository change. A reviewer must attach test output and deployment-specific evidence before changing the maturity status.
