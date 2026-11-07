# Blueprint 03: Multi-Tenant Data Isolation & Row-Level Security (RLS)

> **Status: PROPOSED — SECURITY REVIEW REQUIRED**
>
> This blueprint is a reference pattern, not a security certification. RLS is one layer of defense. Production safety depends on database roles, transaction handling, application authentication, key management, every tenant-scoped table, and adversarial testing.

## 1. Problem and scope

In a shared-schema SaaS database, a missing tenant filter can expose another customer's records. PostgreSQL Row-Level Security (RLS) enforces row filtering for roles subject to RLS.

This design uses a short-lived HMAC-signed tenant context. The application authenticates the user, authorizes tenant membership, and signs the tenant identity server-side. PostgreSQL verifies the signature against a private key table before an RLS policy accepts the tenant ID.

Assumptions:
- Tenant-owned rows carry a non-null `tenant_id UUID`.
- The application authenticates the user and authorizes tenant membership before issuing a context.
- The HMAC signing secret is held only by a trusted application-side secret manager and the private database key table; it is never sent to browsers or ordinary clients.
- Each tenant request runs in a transaction and sets all context fields transaction-locally.
- The application connects using a dedicated non-owner, non-superuser role without `BYPASSRLS`.
- Untrusted callers cannot execute arbitrary SQL. Signed context reduces the impact of changing a custom GUC, but does not make SQL injection safe.

## 2. Critical PostgreSQL security facts and threat boundary

1. Superusers and roles with `BYPASSRLS` bypass RLS.
2. Table owners normally bypass RLS; `FORCE ROW LEVEL SECURITY` subjects the owner to policies, but does not constrain superusers or `BYPASSRLS` roles.
3. RLS does not replace SQL privileges. A role needs ordinary table privileges as well as a matching policy.
4. A missing policy on an RLS-enabled table means default deny for roles subject to RLS.
5. Custom settings are caller-controlled. The tenant ID is trusted only after PostgreSQL validates an HMAC over the version, key ID, tenant UUID, and expiry.
6. Signed context is not a defense against a compromised application server or leaked signing key. An attacker who obtains a valid signed context may replay it until expiry; keep the lifetime short and never expose the fields outside trusted server/database handling.
7. Arbitrary SQL execution remains a serious vulnerability. It may let an attacker read or replay the current request's context, tamper with application data within that tenant, or exploit other database permissions. Prevent SQL injection independently.

## 3. Database role separation and prerequisites

Use separate roles for migrations/ownership and runtime access. The following is an illustrative starting point; adapt grants to the actual schema and deployment process.

```sql
-- Run as a controlled database administrator.
CREATE ROLE app_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE app_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

GRANT USAGE, CREATE ON SCHEMA public TO app_owner;
GRANT USAGE ON SCHEMA public TO app_runtime;
```

Do not grant `TRUNCATE`, schema ownership, elevated role membership, or broad grants unless explicitly required and separately reviewed. Verify effective role membership and attributes in the deployed database.

The migration administrator must install PostgreSQL's `pgcrypto` extension in a dedicated schema. The extension and key table are database prerequisites; do not let the runtime role install extensions or manage keys.

## 4. Signed tenant context and RLS policy

### 4.1 Context format and application contract

The trusted application generates a short-lived HMAC-SHA256 signature over this exact UTF-8 payload:

```text
v1|<key_id>|<canonical-lowercase-tenant-uuid>|<expiry-unix-seconds>
```

Inside a transaction, set all four values with parameterized calls and transaction-local scope:

- `app.tenant_id`
- `app.tenant_exp`
- `app.tenant_kid`
- `app.tenant_sig` (64 lowercase hexadecimal characters)

The application must derive the tenant ID from its authenticated and authorized server-side identity—not from a request parameter. Set a maximum token lifetime of five minutes. Never log the signing secret or expose signed context fields to an untrusted client.

### 4.2 Private key storage and validator

Run the following DDL as a controlled migration administrator. Provision real key material through a secret-management procedure; the example deliberately contains no production secret.

