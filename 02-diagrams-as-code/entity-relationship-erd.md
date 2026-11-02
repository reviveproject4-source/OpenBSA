# Entity Relationship Diagram (ERD) & Schema Design

> **Standard:** Crow's Foot Notation modeled in Mermaid.js with multi-tenant row-level isolation invariants.

---

## 1. Multi-Tenant Enterprise Schema Model

```mermaid
erDiagram
    TENANTS ||--o{ USERS : "employs"
    TENANTS ||--o{ CUSTOMERS : "serves"
    TENANTS ||--o{ PRODUCTS : "stocks"
    TENANTS ||--o{ TRANSACTIONS : "processes"
    TENANTS ||--o{ OPERATIONAL_EXPENSES : "records"
    TENANTS ||--o{ CRM_LOGS : "tracks"

    CUSTOMERS ||--o{ TRANSACTIONS : "places"
    CUSTOMERS ||--o{ CRM_LOGS : "subject_of"

    USERS ||--o{ TRANSACTIONS : "operated_by"
    USERS ||--o{ CRM_LOGS : "performed_by"

    TRANSACTIONS ||--|{ TRANSACTION_ITEMS : "contains"
    PRODUCTS ||--o{ TRANSACTION_ITEMS : "fulfilled_by"

    TENANTS {
        uuid id PK
        string business_name
        string plan_tier
        string currency
        timestamp created_at
    }

    USERS {
        uuid id PK
        uuid tenant_id FK
        string email
        string full_name
        string role "OWNER | CASHIER | SUPERADMIN"
        boolean is_active
    }

    CUSTOMERS {
        uuid id PK
        uuid tenant_id FK
        string phone_number
        string customer_name
        decimal total_spent
        int total_orders
        string lifecycle_status "ACTIVE | DORMANT | VIP"
        timestamp last_order_at
    }

    PRODUCTS {
        uuid id PK
        uuid tenant_id FK
        string sku
        string name
        decimal cost_price
        decimal selling_price
        int stock_quantity
        int low_stock_threshold
    }

    TRANSACTIONS {
        uuid id PK
        uuid tenant_id FK
        uuid customer_id FK
        uuid user_id FK
        string invoice_number
        decimal subtotal
        decimal discount_amount
        decimal tax_amount
        decimal total_amount
        string payment_method "CASH | CARD | QRIS"
        string payment_status "PENDING | PAID | REFUNDED"
        timestamp transaction_at
    }

    TRANSACTION_ITEMS {
        uuid id PK
        uuid transaction_id FK
        uuid product_id FK
        int quantity
        decimal unit_price
        decimal cost_price_snapshot
        decimal line_total
    }

    CRM_LOGS {
        uuid id PK
        uuid tenant_id FK
        uuid customer_id FK
        uuid user_id FK
        string interaction_type "CALL | WHATSAPP | VISIT"
        string outcome "RE_ENGAGED | NO_ANSWER | DECLINED"
        timestamp scheduled_follow_up
    }

    OPERATIONAL_EXPENSES {
        uuid id PK
        uuid tenant_id FK
        string category "FIXED | VARIABLE"
        string description
        decimal amount
        date expense_date
    }
```

---

## 2. Key Data Architecture Principles

1. **Denormalized Snapshots for Auditing:**
   * In `TRANSACTION_ITEMS`, notice `cost_price_snapshot` and `unit_price`. This ensures that when a merchant alters product prices in the catalog tomorrow, historical financial reporting and profit-margin calculations remain permanently accurate.
2. **Tenant ID Foreign Key Invariant:**
   * Every single entity table contains a direct `tenant_id` foreign key referencing `tenants(id)`. This prevents expensive cascading multi-table joins when enforcing Row-Level Security (RLS) policies.
3. **Optimistic Locking via Version Columns:**
   * High-contention tables (like `PRODUCTS` stock quantities) include a `version integer DEFAULT 1` column to support optimistic concurrency control during high-volume sales.
