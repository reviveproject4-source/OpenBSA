# Blueprint 14: Zero-Downtime Database Migration Protocol

> **Target Problem:** Your product is live with 100,000 active users. The developer deploys an update containing a database migration: `ALTER TABLE orders ADD COLUMN status VARCHAR(50) DEFAULT 'ACTIVE' NOT NULL;`. In PostgreSQL, on large tables, this locks the table for writes for 45 seconds. Active checkout requests back up, web workers run out of memory, and the entire platform crashes during business hours.

---

## 1. The Nightmare Scenario
A fast-growing B2B software company has 2 million rows in its `invoices` table. 
At 11:00 AM on a Tuesday, an engineer merges a pull request that runs:
```sql
-- DANGEROUS MIGRATION ON LIVE PRODUCTION
ALTER TABLE invoices ADD COLUMN currency_code VARCHAR(3) NOT NULL;
```
PostgreSQL takes an `ACCESS EXCLUSIVE` lock on the `invoices` table to validate the `NOT NULL` constraint across 2 million rows. 
Every API endpoint that touches invoices freezes. 
Customer web traffic piles up in the queue, consuming all web server RAM. 
The database CPU spikes to 100%. The company suffers a 35-minute unscheduled outage, and two major B2B clients threaten to cancel their contracts.

---

## 2. Architectural Blueprint: The Expand-and-Contract Migration Pattern

To achieve zero downtime, database schema changes must NEVER be shipped as a single monolithic migration. They must follow the **3-Phase Expand and Contract Pattern**:

```mermaid
graph TD
    classDef phase1 fill:#e1f5fe,stroke:#0288d1,stroke-width:2px;
    classDef phase2 fill:#ede7f6,stroke:#512da8,stroke-width:2px;
    classDef phase3 fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;

    subgraph Step 1: Expand (Zero Lock)
        M1[Deploy Migration:<br/>Add Column as NULLABLE without default lock]:::phase1
        M1 --> A1[Deploy Code v1.1:<br/>Write to BOTH old and new columns, Read from old column]:::phase1
    end

    subgraph Step 2: Backfill (Background Worker)
        B1[Run Background Script in batches of 1,000:<br/>Backfill historical rows in the background without table locks]:::phase2
    end

    subgraph Step 3: Contract (Cutover & Clean)
        A2[Deploy Code v1.2:<br/>Read and Write ONLY to new column]:::phase3
        A2 --> M2[Deploy Migration:<br/>Add NOT NULL constraint safely using NOT VALID then VALIDATE CONSTRAINT]:::phase3
        M2 --> M3[Drop old column safely after 14 days]:::phase3
    end
```

---

## 3. Safe vs Unsafe PostgreSQL Operations Cheat Sheet

| Operation | ❌ Dangerous Anti-Pattern (Locks Table) | ✅ Zero-Downtime Safe Pattern |
|---|---|---|
| **Add NOT NULL Column** | `ALTER TABLE t ADD COLUMN c TEXT NOT NULL;` | 1. Add column as nullable.<br/>2. Add constraint `NOT VALID`.<br/>3. Run `VALIDATE CONSTRAINT` asynchronously. |
| **Create Index** | `CREATE INDEX idx_name ON t (col);` | `CREATE INDEX CONCURRENTLY idx_name ON t (col);` (Builds index without write lock). |
| **Rename Column** | `ALTER TABLE t RENAME COLUMN a TO b;` | Expand & Contract: Add new column, dual-write in application, backfill, cutover. |
| **Drop Column** | `ALTER TABLE t DROP COLUMN c;` | 1. Remove column references from application code.<br/>2. Deploy code.<br/>3. Wait 24h.<br/>4. Drop column. |

---

## 4. Engineering Acceptance Criteria

```gherkin
Scenario: Developer submits PR modifying production database table
  Given a table "orders" contains > 100,000 rows
  When a developer opens a Pull Request with database migrations
  Then the CI/CD pipeline scans for forbidden table-locking statements
  And blocks any PR containing "CREATE INDEX" without the "CONCURRENTLY" keyword
  And blocks any PR containing "ADD COLUMN ... NOT NULL" without the multi-phase pattern
  And mandates that every migration file has a matching "down.sql" rollback script
```
