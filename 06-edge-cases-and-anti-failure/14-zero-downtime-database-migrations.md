# Blueprint 14: Zero-Downtime Database Migration Protocol

> **Target Problem:** Your product is live with 150,000 active users. An engineer merges a migration script: `ALTER TABLE orders ADD COLUMN status VARCHAR(50) DEFAULT 'ACTIVE' NOT NULL;`. In PostgreSQL, on large tables, this takes an exclusive table lock. Active customer checkout requests pile up, server connection pools exhaust, and the platform suffers an unscheduled 35-minute outage during business hours.

---

## 1. Assumptions (Asumsi)
* **High-Concurrency Live Production:** The database is constantly serving active read and write transactions 24/7 with zero maintenance windows permitted.
* **PostgreSQL Lock Hierarchy Reality:** Statements like `ALTER TABLE`, `ADD COLUMN ... NOT NULL`, and `CREATE INDEX` acquire `ACCESS EXCLUSIVE` locks that block all concurrent reads and writes.
* **Backward Compatibility Requirement:** Database schema changes must be compatible with both the currently running application code (v1.0) and the incoming deployment (v1.1).

---

## 2. Prerequisites (Prasyarat)
* **PostgreSQL 12+:** Supporting `CONCURRENTLY` index creation and multi-phase constraint validation (`NOT VALID` followed by `VALIDATE CONSTRAINT`).
* **CI/CD Pipeline Linter:** Pre-commit or pull request linters (e.g., `strong_migrations` or `squawk`) that flag unsafe DDL operations before merging.

---

## 3. Failure Scenario & Blast Radius (Skenario Kegagalan)
* **The Failure Story:** A fast-growing B2B software company has 3 million rows in its `invoices` table. An engineer merges a pull request adding a new column: `ALTER TABLE invoices ADD COLUMN currency_code VARCHAR(3) NOT NULL;`. PostgreSQL locks the entire table to validate the constraint across 3 million rows. Every incoming API request attempting to query or update invoices hangs. Web server RAM spikes to 100%, and the system crashes for 35 minutes during Tuesday morning peak hours.
* **Financial Impact:** $22,000 in SLA breach penalty credits refunded to enterprise clients, plus customer support overtime.
* **Blast Radius:** Total application outage, API timeouts, dropped shopping carts, and executive panic.

---

## 4. Architectural Blueprint: The Expand-and-Contract Migration Pattern

```mermaid
graph TD
    classDef phase1 fill:#e1f5fe,stroke:#0288d1,stroke-width:2px;
    classDef phase2 fill:#ede7f6,stroke:#512da8,stroke-width:2px;
    classDef phase3 fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;

    subgraph Step 1: Expand (Zero Lock Impact)
        M1[Deploy Migration 1:<br/>Add Column as NULLABLE without table lock]:::phase1
        M1 --> A1[Deploy Code v1.1:<br/>Dual-Write to BOTH old and new columns, Read from old column]:::phase1
    end

    subgraph Step 2: Backfill (Background Worker)
        B1[Run Background Script in batches of 1,000:<br/>Backfill historical rows gradually without taking write locks]:::phase2
    end

    subgraph Step 3: Contract (Cutover & Clean)
        A2[Deploy Code v1.2:<br/>Read and Write ONLY to new column]:::phase3
        A2 --> M2[Deploy Migration 2:<br/>Enforce NOT NULL using NOT VALID then VALIDATE CONSTRAINT]:::phase3
        M2 --> M3[Drop old column safely after 14 days]:::phase3
    end
```

---

## 5. Safe vs Unsafe PostgreSQL Operations Reference

```sql
-- ❌ DANGEROUS MONOLITHIC MIGRATION (TAKES EXCLUSIVE WRITE LOCK)
ALTER TABLE invoices ADD COLUMN status VARCHAR(50) DEFAULT 'ACTIVE' NOT NULL;
CREATE INDEX idx_invoices_user ON invoices(user_id);

-- ✅ SAFE ZERO-DOWNTIME EQUIVALENT (3-PHASE PROTOCOL)

-- Phase 1: Add column as NULLABLE (Instant metadata-only change in Postgres 11+)
ALTER TABLE invoices ADD COLUMN status VARCHAR(50);

-- Phase 2: Create index CONCURRENTLY (Does NOT block concurrent writes)
CREATE INDEX CONCURRENTLY idx_invoices_user ON invoices(user_id);

-- Phase 3: Add constraint without table scan validation
ALTER TABLE invoices ADD CONSTRAINT chk_status_not_null CHECK (status IS NOT NULL) NOT VALID;

-- Phase 4: Validate constraint asynchronously (Takes only SHARE UPDATE EXCLUSIVE lock)
ALTER TABLE invoices VALIDATE CONSTRAINT chk_status_not_null;
```

---

## 6. Recovery Strategy & Rollback Runbook (Strategi Pemulihan)
* **The "Down Migration" Requirement:** Every migration file (`up.sql`) MUST be accompanied by an automated, tested `down.sql` rollback script.
* **Deadlock Auto-Abort (Lock Timeout):**
  All production migration sessions MUST execute a strict 5-second lock timeout before running DDL:
  ```sql
  SET lock_timeout = '5s';
  -- If table lock cannot be acquired within 5s, Postgres aborts rather than queueing requests
  ```

---

## 7. Security Boundary & Access Scope (Batas Keamanan)
* **DBA Role Isolation:** Application web servers connect using the `app_runtime` role, which has zero `ALTER TABLE`, `DROP TABLE`, or `CREATE TABLE` permissions. Only automated CI/CD deployment pipelines possess DDL migration privileges.

---

## 8. Test Scenarios (Skenario Pengujian)

```gherkin
Feature: Zero-Downtime Database Migration Protocol

  Scenario: Adding Column to High-Traffic Production Table
    Given table "orders" contains 2,000,000 rows
    And active user traffic is executing 300 write queries per second
    When the zero-downtime migration script executes with "lock_timeout = '5s'"
    Then the new column is created without blocking active write transactions
    And zero API requests experience 504 Gateway Timeouts
    And the application v1.0 continues functioning normally

  Scenario: CI/CD Pipeline Blocks Dangerous Table-Locking PR
    Given a developer submits a PR containing "CREATE INDEX" without "CONCURRENTLY"
    When the CI pipeline executes automated migration linting
    Then the build fails with an alert: "DANGEROUS_MIGRATION_DETECTED"
    And merging to the "main" branch is blocked until corrected
```

---

## 9. Batasan Penerapan & Trade-offs (Kapan JANGAN Digunakan)
* **Contraindications:** Do not mandate 3-phase Expand-and-Contract patterns during early greenfield prototyping when the database has 0 production users. A direct `ALTER TABLE` is faster before initial public launch.
* **Deployment Cadence Overhead:** Requires 2 or 3 separate phased deployments over 1–2 days instead of a single rapid deploy.