```sql
CREATE SCHEMA IF NOT EXISTS private AUTHORIZATION app_owner;
CREATE SCHEMA IF NOT EXISTS crypto AUTHORIZATION app_owner;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA crypto;

CREATE TABLE private.tenant_context_keys (
    key_id TEXT PRIMARY KEY CHECK (key_id ~ '^[a-zA-Z0-9_-]{1,32}$'),
    secret BYTEA NOT NULL CHECK (octet_length(secret) >= 32),
    active_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ
);
ALTER TABLE private.tenant_context_keys OWNER TO app_owner;
REVOKE ALL ON private.tenant_context_keys FROM PUBLIC, app_runtime;

CREATE OR REPLACE FUNCTION private.current_tenant_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, private, crypto
AS $function$
DECLARE
    v_tenant TEXT;
    v_exp_text TEXT;
    v_kid TEXT;
    v_sig TEXT;
    v_exp BIGINT;
    v_secret BYTEA;
    v_payload TEXT;
    v_expected TEXT;
    v_now BIGINT;
BEGIN
    v_tenant := current_setting('app.tenant_id', true);
    v_exp_text := current_setting('app.tenant_exp', true);
    v_kid := current_setting('app.tenant_kid', true);
    v_sig := current_setting('app.tenant_sig', true);

    IF v_tenant IS NULL OR v_tenant !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       OR v_exp_text IS NULL OR v_exp_text !~ '^[0-9]{1,12}$'
       OR v_kid IS NULL OR v_kid !~ '^[a-zA-Z0-9_-]{1,32}$'
       OR v_sig IS NULL OR v_sig !~ '^[0-9a-f]{64}$' THEN
        RETURN NULL;
    END IF;

    v_exp := v_exp_text::BIGINT;
    v_now := floor(extract(epoch FROM statement_timestamp()))::BIGINT;
    IF v_exp <= v_now OR v_exp > v_now + 300 THEN
        RETURN NULL;
    END IF;

    SELECT k.secret INTO v_secret
      FROM private.tenant_context_keys AS k
     WHERE k.key_id = v_kid
       AND k.active_from <= statement_timestamp()
       AND (k.expires_at IS NULL OR k.expires_at > statement_timestamp())
       AND k.revoked_at IS NULL;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    v_payload := 'v1|' || v_kid || '|' || v_tenant || '|' || v_exp_text;
    v_expected := encode(crypto.hmac(convert_to(v_payload, 'UTF8'), v_secret, 'sha256'), 'hex');

    IF v_sig <> v_expected THEN
        RETURN NULL;
    END IF;

    RETURN v_tenant::UUID;
EXCEPTION
    WHEN OTHERS THEN
        -- Invalid or incomplete context must fail closed.
        RETURN NULL;
END
$function$;

ALTER FUNCTION private.current_tenant_id() OWNER TO app_owner;
REVOKE ALL ON FUNCTION private.current_tenant_id() FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO app_runtime;
GRANT EXECUTE ON FUNCTION private.current_tenant_id() TO app_runtime;
```

Security notes:
- The function is `SECURITY DEFINER`, owned by the non-login `app_owner`, and pins a safe `search_path`. Keep the function body fully schema-qualified when adding objects.
- Runtime receives only schema usage and function execution. It receives no `SELECT`, `INSERT`, `UPDATE`, or `DELETE` privilege on the key table.
- Revoke function execution from `PUBLIC`; grant it only to the intended runtime role(s).
- Rotate keys by adding a new key ID, switching the application signer, and revoking the old key after the maximum token lifetime. Restrict key provisioning to a controlled administrator/secret-management process.
- Review extension placement and ownership in the actual deployment. Do not move or replace the `crypto.hmac` function with an untrusted implementation.

### 4.3 Tenant tables and policies

The following example assumes the validator and key table above have been created:

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

ALTER TABLE tenants OWNER TO app_owner;
ALTER TABLE customer_invoices OWNER TO app_owner;

ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_self_access ON tenants
    FOR SELECT TO app_runtime
    USING (id = private.current_tenant_id());

