# Blueprint 04: Immutable Audit Trail & Anti-Fraud Log

> **Target Problem:** A store cashier voids a $200 cash sale after the customer walks out, pocketing the cash and writing off the inventory as "damaged stock". An employee deletes order records before resigning. Without an immutable append-only audit trail, the business owner loses money without forensic evidence of theft.

---

## 1. Assumptions (Asumsi)
* **Insider Threat Reality:** Fraud and theft frequently originate from trusted internal employees with legitimate system access (cashiers, supervisors, admins).
* **Non-Repudiation Requirement:** Actions involving money, discounts, debt cancellations, or record deletions must be permanently provable in a legal dispute.
* **Database WORM (Write-Once-Read-Many):** Audit entries must be permanent; even database administrators cannot edit or delete audit rows without triggering cryptographic alarms.

---

## 2. Prerequisites (Prasyarat)
* **PostgreSQL 12+:** Supporting PL/pgSQL triggers that can intercept and abort `UPDATE` and `DELETE` commands.
* **Cryptographic Hashing:** `pgcrypto` extension or SHA-256 hash chaining to detect retroactive table tampering.

---

## 3. Failure Scenario & Blast Radius (Skenario Kegagalan)
* **The Failure Story:** An operator of a 5-branch retail chain discovers an unexplained $6,000 cash shortage at month-end. When reviewing the database, multiple sales records from the prior 3 weeks are completely missing or modified to $0. The database admin reports: *"Someone with manager credentials ran an UPDATE/DELETE query. We have no record of who logged in, what the original price was, or what terminal was used."*
* **Financial Impact:** Unrecoverable monetary loss ($6,000) and inability to file an insurance claim or police report due to lack of admissible forensic logs.
* **Blast Radius:** Financial accounts, inventory shrinkage calculations, and loss of trust across the entire workforce.

---

## 4. Architectural Blueprint & DDL (Spesifikasi Arsitektur)

```mermaid
graph LR
    classDef client fill:#e1f5fe,stroke:#0288d1,stroke-width:2px;
    classDef action fill:#fff3e0,stroke:#f57c00,stroke-width:2px;
    classDef ledger fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef blocked fill:#ffebee,stroke:#c62828,stroke-width:2px;

    User[Operator / Cashier]:::client -->|Initiates Void / Discount > 10%| Event[Business Action]:::action
    Event --> Write[Append Immutable Audit Entry]:::ledger

    subgraph Database Kernel Triggers
        Write --> Hash[Compute Record Hash:<br/><code>SHA256(PrevHash + Data + Actor + Time)</code>]:::ledger
        Hash --> Ledger[(system_audit_ledger Table)]:::ledger

        Ledger -.->|Attempt UPDATE or DELETE| Guard{SQL Trigger Intercept}:::blocked
        Guard -->|EXECUTION BLOCKED| Error[RAISE EXCEPTION:<br/>'CRITICAL: Audit logs are immutable!']:::blocked
    end
```

```sql
-- Production DDL: Append-Only Immutable Audit Ledger
CREATE TABLE system_audit_ledger (
    id BIGSERIAL PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    actor_id UUID NOT NULL, -- User who performed the action
    actor_role VARCHAR(50) NOT NULL, -- 'CASHIER', 'MANAGER', 'ADMIN'
    ip_address INET,
    action_type VARCHAR(50) NOT NULL, -- 'TRANSACTION_VOID', 'PRICE_OVERRIDE', 'DISCOUNT_APPLIED'
    entity_name VARCHAR(50) NOT NULL, -- 'orders', 'inventory', 'invoices'
    entity_id VARCHAR(100) NOT NULL,
    old_state JSONB, -- NULL on INSERT
    new_state JSONB, -- The modified payload
    reason TEXT NOT NULL, -- Mandatory justification entered by user
    previous_record_hash VARCHAR(64) NOT NULL, -- Blockchain-style tamper detection
    record_hash VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- CRITICAL SECURITY RULE: Trigger that strictly blocks ANY UPDATE or DELETE
CREATE OR REPLACE FUNCTION prevent_audit_tampering()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'CRITICAL SECURITY VIOLATION: Records in system_audit_ledger are immutable and cannot be updated or deleted!';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_immutable_audit
    BEFORE UPDATE OR DELETE ON system_audit_ledger
    FOR EACH ROW
    EXECUTE FUNCTION prevent_audit_tampering();
```

---

## 5. Recovery Strategy & Self-Healing (Strategi Pemulihan)
* **Cryptographic Chain Verification (Nightly Integrity Check):** A nightly worker reads the entire ledger and recalculates the SHA-256 hash chain:
  `Hash_N = SHA256(Hash_{N-1} || RecordData)`. If any historical row was altered via low-level database file tampering, an immediate security alert (`AUDIT_CHAIN_BROKEN_AT_RECORD_ID`) is fired.
* **Secondary WORM Archival:** Audit logs older than 90 days are mirrored asynchronously to an append-only S3 bucket with Object Lock (Compliance Mode) enabled.

---

## 6. Security Boundary & Access Scope (Batas Keamanan)
* **No PII Storage in Audit Logs:** To avoid conflict with GDPR/privacy laws (BP-08), audit logs store `actor_id UUID` and entity IDs, but NEVER store plain-text customer credit cards, phone numbers, or passwords.
* **Mandatory Justification Gate:** The application rejects any high-risk action (voids, discounts > 10%) at the API validation layer if the `reason` field is shorter than 15 characters.

---

## 7. Test Scenarios (Skenario Pengujian)

```gherkin
Feature: Immutable Audit Trail & Anti-Fraud

  Scenario: Operator Applies a Large Discount
    Given a cashier applies a 20% manual discount to Order "ORD-404"
    When the transaction commits
    Then a record is inserted into "system_audit_ledger" with "DISCOUNT_APPLIED"
    And the old price and discounted price are captured in JSONB
    And the record hash matches SHA256 calculation

  Scenario: Malicious Update Attempt on Historical Audit Row
    Given an existing record exists in "system_audit_ledger" with ID 105
    When a database user attempts to run "UPDATE system_audit_ledger SET new_state = '{}' WHERE id = 105"
    Then PostgreSQL aborts the transaction with exception "CRITICAL SECURITY VIOLATION"
    And the record remains completely unchanged

  Scenario: Attempted Deletion of Audit Trail
    Given an existing record exists in "system_audit_ledger" with ID 105
    When an admin user attempts to execute "DELETE FROM system_audit_ledger WHERE id = 105"
    Then PostgreSQL aborts the transaction with exception "CRITICAL SECURITY VIOLATION"
    And zero rows are deleted
```

---

## 8. Batasan Penerapan & Trade-offs (Kapan JANGAN Digunakan)
* **Contraindications:** Do not log routine low-risk read operations (e.g. `VIEW_PRODUCT_PAGE`, `SEARCH_QUERY`) into this table. That belongs in high-volume logging systems (Datadog/Elasticsearch). This ledger is strictly reserved for financial, security, and administrative state changes.
* **Storage Footprint:** At 50,000 transactions/month, audit tables generate ~250MB/year. Implement automated partitioning by month (`PARTITION BY RANGE (created_at)`) for high-volume enterprises.
