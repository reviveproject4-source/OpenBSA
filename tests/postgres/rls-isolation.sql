\set ON_ERROR_STOP on

-- Run setup as postgres. The RLS DDL itself is extracted from the OpenBSA
-- blueprint and executed unchanged by the workflow before this test file runs.
CREATE ROLE app_owner NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE ROLE app_runtime LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE SCHEMA tenant_test AUTHORIZATION app_owner;
GRANT USAGE ON SCHEMA tenant_test TO app_runtime;
SET search_path TO tenant_test, public;

-- The workflow executes /tmp/openbsa-rls-blueprint.sql here. That file is
-- extracted from section 4 of 06-edge-cases-and-anti-failure/03-multi-tenant-data-isolation-rls.md.
\i /tmp/openbsa-rls-blueprint.sql

-- Seed as postgres, which intentionally bypasses RLS for controlled fixtures.
INSERT INTO tenant_test.tenants (id, company_name) VALUES
    ('11111111-1111-4111-8111-111111111111', 'Tenant A'),
    ('22222222-2222-4222-8222-222222222222', 'Tenant B');

INSERT INTO tenant_test.customer_invoices (id, tenant_id, invoice_number, total_amount_cents) VALUES
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'A-001', 10000),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '22222222-2222-4222-8222-222222222222', 'B-001', 20000);

DO $role_checks$
BEGIN
    IF (SELECT rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole
        FROM pg_roles WHERE rolname = 'app_runtime') THEN
        RAISE EXCEPTION 'app_runtime has an elevated role attribute';
    END IF;
    IF (SELECT rolcanlogin OR rolsuper OR rolbypassrls
        FROM pg_roles WHERE rolname = 'app_owner') THEN
        RAISE EXCEPTION 'app_owner must be NOLOGIN, NOSUPERUSER, and NOBYPASSRLS';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'tenant_test' AND c.relkind = 'r'
          AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
    ) THEN
        RAISE EXCEPTION 'A tenant table is missing ENABLE or FORCE ROW LEVEL SECURITY';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_roles r ON r.oid = c.relowner
        WHERE n.nspname = 'tenant_test' AND c.relkind = 'r'
          AND r.rolname <> 'app_owner'
    ) THEN
        RAISE EXCEPTION 'A tenant table is not owned by app_owner';
    END IF;
END
$role_checks$;

-- FORCE ROW LEVEL SECURITY subjects the non-login table owner to policies.
SET ROLE app_owner;
BEGIN;
DO $owner_checks$
BEGIN
    IF EXISTS (SELECT 1 FROM tenant_test.tenants)
       OR EXISTS (SELECT 1 FROM tenant_test.customer_invoices) THEN
        RAISE EXCEPTION 'app_owner unexpectedly bypassed forced RLS';
    END IF;
END
$owner_checks$;
COMMIT;
RESET ROLE;

SET ROLE app_runtime;

-- Missing context must fail closed for both tenant-owned tables.
BEGIN;
DO $no_context$
BEGIN
    IF EXISTS (SELECT 1 FROM tenant_test.tenants)
       OR EXISTS (SELECT 1 FROM tenant_test.customer_invoices) THEN
        RAISE EXCEPTION 'Rows are visible without tenant context';
    END IF;
END
$no_context$;
COMMIT;

-- Tenant A sees its own tenant row and invoice, and no Tenant B records.
BEGIN;
SELECT set_config('app.current_tenant_id', '11111111-1111-4111-8111-111111111111', true);
DO $tenant_a$
DECLARE invoice_count INTEGER;
BEGIN
    SELECT count(*) INTO invoice_count FROM tenant_test.customer_invoices;
    IF invoice_count <> 1 THEN
        RAISE EXCEPTION 'Tenant A expected one invoice, found %', invoice_count;
    END IF;
    IF EXISTS (SELECT 1 FROM tenant_test.customer_invoices
               WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') THEN
        RAISE EXCEPTION 'Tenant A can read Tenant B invoice';
    END IF;
    IF (SELECT count(*) FROM tenant_test.tenants) <> 1 THEN
        RAISE EXCEPTION 'Tenant A can see an unexpected tenant row';
    END IF;
END
$tenant_a$;
COMMIT;

-- Malformed tenant UUID must fail with a cast error, not broaden access.
BEGIN;
SELECT set_config('app.current_tenant_id', 'not-a-uuid', true);
DO $malformed$
BEGIN
    BEGIN
        PERFORM 1 FROM tenant_test.customer_invoices;
        RAISE EXCEPTION 'Malformed tenant context was unexpectedly accepted';
    EXCEPTION
        WHEN invalid_text_representation THEN
            NULL;
    END;
END
$malformed$;
COMMIT;

-- Trust-boundary demonstration: arbitrary SQL as app_runtime can change a custom GUC.
-- The application must never expose arbitrary SQL execution to untrusted callers.
BEGIN;
SELECT set_config('app.current_tenant_id', '22222222-2222-4222-8222-222222222222', true);
DO $trust_boundary$
BEGIN
    IF (SELECT count(*) FROM tenant_test.customer_invoices) <> 1 THEN
        RAISE EXCEPTION 'Expected the runtime role to be able to change its custom GUC';
    END IF;
END
$trust_boundary$;
COMMIT;

-- Cross-tenant INSERT must be rejected by WITH CHECK.
BEGIN;
SELECT set_config('app.current_tenant_id', '11111111-1111-4111-8111-111111111111', true);
DO $cross_insert$
BEGIN
    BEGIN
        INSERT INTO tenant_test.customer_invoices
            (id, tenant_id, invoice_number, total_amount_cents)
        VALUES
            ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
             '22222222-2222-4222-8222-222222222222', 'A-ILLEGAL', 500);
        RAISE EXCEPTION 'Cross-tenant INSERT was unexpectedly accepted';
    EXCEPTION
        WHEN insufficient_privilege THEN
            NULL;
    END;
END
$cross_insert$;
COMMIT;

-- Cross-tenant UPDATE must not affect Tenant B's row.
BEGIN;
SELECT set_config('app.current_tenant_id', '11111111-1111-4111-8111-111111111111', true);
DO $cross_update$
DECLARE affected_rows INTEGER;
BEGIN
    UPDATE tenant_test.customer_invoices
       SET total_amount_cents = 1
     WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows <> 0 THEN
        RAISE EXCEPTION 'Cross-tenant UPDATE affected % rows', affected_rows;
    END IF;
END
$cross_update$;
COMMIT;

-- Transaction-local tenant context must not leak to the next transaction on a pooled connection.
BEGIN;
SELECT set_config('app.current_tenant_id', '11111111-1111-4111-8111-111111111111', true);
COMMIT;
BEGIN;
DO $pool_reset$
BEGIN
    IF EXISTS (SELECT 1 FROM tenant_test.customer_invoices) THEN
        RAISE EXCEPTION 'Tenant context leaked across transactions';
    END IF;
END
$pool_reset$;
COMMIT;

RESET ROLE;

-- Verify Tenant B's invoice was not changed and no cross-tenant invoice was inserted.
DO $final_checks$
BEGIN
    IF (SELECT total_amount_cents FROM tenant_test.customer_invoices
        WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') <> 20000 THEN
        RAISE EXCEPTION 'Tenant B invoice was modified by Tenant A';
    END IF;
    IF EXISTS (SELECT 1 FROM tenant_test.customer_invoices
               WHERE id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc') THEN
        RAISE EXCEPTION 'Cross-tenant invoice was inserted';
    END IF;
END
$final_checks$;

\echo 'PASS: OpenBSA blueprint SQL passed PostgreSQL tenant-isolation smoke tests.'
