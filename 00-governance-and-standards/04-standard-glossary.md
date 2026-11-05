# 📖 04 — Standard B2E Glossary
> **Formal Codification of Business Systems Analysis & Architecture Terms in `system-blueprint-os`.**  
> *Status: RATIFIED & LOCKED.*

---

## 🎯 Purpose & Scope

This glossary establishes the unambiguous, authoritative definitions of technical, architectural, and business terms used throughout OpenBSA. 

In business-to-engineering collaboration, semantic ambiguity is a primary cause of scope failure. This document acts as the legal and architectural lexicon for all project deliverables.

---

## 🔤 Codified Technical & Domain Lexicon

### 1. Analysis Integrity Standard (AIS)
The foundational governance standard in OpenBSA requiring all business system analyses to satisfy four non-negotiable dimensions: (1) Mathematical & Financial Rigor, (2) Cross-Blueprint Consistency, (3) Empirical Reality Check, and (4) Requirement Integrity & Evidence Traceability.

### 2. Atomic Invariant
A non-negotiable system truth enforced at the database kernel level that cannot be broken even during server crashes, network drops, or extreme concurrency spikes (e.g., `available_qty >= 0` or `total = subtotal + tax - discount`).

### 3. Banker's Rounding (Half-Even Rounding)
An IEEE 754 standard rounding algorithm where numbers equidistant from two integers are rounded to the nearest *even* integer (e.g., $2.5 \to 2$, $3.5 \to 4$). Eliminates cumulative upward statistical drift across high-volume financial accounting ledgers.

### 4. Blast Radius
The maximum extent of damage, data corruption, financial liability, or downstream table pollution that occurs when a system failure is left unmitigated.

### 5. Circuit Breaker Pattern
A distributed systems stability pattern that monitors external vendor API calls. If failure rates exceed an established threshold (e.g. 50%), the breaker trips to the `OPEN` state, immediately failing fast in 0ms without waiting for timeouts, protecting web server threads from starvation. States: `CLOSED` (normal), `OPEN` (short-circuiting), `HALF-OPEN` (probing recovery).

### 6. Dead-Letter Queue (DLQ)
A specialized job queue or database table where poisoned, malformed, or repeatedly failed payloads are quarantined for human inspection and forensic analysis, preventing them from blocking main processing pipelines.

### 7. Definition of Done (DoD) — 4-Tier Standard
The contractual gate governing feature completeness. A feature is complete only when it satisfies:
* **Tier 1 (Functional):** BDD Given-When-Then acceptance criteria pass.
* **Tier 2 (Edge-Case):** Handles null states, timeouts, and negative inputs gracefully.
* **Tier 3 (Security):** RLS tenant isolation and least-privilege checks pass.
* **Tier 4 (Operational):** Database migrations run zero-downtime with automated rollback scripts.

### 8. Expand-and-Contract Migration Pattern
A zero-downtime database schema evolution methodology executed in three decoupled phases: (1) **Expand** (add new column as nullable, dual-write in application), (2) **Backfill** (populate historical rows via background worker without table locks), and (3) **Contract** (switch application reads to new column, enforce constraints asynchronously, drop old column).

### 9. Four-Eyes Principle (Two-Person Rule)
A security and governance control mandating that high-risk business actions (large discounts, transaction voids, bulk customer exports, debt write-offs) must be cryptographically signed by two distinct authorized human actors (`requester_id <> approver_id`).

### 10. Idempotency Key & Mutex
A unique identifier (such as a payment gateway event ID or UUID) attached to an API operation, combined with a distributed lock (mutex), guaranteeing that even if a network request is received multiple times, the underlying business mutation is executed exactly once.

### 11. Immutable Audit Trail (WORM Ledger)
A Write-Once-Read-Many database table that records all security, financial, and administrative state changes. Direct `UPDATE` or `DELETE` statements are strictly blocked by database kernel triggers, and records are linked using cryptographic SHA-256 hash chains.

### 12. Negative Stock Defense
An architectural constraint combining atomic SQL updates (`UPDATE ... WHERE available_qty >= 1 RETURNING`) with database check constraints (`CHECK (available_qty >= 0)`), mathematically eliminating overselling and race conditions during high-concurrency flash sales.

### 13. Pseudonymization (GDPR Article 17)
The processing of personal data in such a manner that the personal data can no longer be attributed to a specific data subject without the use of additional information. Distinct from naive deletion, pseudonymization scrambles PII (email, phone, name) while preserving statutory accounting records (invoice amounts, tax dates) for legal compliance.

### 14. Row-Level Security (RLS)
A PostgreSQL database kernel feature that evaluates security access policies on every individual row returned by any SQL query. Guarantees multi-tenant data isolation even if a developer forgets to append `WHERE tenant_id = ?` in backend application code.

### 15. Rules of Evidence
The OpenBSA protocol defining the four admissible classes of proof required to support system readiness claims (Class A: Live Production Telemetry, Class B: Integration Stress Benchmarks, Class C: Mathematical/Cryptographic Proofs, Class D: Statutory/Regulatory Citations).

### 16. Seven-Pillar Blueprint Standard (7PS)
The mandatory 8-section operational structure required for all OpenBSA architectural specifications: Assumptions, Prerequisites, Failure Scenario, Architecture/DDL, Recovery Strategy, Security Boundary, Test Scenarios (BDD), and Batasan Penerapan (Trade-offs).

### 17. SMS Toll Fraud (Artificially Inflated Traffic / AIT)
A cybercrime scheme where bot syndicates generate automated SMS verification requests through public web forms targeting high-rate international telecommunication numbers they control, splitting revenue with rogue carriers and billing thousands of dollars to the business owner.

### 18. Traceability Anchor
The verified origin point of an architectural decision, anchored to a concrete commercial problem, empirical operational metric, signed contract (ADR), or statutory law (e.g. IRS § 6001, GDPR Art. 17).

### 19. UUIDv7 (Time-Ordered Distributed Identifier)
A 128-bit universally unique identifier standard that embeds a millisecond-precision Unix timestamp in its most significant bits. Enables distributed offline terminals (tablets, mobile POS) to generate globally unique, chronologically sortable primary keys without central database coordination.
