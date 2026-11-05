# 🏛️ 02 — Seven-Pillar Blueprint Standard (7PS)
> **The 8 Mandatory Operational Sections for All Architectural Blueprints.**  
> *Status: RATIFIED & LOCKED.*

---

## 🎯 Purpose & Scope

The **Seven-Pillar Blueprint Standard (7PS)** establishes the structural and operational anatomy required for every technical specification in `system-blueprint-os`. 

A blueprint is NOT a high-level conceptual overview; it is an **executable operational specification** that provides complete defensive controls from failure detection to self-healing recovery.

---

## 📑 The 8 Operational Sections (Detailed Standards)

### Pillar 1: Assumptions (Asumsi)
* **Definition:** The baseline conditions of the business model, data scale, and physical environment that must hold true for the blueprint to be valid.
* **Mandatory Contents:**
  * Business operational model (e.g. single-tenant vs multi-tenant, online-only vs omni-channel retail).
  * Data scale baselines (e.g. up to 500 concurrent writes/second per SKU).
  * Infrastructure guarantees (e.g. PostgreSQL ACID compliance, Redis cluster availability).

### Pillar 2: Prerequisites (Prasyarat)
* **Definition:** The technical tools, engine versions, external APIs, and organizational agreements that must exist prior to implementation.
* **Mandatory Contents:**
  * Minimum database version (e.g. PostgreSQL 14+ for atomic RETURNING locks).
  * Supporting middleware (e.g. Redis 6.2+ for atomic distributed locks).
  * Pre-configured vendor credentials (e.g. Stripe webhook secret, Turnstile secret key).
  * Formal organizational approvals (e.g. management sign-off on refund escrow windows).

### Pillar 3: Failure Scenario & Blast Radius (Skenario Kegagalan)
* **Definition:** The concrete narrative detailing the catastrophic breakdown that occurs when this blueprint is omitted.
* **Mandatory Contents:**
  * Chronological failure trigger (e.g. "Network timeout during Black Friday surge causes 4 duplicate webhook retries").
  * Quantified direct financial loss ($) or fraud liability.
  * Blast radius: The specific database tables, services, or downstream customer records corrupted.

### Pillar 4: Architecture & Executable DDL (Spesifikasi Arsitektur)
* **Definition:** The formal engineering solution combining visual process diagrams and executable database definitions.
* **Mandatory Contents:**
  * Native Mermaid.js diagrams (Sequence diagrams, state machines, or C4 container graphs).
  * Executable SQL DDL: Table schemas, composite primary keys, `CHECK` constraints, `UNIQUE` compound constraints, PostgreSQL Row-Level Security (RLS) policies, and PL/pgSQL triggers.
  * Code snippets for atomic queries (e.g. `UPDATE ... WHERE available_qty >= 1 RETURNING`).

### Pillar 5: Recovery Strategy & Self-Healing (Strategi Pemulihan)
* **Definition:** The mechanisms through which the system automatically detects, isolates, and recovers from anomalies without human panic.
* **Mandatory Contents:**
  * Automated self-healing workers (e.g. nightly reconciliation cron jobs, exponential backoff retries with jitter).
  * Dead-Letter Queues (DLQ) and quarantine buckets for malformed or poisoned payloads.
  * Operational Runbook: Step-by-step Standard Operating Procedures (SOP) for customer support when automated self-healing requires manual escalation.

### Pillar 6: Security Boundary & Access Scope (Batas Keamanan)
* **Definition:** The principle of least privilege, data isolation boundaries, and cryptographic tamper-prevention rules.
* **Mandatory Contents:**
  * Application role permissions (e.g. runtime web workers have only `SELECT/UPDATE`, zero DDL or `DROP` rights).
  * Tenant isolation guarantees (RLS kernel policies enforcing `tenant_id` session variables).
  * Non-repudiation controls: Cryptographic HMAC signature verification, SHA-256 hash chaining, WORM trigger locks.

### Pillar 7: Test Scenarios (Skenario Pengujian BDD)
* **Definition:** Executable acceptance criteria formatted in Gherkin BDD (`Given-When-Then`) for automated QA verification.
* **Mandatory Contents:**
  * Happy Path Scenario: Standard ideal business flow.
  * Negative Edge-Case Scenario: How the system detects and rejects bad inputs, timeouts, and corrupted rows.
  * Concurrency / Stress Scenario: What happens when 50 requests hit the exact same resource in the same millisecond.

### Pillar 8: Batasan Penerapan & Trade-offs (Kapan JANGAN Digunakan)
* **Definition:** Honest architectural boundaries identifying where the pattern is overkill, contraindicated, or carries unacceptable complexity.
* **Mandatory Contents:**
  * Concrete contraindications (e.g. "Do not implement for digital goods with infinite license inventory").
  * Performance latency overhead (e.g. "Distributed locking adds 2–6ms per webhook call").
  * Operational maintenance burden (e.g. "Requires monitoring Redis memory utilization and TTL expirations").

---

## 🔒 The 7PS Structural Rule

No blueprint may omit any of the 8 sections above. If a section is deemed non-applicable, the author must explicitly write:  
`"N/A: [Justification why this operational boundary does not apply to this domain]"`  
Blank or placeholder headings immediately fail the Tier 2 Governance Gate.
