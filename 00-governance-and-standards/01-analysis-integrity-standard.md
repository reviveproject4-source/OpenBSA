# 📐 01 — Analysis Integrity Standard (AIS)
> **The 4 Invariant Dimensions of Business Systems Analysis in `system-blueprint-os`.**  
> *Status: RATIFIED & LOCKED.*

---

## 🎯 Purpose & Scope

The **Analysis Integrity Standard (AIS)** defines the non-negotiable criteria that any business system analysis must satisfy *before* technical engineering or coding begins. 

A specification that lacks analysis integrity produces software with silent financial leaks, regulatory violations, and architectural deadlock.

---

## 🏛️ Dimension 1: Mathematical & Financial Rigor

Every quantitative calculation involving money, inventory, tax, interest, or discounts must adhere to formal mathematical proofs.

### 1. The Integer Cent Storage Invariant
* **Strict Prohibition:** The use of binary floating-point types (`FLOAT`, `DOUBLE`, `REAL`, `FLOAT4`, `FLOAT8`) is strictly prohibited for monetary amounts in database schemas and application models.
* **The Atomic Storage Rule:** All currency amounts must be represented as `BIGINT` integers in the currency's lowest atomic divisible unit (e.g., cents for USD/EUR, satuan for IDR, yen for JPY).
  $$\text{StorageValue} = \text{Round}(\text{MonetaryValue} \times 10^{\text{precision}})$$
* **Zero Floating-Point Drift:** The database engine must enforce ledger integrity via declarative SQL constraints:
  ```sql
  CONSTRAINT chk_ledger_math_integrity CHECK (
      total_atomic_units = (subtotal_atomic_units + tax_atomic_units - discount_atomic_units)
  )
  ```

### 2. Standardized Rounding Mode
* **Banker's Rounding (Half-Even):** When dividing currencies (tax percentages, discounts, unit prices), applications must use IEEE 754 Half-Even Rounding (round to the nearest even number when equidistant) to eliminate cumulative statistical bias across high transaction volumes.
* **Order-Level Tax Calculation:** Tax must be computed on the taxable order subtotal, not rounded line-item by line-item, preventing fractional penny drift.

---

## 🏛️ Dimension 2: Cross-Blueprint Traceability & Consistency

A system is an interconnected web of state machines. An architectural decision in one domain must never violate an invariant in another domain.

### 1. Invariant Preservation Rules
* **Privacy vs Financial Audit (BP-08 vs BP-04/07):**
  * *Rule:* GDPR Right to Erasure procedures must NEVER perform cascading physical deletes (`DELETE FROM users CASCADE`).
  * *Verification:* The procedure must use **Irreversible Pseudonymization** on personal profiles while leaving invoice IDs, tax amounts, line items, and append-only audit hashes intact under statutory legal exemptions (GDPR Art. 17(3)(b) & IRS § 6001).
* **Online Concurrency vs Offline Delta Sync (BP-02 vs BP-09):**
  * *Rule:* Offline sales syncing after an internet outage must not overwrite online inventory locks.
  * *Verification:* Sync logic must apply **atomic delta deductions** (`available_qty = available_qty - :qty_sold`), with excess sales flagged as `FLAGGED_STOCK_ANOMALY` rather than throwing uncaught constraint exceptions that abort the sync queue.

### 2. Cross-Blueprint Compatibility Matrix
Every new blueprint must pass a conflict audit against all existing blueprints across all 5 architectural layers before merge.

---

## 🏛️ Dimension 3: Empirical Reality Check

Specifications must reflect the messy, chaotic reality of physical business operations and cloud infrastructure—not a sanitized, ideal world.

### 1. Required Failure Modeling
Every blueprint must explicitly specify behavior during:
* **Network Partition & Drop:** Webhook retry storms (BP-01), severed store fiber cables (BP-09).
* **Malicious Insider Threat:** Cashier pocketing cash via fake voids (BP-04), supervisor retaliatory bulk discounts or exfiltration (BP-10).
* **Third-Party API Degradation:** WhatsApp/OpenAI API hanging for 45s (BP-12), SMS Toll Fraud botnet attacks (BP-13).
* **Production Scale Bottlenecks:** Table-locking database migrations under active user load (BP-14).

### 2. Worst-Case Blast Radius Metric
For every identified failure mode, the analysis must calculate:
1. **Direct Financial Loss ($):** Fraud potential, chargeback penalties, or lost walkout sales.
2. **Data Corruption Scope:** Which tables, foreign keys, or downstream accounting systems are poisoned if the failure is unmitigated.

---

## 🏛️ Dimension 4: Requirement Integrity & Evidence Traceability

No technical constraint, table column, or security check may exist purely because of a developer's aesthetic preference. Every architectural decision must be bidirectionally traceable.

### 1. The Bidirectional Traceability Chain

$$\text{Business Problem / Legal Statute} \longleftrightarrow \text{System Requirement (PRD)} \longleftrightarrow \text{Architectural DDL / Constraint} \longleftrightarrow \text{Automated BDD Test}$$

### 2. Mandatory Traceability Anchor Sources
Every blueprint must explicitly cite at least one verified anchor:
* **Commercial Precedent / Operational Metric:** Documented operational leakage (e.g. "Cashier voids accounted for 4.2% unaccounted shrinkage").
* **Statutory Law / Industry Mandate:** Legal obligation (e.g., GDPR Article 17, IRS Code § 6001, PCI-DSS v4.0 Requirement 10.2).
* **Architectural Decision Record (ADR):** Signed technical contract approving specific infrastructure choices.

---

## 📋 The AIS Verification Checklist (Mandatory Sign-off)

Before any blueprint is eligible for `Level 2: SPEC_COMPLETE` maturity status, it must achieve 100% sign-off on this checklist:

```markdown
- [ ] AIS-1: All monetary fields are integer atomic cents; Banker's Rounding verified.
- [ ] AIS-2: Cross-blueprint audit confirms zero invariant collisions with BP-04, BP-07, BP-08, BP-09.
- [ ] AIS-3: Failure scenario models empirical disaster (network timeout, employee theft, vendor outage).
- [ ] AIS-4: Every database constraint and security policy anchors to an explicit PRD requirement or legal statute.
```
