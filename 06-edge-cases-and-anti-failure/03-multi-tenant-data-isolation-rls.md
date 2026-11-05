# Blueprint 03: Multi-Tenant Data Isolation & RLS

> **Target Problem:** A developer forgets to add `WHERE tenant_id = current_tenant` inside a newly added export endpoint. A user from Company A clicks "Export Invoices" and accidentally downloads Company B's confidential pricing, customer names, and revenue numbers.

---

## 1. The Nightmare Scenario
A B2B SaaS startup signs its first enterprise customer paying $5,000/month. 
Two months later, a junior developer ships a feature: `GET /api/v1/customers/search?q=john`. 
The developer forgets to filter by `tenant_id` in the raw SQL query.
The enterprise customer searches for a contact and sees contacts belonging to their direct competitor who also uses the SaaS platform.
The enterprise customer files a GDPR breach report, terminates their contract, and sues the startup for breach of confidentiality.

---

## 2. Architectural Blueprint: Database-Level Row-Level Security (RLS)

Never rely on developer discipline to append `WHERE tenant_id = x` in every backend query. Instead, enforce isolation directly at the database kernel level using PostgreSQL **Row-Level Security (RLS)**.

```mermaid
graph TD
    classDef client fill:#e1f5fe,stroke:#0288d1,stroke-width:2px;
    classDef app fill:#ede7f6,stroke:#512da8,stroke-width:2px;
    classDef rls fill:#ffebee,stroke:#c62828,stroke-width:2px;
    classDef db fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;

    User[Client Request: Tenant X]:::client --> App[Backend Application / API Gateway]:::app
    App -->|Extracts JWT: tenant_id = 'uuid-tenant-x'| Session[Set DB Session Config:<br/><code>SET LOCAL app.current_tenant_id = 'uuid-tenant-x'</code>]:::app
    
    Session --> Query[Any Query: <code>SELECT * FROM customers;</code>]:::app
    Query --> RLSKernel[PostgreSQL Engine RLS Kernel]:::rls
    
    RLSKernel -->|Auto-injected constraint:<br/><code>tenant_id = current_setting('app.current_tenant_id')</code>| Filtered[Data Table: ONLY Tenant X Rows Visible]:::db
    RLSKernel -.->|Blocks access silently| OtherData[Tenant Y & Z Data Completely Invisible]:::rls
```

---

## 3. Database Specification: The Bulletproof RLS Pattern

```sql
-- 1. Create the tenant context table
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name VARCHAR(255) NOT NULL,
    plan_tier VARCHAR(50) NOT NULL DEFAULT 'standard',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Create an isolated business table
CREATE TABLE customer_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    customer_name VARCHAR(255) NOT NULL,
    total_amount_cents BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. ENABLE ROW LEVEL SECURITY
ALTER TABLE customer_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_orders FORCE ROW LEVEL SECURITY; -- Also applies to table owners!

-- 4. DEFINE THE STRICT ISOLATION POLICY
CREATE POLICY tenant_isolation_policy ON customer_orders
    FOR ALL
    USING (
        tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
    )
    WITH CHECK (
        tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
    );
```

---

## 4. Middleware Implementation Pattern (Node.js / Go / Python)

Every database connection checked out from the connection pool MUST execute the tenant injection header before running any business query:

```typescript
// Example: Express / Next.js API Middleware
export async function withTenantContext(req: Request, tenantId: string, callback: (client: PoolClient) => Promise<any>) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Set transaction-local session variable. 
    // If the developer forgets WHERE tenant_id, Postgres filters it automatically!
    await client.query("SELECT set_config('app.current_tenant_id', $1, true)", [tenantId]);
    
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
```

---

## 5. Automated Security Test in CI/CD

```gherkin
Feature: Multi-tenant Data Breach Prevention
  Scenario: Cross-tenant data leak attempt via API
    Given User A belongs to Tenant "Company-Alpha"
    And User B belongs to Tenant "Company-Beta"
    And Company-Beta has an invoice with ID "INV-999"
    When User A attempts to request "GET /api/invoices/INV-999"
    Then the system must respond with HTTP 404 Not Found
    And the database query must return 0 records
    And an alert must be logged: "UNAUTHORIZED_CROSS_TENANT_ACCESS_ATTEMPT"
```