ALTER TABLE customer_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_invoices FORCE ROW LEVEL SECURITY;
CREATE POLICY invoice_tenant_isolation ON customer_invoices
    FOR ALL TO app_runtime
    USING (tenant_id = private.current_tenant_id())
    WITH CHECK (tenant_id = private.current_tenant_id());

CREATE INDEX customer_invoices_tenant_created_idx
    ON customer_invoices (tenant_id, created_at);

GRANT SELECT ON tenants TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON customer_invoices TO app_runtime;
```

Add policies and least-privilege grants for every tenant-scoped table and command actually used. Avoid permissive policies that accidentally broaden access; PostgreSQL combines permissive policies with OR semantics.

## 5. Fail-closed behavior and operational constraints

- Missing, malformed, expired, revoked, unknown-key, or incorrectly signed context returns NULL from the validator. The RLS equality predicate is then not true, so reads return no tenant rows and writes are rejected by `WITH CHECK`.
- The five-minute maximum is enforced by the database validator, even if the application accidentally issues a longer expiry.
- Set all four GUC values transaction-locally. Commit or roll back before returning the pooled connection.
- Ensure every tenant query—including background jobs, exports, reporting, RPCs, views, and stored procedures—runs under the intended signed context.
- Review `SECURITY DEFINER` functions, views, triggers, foreign-key/unique constraint side channels, and administrative/service roles separately.
- Never expose a service role, database owner, superuser, `BYPASSRLS` credential, or HMAC signing secret to browsers or ordinary application requests.

## 6. Verification checklist

Do not mark this blueprint verified until tests run against the actual deployed PostgreSQL version and runtime role.

| Test | Expected result |
|---|---|
| Runtime role reads its own tenant rows with a valid signature | Only its tenant's rows are visible |
| Runtime role changes tenant ID but reuses the original signature | No tenant rows are visible |
| Runtime role supplies a forged signature | No tenant rows are visible |
| Context is absent, malformed, expired, revoked, or uses an unknown key | No tenant rows visible; tenant writes rejected |
| Runtime role attempts to read the private key table | Permission denied |
| Runtime role inserts/updates another tenant's row | Rejected or hidden by RLS |
| Two tenants reuse a pooled connection sequentially | No context leaks between transactions |
| Runtime role attributes and ownership are inspected | Not superuser, not table owner, no `BYPASSRLS`, no elevated inherited role |
| Every tenant-scoped table is enumerated | RLS enabled and policies reviewed for all applicable commands |
| Admin, backup, migration, and key-rotation paths are tested | Explicitly authorized and isolated from runtime credentials |

A test executed as a superuser or privileged table owner is not evidence that the application runtime role is protected.

## 7. Assumptions, trade-offs, and limitations

- HMAC context limits tenant switching by a caller who can alter custom GUC values but cannot obtain a valid signature for another tenant. It does not prevent SQL injection, same-tenant abuse, application compromise, signing-key compromise, or replay of a stolen valid token before expiry.
- The database validator performs an HMAC operation during policy evaluation. Measure its impact with realistic workloads and consider safe caching only after a separate security review.
- Shared-schema RLS is not a substitute for dedicated databases where contractual or regulatory isolation requires physical separation.
- Review foreign-key and unique-constraint behavior for cross-tenant information leakage.
- Do not claim compliance with GDPR, SOC 2, ISO 27001, or any other framework solely because RLS and signed context are enabled.
- Record PostgreSQL version, runtime role, migration owner, transaction-pooling mode, key-management procedure, policies, test evidence, reviewer, and review date for each implementation.

## 8. Evidence and maturity

**Current maturity: PROPOSED.** The SQL and checklist are reference guidance. Repository CI tests the blueprint against PostgreSQL 16 using deterministic test-only key material. This is not a production deployment test, penetration test, or independent security review. Attach deployment-specific evidence and reviewer sign-off before changing the maturity status.
