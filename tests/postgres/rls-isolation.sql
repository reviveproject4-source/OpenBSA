\set ON_ERROR_STOP on

-- This test runs as the PostgreSQL superuser only for setup and role switching.
-- Runtime assertions execute with current_user = app_runtime or app_owner.

CREATE ROLE app_owner NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE ROLE app_runtime LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE SCHEMA tenant_test AUTHORIZATION app_owner;
GRANT USAGE ON SCHEMA tenant_test TO app_runtime;

SET ROLE app_owner;

CREATE TABLE tenant_test.tenants (
    id UUID PRIMARY KEY,
    company_name TEXT NOT NULL
);

CREATE TABLE tenant_test.customer_invoices (
    id UUID PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES tenant_test.tenants(id),
    invoice_number TEXT NOT NULL,
    total_amount_cents BIGINT NOT NULL CHECK (total_amount_cents >= 0),
    UNIQUE (tenant_id, invoice_number)
);

ALTER TABLE tenant_test.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_test.tenants FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_self_access ON tenant_test.tenants
    FOR SELECT TO app_runtime
    USING (id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid);

ALTER TABLE tenant_test.customer_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_test.customer_invoices FORCE ROW LEVEL SECURITY;
CREATE POLICY invoice_tenant_isolation ON tenant_test.customer_invoices
    FOR ALL TO app_runtime
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid);

CREATE INDEX customer_invoices_tenant_created_idx
    ON tenant_test.customer_invoices (tenant_id, invoice_number);

GRANT SELECT ON tenant_test.tenants TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON tenant_test.customer_invoices TO app_runtime;

RESET ROLE;

-- Seed data as the database administrator. Runtime access is tested below.
INSERT INTO tenant_test.tenants (id, company_name) VALUES
    ('11111111-1111-4111-8111-111111111111', 'Tenant A'),
    ('22222222-2222-4222-8222-222222222222', 'Tenant B');

INSERT INTO tenant_test.customer_invoices (id, tenant_id, invoice_number, total_amount_cents) VALUES
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'A-001', 10000),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '22222222-2222-4222-8222-222222222222', 'B-001', 20000);

DO $$
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
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'tenant_test'
          AND c.relkind = 'r'
          AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
    ) THEN
        RAISE EXCEPTION 'A tenant table is missing ENABLE or FORCE ROW LEVEL SECURITY';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_roles r ON r.oid = c.relowner
        WHERE n.nspname = 'tenant_test'
          AND c.relkind = 'r'
          AND r.rolname <> 'app_owner'
    ) THEN
        RAISE EXCEPTION 'A tenant table is not owned by app_owner';
    END IF;
END
$$;

-- FORCE ROW LEVEL SECURITY also subjects the table owner to policy evaluation.
SET ROLE app_owner;
BEGIN;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM tenant_test.tenants)
       OR EXISTS (SELECT 1 FROM tenant_test.customer_invoices) THEN
        RAISE EXCEPTION 'app_owner unexpectedly bypassed forced RLS';
    END IF;
END
$$;
COMMIT;
RESET ROLE;

SET ROLE app_runtime;

-- No tenant context: both tenant tables must fail closed.
BEGIN;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM tenant_test.tenants)
       OR EXISTS (SELECT 1 FROM tenant_test.customer_invoices) THEN
        RAISE EXCEPTION 'Rows are visible without tenant context';
    END IF;
END
$$;
COMMIT;

-- Tenant A sees only Tenant A's tenant row and invoice.
BEGIN;
SELECT set_config('app.current_tenant_id', '11111111-1111-4111-8111-111111111111', true);
DO $$
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
$$;
COMMIT;

-- Cross-tenant INSERT must be rejected by WITH CHECK.
BEGIN;
SELECT set_config('app.current_tenant_id', '11111111-1111-4111-8111-111111111111', true);
DO $$
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
$$;
COMMIT;

-- Cross-tenant UPDATE must not affect another tenant's row.
BEGIN;
SELECT set_config('app.current_tenant_id', '11111111-1111-4111-8111-111111111111', true);
DO $$
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
$$;
COMMIT;

-- A transaction-local setting must not leak into the next transaction on a reused connection.
BEGIN;
SELECT set_config('app.current_tenant_id', '11111111-1111-4111-8111-111111111111', true);
COMMIT;
BEGIN;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM tenant_test.customer_invoices) THEN
        RAISE EXCEPTION 'Tenant context leaked across transactions';
    END IF;
END
$$;
COMMIT;

RESET ROLE;

-- Verify the rejected write and hidden update left Tenant B's invoice unchanged.
DO $$
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
$$;

\echo 'PASS: PostgreSQL tenant RLS smoke tests completed.'
