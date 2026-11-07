\set ON_ERROR_STOP on

-- Run setup as postgres. The RLS DDL is extracted unchanged from blueprint section 4.
CREATE ROLE app_owner NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE ROLE app_runtime LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE SCHEMA tenant_test AUTHORIZATION app_owner;
GRANT USAGE ON SCHEMA tenant_test TO app_runtime;
SET search_path TO tenant_test, public;

\i /tmp/openbsa-rls-blueprint.sql

-- Deterministic TEST-ONLY key. Never use this value outside CI.
INSERT INTO private.tenant_context_keys (key_id, secret)
VALUES ('ci-key', decode(repeat('ab', 32), 'hex'));

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
    IF has_table_privilege('app_runtime', 'private.tenant_context_keys', 'SELECT') THEN
        RAISE EXCEPTION 'app_runtime must not read the private signing-key table';
    END IF;
    IF NOT has_function_privilege('app_runtime', 'private.current_tenant_id()', 'EXECUTE') THEN
        RAISE EXCEPTION 'app_runtime must be able to execute the validator';
    END IF;
END
$role_checks$;

-- FORCE ROW LEVEL SECURITY subjects the non-login owner to policies.
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

-- Build short-lived signatures as the test administrator, not app_runtime.
SELECT (floor(extract(epoch FROM clock_timestamp()))::BIGINT + 120)::TEXT AS valid_exp \gset
SELECT encode(
    crypto.hmac(
        convert_to('v1|ci-key|11111111-1111-4111-8111-111111111111|' || :'valid_exp', 'UTF8'),
        decode(repeat('ab', 32), 'hex'),
        'sha256'
    ), 'hex'
) AS valid_sig \gset
SELECT (floor(extract(epoch FROM clock_timestamp()))::BIGINT - 10)::TEXT AS expired_exp \gset
SELECT encode(
    crypto.hmac(
        convert_to('v1|ci-key|11111111-1111-4111-8111-111111111111|' || :'expired_exp', 'UTF8'),
        decode(repeat('ab', 32), 'hex'),
        'sha256'
    ), 'hex'
) AS expired_sig \gset

SET ROLE app_runtime;

-- Missing context must fail closed.
BEGIN;
DO $no_context$
BEGIN
    IF private.current_tenant_id() IS NOT NULL
       OR EXISTS (SELECT 1 FROM tenant_test.tenants)
       OR EXISTS (SELECT 1 FROM tenant_test.customer_invoices) THEN
        RAISE EXCEPTION 'Rows or tenant identity are available without signed context';
    END IF;
END
$no_context$;
COMMIT;

