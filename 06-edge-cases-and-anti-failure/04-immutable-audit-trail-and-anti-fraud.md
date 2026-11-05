# Blueprint 04: Immutable Audit Trail & Anti-Fraud Log

> **Target Problem:** A store cashier voids a $200 cash sale after the customer walks out, pocketing the $200 cash and adjusting inventory to "damaged goods". A disgruntled employee deletes order records before quitting. Without an immutable append-only audit trail, the business owner loses money without any legal proof of theft.

---

## 1. The Nightmare Scenario
A retail multi-outlet business owner notices a $4,500 cash shortage at the end of the month. 
When they check the database, several cash sales from the past 3 weeks are simply missing or modified to $0. 
The database administrator says: *"Someone ran an `UPDATE` or `DELETE` query with manager credentials. We have no record of who did it, what the original price was, or what IP address it came from."*
The police cannot take action because there is zero forensic chain of custody.

---

## 2. Architectural Blueprint: Append-Only Immutable Ledger (WORM)

In financial and inventory systems, **records are never deleted or mutated in-place**. Every change is recorded as an immutable new event with cryptographic checksum verification.

```mermaid
graph LR
    classDef client fill:#e1f5fe,stroke:#0288d1,stroke-width:2px;
    classDef action fill:#fff3e0,stroke:#f57c00,stroke-width:2px;
    classDef ledger fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef blocked fill:#ffebee,stroke:#c62828,stroke-width:2px;

    User[Cashier / Operator]:::client -->|Initiates Void / Discount / Refund| Action[Business Event Trigger]:::action
    Action --> Write[Write Immutable Audit Entry]:::ledger
    
    subgraph Database Kernel Triggers
        Write --> Hash[Compute SHA-256 Checksum<br/><i>Hash(PrevHash + RecordData)</i>]:::ledger
        Hash --> Ledger[(audit_trail Table)]:::ledger
        
        Ledger -.->|Attempt UPDATE or DELETE| Guard{SQL Trigger / Rule}:::blocked
        Guard -->|BLOCKED| Error[RAISE EXCEPTION:<br/>'Audit trail is immutable!']:::blocked
    end
```

---

## 3. Database Specification: The Cryptographically Sealed Ledger

```sql
-- 1. Create the immutable audit log table
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

-- 2. HARD SECURITY RULE: Prevent ANY UPDATE or DELETE on this table
CREATE OR REPLACE FUNCTION prevent_audit_tampering()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'CRITICAL SECURITY ALERT: Records in system_audit_ledger are immutable and cannot be updated or deleted!';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_immutable_audit
    BEFORE UPDATE OR DELETE ON system_audit_ledger
    FOR EACH ROW
    EXECUTE FUNCTION prevent_audit_tampering();
```

---

## 4. Business Rules: High-Risk Action Guardrails

1. **Mandatory Reason Field:**
   Any void, manual discount > 10%, or price override must prompt a mandatory input modal. The system rejects the API call if `reason.length < 15 characters`.
2. **Four-Eyes Trigger:**
   If a void exceeds $100, the POS application must lock until a Manager swipes their RFID card or enters a 2FA OTP pin.
3. **Automated Flagging Report:**
   A weekly automated email is dispatched to the Business Owner highlighting:
   * Top 3 employees with the highest ratio of voided transactions.
   * Any transactions modified outside normal store operating hours (e.g. 11:30 PM).
