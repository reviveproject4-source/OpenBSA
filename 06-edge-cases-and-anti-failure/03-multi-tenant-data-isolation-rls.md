# Blueprint 03: Multi-Tenant Data Isolation & RLS

> **Target Problem:** A developer forgets to append `WHERE tenant_id = current_tenant` in a newly added export endpoint. A user from Company A clicks "Export Invoices" and accidentally downloads Company B's confidential pricing, customer names, and revenue data.

---

## 1. Assumptions (Asumsi)
* **Shared-Database Multi-Tenancy:** The business operates a multi-tenant SaaS architecture where multiple companies share the same PostgreSQL database schema to minimize infrastructure costs.
* **Human Engineering Fallibility:** Developers will inevitably forget to manually append `WHERE tenant_id = ?` to every query as the codebase scales to hundreds of endpoints.
* **Zero Cross-Tenant Tolerance:** Enterprise B2B customers require zero tolerance for data leaks under SOC2, ISO27001, and GDPR compliance.

---

## 2. Prerequisites (Prasyarat)
* **PostgreSQL 12+:** Native support for `ROW LEVEL SECURITY` (RLS) and `FORCE ROW LEVEL SECURITY`.
* **Session Parameter Middleware:** Backend framework capable of executing session initialization (`SET LOCAL app.current_tenant_id = :tenant_id`) upon checking out a database connection from the pool.

---

## 3. Failure Scenario & Blast Radius (Skenario Kegagalan)
* **The Failure Story:** A B2B SaaS startup closes a $5,000/month enterprise client. A junior developer ships a feature: `GET /api/v1/customers/search?q=acme`. The developer uses a direct SQL query without a tenant filter. An enterprise user searches for a prospect and sees full contact details, order sizes, and discount rates belonging to their direct market competitor who also uses the platform.
* **Financial Impact:** Customer immediately terminates contract, demands a full refund, and reports the data breach to the regulatory privacy commission, resulting in a potential GDPR penalty of up to 4% of annual turnover.
* **Blast Radius:** Total compromise of data confidentiality across all tenants in the system.

---

## 4. Architectural Blueprint & DDL (Spesifikasi Arsitektur)

```mermaid
graph TD
    classDef client fill:#e1f5fe,stroke:#0288d1,stroke-width:2px;
    classDef middleware fill:#ede7f6,stroke:#512da8,stroke-width:2px;
    classDef rls fill:#ffebee,stroke:#c62828,stroke-width:2px;
    classDef db fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;

    User[User Request: JWT Claims tenant_id = 't-123']:::client --> MW[API Auth Middleware]:::middleware
    MW -->|Extracts Claims & Opens DB Transaction| DBConn[DB Connection Session]:::middleware
    
    DBConn -->|Executes: <code>SET LOCAL app.current_tenant_id = 't-123'</code>| Kernel[PostgreSQL RLS Engine]:::rls
    
    Query[Developer Query: <code>SELECT * FROM customer_invoices;</code>]:::middleware --> Kernel
    
    Kernel -->|PostgreSQL auto-injects:<br/><code>tenant_id = current_setting('app.current_tenant_id')::UUID</code>| Result[Returns ONLY Records Belonging to 't-123']:::db
    Kernel -.->|Blocks & Hides Silently| OtherTenants[Tenant 't-456' Records Completely Invisible]:::rls
```

```sql
-- Production DDL: Kernel-Level RLS Policy
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name VARCHAR(255) NOT NULL,
    plan_tier VARCHAR(50) NOT NULL DEFAULT 'standard',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE customer_invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    invoice_number VARCHAR(50) NOT NULL,
    total_amount_cents BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1. Enable RLS on the table
ALTER TABLE customer_invoices ENABLE ROW LEVEL SECURITY;

-- 2. CRITICAL: Force RLS for table owners to prevent superuser bypasses
ALTER TABLE customer_invoices FORCE ROW LEVEL SECURITY;

-- 3. Define the strict isolation policy
CREATE POLICY tenant_isolation_policy ON customer_invoices
    FOR ALL
    USING (
        tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
    )
    WITH CHECK (
        tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
    );
```

---

## 5. Recovery Strategy & Self-Healing (Strategi Pemulihan)
* **Fail-Closed Default:** If `app.current_tenant_id` is empty, unset, or malformed, the PostgreSQL policy evaluates to `NULL`, returning **0 rows**. The system fails closed rather than failing open.
* **Automated Audit Alert on Cross-Tenant Probe:** An exception logging hook triggers whenever a query explicitly requests an ID belonging to a different tenant, generating an immediate `P1_SECURITY_BREACH_PROBE` alert to the security operations team.

---

## 6. Security Boundary & Access Scope (Batas Keamanan)
* **Immutable Tenant Claim:** The `tenant_id` is cryptographically signed inside the user's JWT at login and cannot be altered by query parameters, request headers, or client-side payloads.
* **Separation of Superuser Roles:** The web application connects to PostgreSQL using a restricted role (`app_user`) that cannot bypass RLS (`NOBYPASSRLS`). Only migration scripts run under the schema owner role.

---

## 7. Test Scenarios (Skenario Pengujian)

```gherkin
Feature: Multi-Tenant Data Isolation

  Scenario: Tenant Queries Their Own Invoices
    Given tenant "Alpha-Corp" has 3 invoices in the database
    When a user from "Alpha-Corp" executes "SELECT * FROM customer_invoices"
    Then the database returns exactly 3 records belonging to "Alpha-Corp"

  Scenario: Developer Forgets Tenant Filter (Cross-Tenant Leak Prevention)
    Given tenant "Alpha-Corp" has invoice "INV-001"
    And tenant "Beta-LLC" has invoice "INV-002"
    When an authenticated user from "Alpha-Corp" queries "SELECT * FROM customer_invoices" without a WHERE clause
    Then the database returns ONLY "INV-001"
    And invoice "INV-002" is completely invisible

  Scenario: Explicit Cross-Tenant ID Tampering
    Given an authenticated user from "Alpha-Corp"
    When the user requests "GET /api/invoices/INV-002" (belonging to "Beta-LLC")
    Then the system returns HTTP 404 Not Found
    And zero data bytes from "Beta-LLC" are leaked in the response
```

---

## 8. Batasan Penerapan & Trade-offs (Kapan JANGAN Digunakan)
* **Contraindications:** Do not implement shared-schema RLS for highly regulated government defense contracts or healthcare systems requiring separate physical databases or isolated dedicated servers per customer.
* **Performance Overhead:** RLS adds an automatic query planner constraint. For high-throughput analytics queries (>10 million rows), ensure that `tenant_id` is the primary leading column in all composite indexes (e.g. `CREATE INDEX idx_invoices_tenant_date ON customer_invoices(tenant_id, created_at)`).