-- Valid Tenant A signature grants access to Tenant A only.
BEGIN;
SELECT set_config('app.tenant_id', '11111111-1111-4111-8111-111111111111', true);
SELECT set_config('app.tenant_exp', :'valid_exp', true);
SELECT set_config('app.tenant_kid', 'ci-key', true);
SELECT set_config('app.tenant_sig', :'valid_sig', true);
DO $valid_tenant$
BEGIN
    IF private.current_tenant_id() <> '11111111-1111-4111-8111-111111111111'::UUID THEN
        RAISE EXCEPTION 'Valid Tenant A signature was not accepted';
    END IF;
    IF (SELECT count(*) FROM tenant_test.customer_invoices) <> 1
       OR EXISTS (SELECT 1 FROM tenant_test.customer_invoices
                  WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') THEN
        RAISE EXCEPTION 'Valid Tenant A context exposed unexpected invoices';
    END IF;
    IF (SELECT count(*) FROM tenant_test.tenants) <> 1 THEN
        RAISE EXCEPTION 'Valid Tenant A context exposed unexpected tenants';
    END IF;
END
$valid_tenant$;
COMMIT;

-- Changing the tenant GUC while reusing Tenant A's signature must fail closed.
BEGIN;
SELECT set_config('app.tenant_id', '22222222-2222-4222-8222-222222222222', true);
SELECT set_config('app.tenant_exp', :'valid_exp', true);
SELECT set_config('app.tenant_kid', 'ci-key', true);
SELECT set_config('app.tenant_sig', :'valid_sig', true);
DO $tampered_tenant$
BEGIN
    IF private.current_tenant_id() IS NOT NULL
       OR EXISTS (SELECT 1 FROM tenant_test.customer_invoices) THEN
        RAISE EXCEPTION 'Tampered tenant ID was accepted';
    END IF;
END
$tampered_tenant$;
COMMIT;

-- A forged signature must fail closed.
BEGIN;
SELECT set_config('app.tenant_id', '11111111-1111-4111-8111-111111111111', true);
SELECT set_config('app.tenant_exp', :'valid_exp', true);
SELECT set_config('app.tenant_kid', 'ci-key', true);
SELECT set_config('app.tenant_sig', repeat('0', 64), true);
DO $forged_signature$
BEGIN
    IF private.current_tenant_id() IS NOT NULL
       OR EXISTS (SELECT 1 FROM tenant_test.customer_invoices) THEN
        RAISE EXCEPTION 'Forged signature was accepted';
    END IF;
END
$forged_signature$;
COMMIT;

-- Expired signatures and unknown key IDs must fail closed.
BEGIN;
SELECT set_config('app.tenant_id', '11111111-1111-4111-8111-111111111111', true);
SELECT set_config('app.tenant_exp', :'expired_exp', true);
SELECT set_config('app.tenant_kid', 'ci-key', true);
SELECT set_config('app.tenant_sig', :'expired_sig', true);
DO $expired_context$
BEGIN
    IF private.current_tenant_id() IS NOT NULL THEN
        RAISE EXCEPTION 'Expired context was accepted';
    END IF;
END
$expired_context$;
COMMIT;

BEGIN;
SELECT set_config('app.tenant_id', '11111111-1111-4111-8111-111111111111', true);
SELECT set_config('app.tenant_exp', :'valid_exp', true);
SELECT set_config('app.tenant_kid', 'unknown-key', true);
SELECT set_config('app.tenant_sig', :'valid_sig', true);
DO $unknown_key$
BEGIN
    IF private.current_tenant_id() IS NOT NULL THEN
        RAISE EXCEPTION 'Unknown key ID was accepted';
    END IF;
END
$unknown_key$;
COMMIT;

-- A valid context cannot authorize cross-tenant INSERT or UPDATE.
BEGIN;
SELECT set_config('app.tenant_id', '11111111-1111-4111-8111-111111111111', true);
SELECT set_config('app.tenant_exp', :'valid_exp', true);
SELECT set_config('app.tenant_kid', 'ci-key', true);
SELECT set_config('app.tenant_sig', :'valid_sig', true);
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
        WHEN insufficient_privilege THEN NULL;
    END;
END
$cross_insert$;
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

-- Revoked keys must stop validating immediately.
RESET ROLE;
UPDATE private.tenant_context_keys SET revoked_at = NOW() WHERE key_id = 'ci-key';
SET ROLE app_runtime;
BEGIN;
SELECT set_config('app.tenant_id', '11111111-1111-4111-8111-111111111111', true);
SELECT set_config('app.tenant_exp', :'valid_exp', true);
SELECT set_config('app.tenant_kid', 'ci-key', true);
SELECT set_config('app.tenant_sig', :'valid_sig', true);
DO $revoked_key$
BEGIN
    IF private.current_tenant_id() IS NOT NULL THEN
        RAISE EXCEPTION 'Revoked key was accepted';
    END IF;
END
$revoked_key$;
COMMIT;

-- Transaction-local context must not leak to the next pooled transaction.
BEGIN;
SELECT set_config('app.tenant_id', '11111111-1111-4111-8111-111111111111', true);
SELECT set_config('app.tenant_exp', :'valid_exp', true);
SELECT set_config('app.tenant_kid', 'ci-key', true);
SELECT set_config('app.tenant_sig', :'valid_sig', true);
COMMIT;
BEGIN;
DO $pool_reset$
BEGIN
    IF private.current_tenant_id() IS NOT NULL
       OR EXISTS (SELECT 1 FROM tenant_test.customer_invoices) THEN
        RAISE EXCEPTION 'Signed tenant context leaked across transactions';
    END IF;
END
$pool_reset$;
COMMIT;
RESET ROLE;

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

\echo 'PASS: OpenBSA signed tenant-context and PostgreSQL RLS tests passed.'
