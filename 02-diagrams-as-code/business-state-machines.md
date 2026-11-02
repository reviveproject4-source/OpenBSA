# Business State Machine Diagrams (Mermaid.js)

> **Purpose:** Explicitly defines allowable state transitions, transition triggers, and terminal states for business objects to prevent illegal data mutations.

---

## 1. Transaction & Order Lifecycle State Machine

Defines how an order progresses from creation to settlement, refund, or cancellation.

```mermaid
stateDiagram-v2
    [*] --> DRAFT : Cashier creates cart

    DRAFT --> PENDING_PAYMENT : Checkout initiated
    DRAFT --> VOIDED : Cashier discards cart

    PENDING_PAYMENT --> PAID : Payment confirmed (Cash/Card/QRIS)
    PENDING_PAYMENT --> PAYMENT_FAILED : Card declined / Timeout
    PENDING_PAYMENT --> VOIDED : Cashier cancels before payment

    PAYMENT_FAILED --> PENDING_PAYMENT : Retry alternate payment method
    PAYMENT_FAILED --> VOIDED : Abandoned

    PAID --> PROCESSING : Fulfillment started
    PAID --> REFUNDED : Instant cashier reversal (Within 10m)

    PROCESSING --> COMPLETED : Delivered / Handed to customer
    PROCESSING --> PARTIALLY_REFUNDED : Item return / Adjustment
    PROCESSING --> REFUNDED : Total cancellation & return

    COMPLETED --> DISPUTED : Chargeback claim received
    COMPLETED --> PARTIALLY_REFUNDED : Post-delivery return

    DISPUTED --> COMPLETED : Dispute won
    DISPUTED --> REFUNDED : Dispute lost

    VOIDED --> [*]
    REFUNDED --> [*]
    PARTIALLY_REFUNDED --> [*]
    COMPLETED --> [*]
```

### Transition Guard Rules & Invariants
| Current State | Target State | Trigger Event | Guard Condition / Permission | Side Effect |
|---|---|---|---|---|
| `DRAFT` | `PENDING_PAYMENT` | Checkout click | Cart must have `>= 1` item and total `> 0` | Locks stock quantities |
| `PENDING_PAYMENT` | `PAID` | Payment gateway webhook | Verified payment amount matches total | Emits `order.paid` domain event |
| `PAID` | `REFUNDED` | Refund request | Requires `Owner` or `Supervisor` role PIN | Reverses stock decrement; ledger debit |
| `COMPLETED` | `DISPUTED` | Chargeback notice | Received within 90 days of order date | Freezes merchant escrow funds |

---

## 2. Customer Lifecycle & Retention State Machine

Models customer progression and dormancy feedback loops, enabling automated CRM follow-up triggers.

```mermaid
stateDiagram-v2
    [*] --> PROSPECT : Lead captured (Quote / Inquiry)

    PROSPECT --> FIRST_TIME_BUYER : First transaction completed
    PROSPECT --> LOST_LEAD : No purchase within 30 days

    FIRST_TIME_BUYER --> ACTIVE_REPEATER : 2nd purchase within 45 days
    FIRST_TIME_BUYER --> AT_RISK : No purchase for 45-60 days

    ACTIVE_REPEATER --> LOYAL_VIP : > 5 purchases AND spending > $1,000
    ACTIVE_REPEATER --> AT_RISK : Inactivity > 45 days

    LOYAL_VIP --> AT_RISK_VIP : Inactivity > 60 days
    LOYAL_VIP --> LOYAL_VIP : Ongoing repeat purchases

    AT_RISK --> DORMANT : Inactivity reaches 90 days
    AT_RISK --> ACTIVE_REPEATER : Purchase made

    AT_RISK_VIP --> DORMANT : Inactivity reaches 120 days
    AT_RISK_VIP --> LOYAL_VIP : Purchase made

    DORMANT --> RE_ENGAGED : Purchase triggered after win-back promo
    DORMANT --> CHURNED : Inactivity > 365 days

    RE_ENGAGED --> ACTIVE_REPEATER : Subsequent repeat purchase

    LOST_LEAD --> [*]
    CHURNED --> [*]
```

### Automated System Actions by State
* **When entering `AT_RISK`:** Queue automated personalized promotional notification with 10% discount voucher.
* **When entering `DORMANT`:** Flag in CRM dashboard for manual high-touch sales rep outreach.
* **When entering `RE_ENGAGED`:** Attribute marketing conversion to the specific reactivation campaign.
