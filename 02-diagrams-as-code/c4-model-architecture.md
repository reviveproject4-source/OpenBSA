# C4 Model Architecture Library (Mermaid.js)

> **Standard:** The C4 Model by Simon Brown (Context, Containers, Components, Code) rendered via native GitHub Markdown Mermaid syntax.  
> **How to Use:** Copy the Mermaid code blocks below and paste them directly into your GitHub Markdown files, Notion pages, or PRDs.

---

## 1. C4 Level 1: System Context Diagram

The **System Context** diagram shows the high-level picture: how your software system fits into the environment with its human users and external systems.

```mermaid
graph TB
    classDef person fill:#08427b,stroke:#073b6f,color:#fff;
    classDef system fill:#1168bd,stroke:#0b4884,color:#fff;
    classDef external fill:#999999,stroke:#666666,color:#fff;

    Customer[Customer / Shopper<br/><i>[Person]</i>]:::person
    Cashier[Cashier / Store Staff<br/><i>[Person]</i>]:::person
    Owner[Business Owner / Tenant Admin<br/><i>[Person]</i>]:::person

    MainSystem[Retail Management & CRM System<br/><i>[Software System]</i><br/>Enables multi-tenant store operations, POS transactions, inventory, and customer retention.]:::system

    PaymentGateway[Payment Gateway Service<br/><i>[External System: Stripe / Midtrans]</i><br/>Processes card, QRIS, and bank transfers.]:::external
    WhatsAppAPI[WhatsApp Business API<br/><i>[External System: Meta Cloud]</i><br/>Dispatches transaction receipts and CRM notifications.]:::external
    AccountingSync[External Accounting System<br/><i>[External System: Xero / QuickBooks]</i><br/>Synchronizes financial ledgers.]:::external

    Customer -->|Browses catalog & pays via QR| MainSystem
    Cashier -->|Inputs orders & manages cash register| MainSystem
    Owner -->|Views sales reports & configures promos| MainSystem

    MainSystem -->|Authorizes payments| PaymentGateway
    MainSystem -->|Sends receipts & follow-up messages| WhatsAppAPI
    MainSystem -->|Pushes daily ledger entries| AccountingSync
```

---

## 2. C4 Level 2: Container Diagram

The **Container** diagram decomposes the system into executable applications, data stores, and message brokers.

```mermaid
graph TB
    classDef user fill:#08427b,stroke:#073b6f,color:#fff;
    classDef app fill:#1168bd,stroke:#0b4884,color:#fff;
    classDef db fill:#2b78e4,stroke:#0b4884,color:#fff;
    classDef queue fill:#e67e22,stroke:#d35400,color:#fff;
    classDef ext fill:#888888,stroke:#555555,color:#fff;

    Staff[Store Staff / Owner]:::user

    subgraph System Boundary: Retail SaaS Platform
        WebSPA[Single Page App / POS<br/><i>[Next.js, TypeScript, Tailwind]</i><br/>Provides UI for order taking, CRM, and catalog management.]:::app
        APIGateway[API Gateway & Router<br/><i>[Node.js / Express or Go]</i><br/>Enforces JWT validation, rate limiting, and route proxying.]:::app
        TxEngine[Transaction & Inventory Service<br/><i>[Container: REST / gRPC]</i><br/>Handles atomic order placement and stock decrementing.]:::app
        CRMWorker[CRM & Retention Worker<br/><i>[Container: Node.js Background Service]</i><br/>Processes asynchronous customer dormancy and follow-ups.]:::app
        
        PrimaryDB[(Primary Relational Database<br/><i>[PostgreSQL + Supabase RLS]</i><br/>Stores multi-tenant orders, customers, and accounts.)]:::db
        RedisCache[(Distributed Cache & Sessions<br/><i>[Redis 7]</i><br/>Idempotency tokens, session tokens, and catalog cache.)]:::db
        EventBus[(Message Broker / Stream<br/><i>[RabbitMQ / Redis Stream]</i><br/>Pub/Sub queue for decoupled domain events.)]:::queue
    end

    Stripe[Stripe API]:::ext

    Staff -->|HTTPS| WebSPA
    WebSPA -->|JSON / HTTPS| APIGateway
    APIGateway -->|Route & Authorize| TxEngine
    TxEngine -->|Read & Write| PrimaryDB
    TxEngine -->|Verify Idempotency| RedisCache
    TxEngine -->|Publish Domain Events| EventBus
    EventBus -->|Consume `order.completed`| CRMWorker
    CRMWorker -->|Update Customer RFM| PrimaryDB
    TxEngine -->|Process Card Payment| Stripe
```

---

## 3. C4 Level 3: Component Diagram (Core Transaction Service)

The **Component** diagram zooms inside a single container (the Transaction Engine) to show its internal software components.

```mermaid
graph TB
    classDef component fill:#1168bd,stroke:#0b4884,color:#fff;
    classDef repository fill:#2b78e4,stroke:#0b4884,color:#fff;
    classDef ext fill:#7f8c8d,stroke:#34495e,color:#fff;

    APIClient[API Gateway Ingress]:::ext

    subgraph Transaction Engine Container
        TxController[Transaction Controller<br/><i>[Spring Boot / Express Route]</i><br/>Validates payload schema and parses tenant claims.]:::component
        IdempotencyGuard[Idempotency Interceptor<br/><i>[Middleware]</i><br/>Guards against double-charging duplicate requests.]:::component
        OrderService[Order Orchestration Service<br/><i>[Domain Logic]</i><br/>Coordinates validation, pricing, and stock reservation.]:::component
        StockManager[Inventory Allocation Component<br/><i>[Domain Logic]</i><br/>Performs optimistic lock stock checks and decrements.]:::component
        LedgerManager[Financial Ledger Writer<br/><i>[Domain Logic]</i><br/>Creates immutable double-entry ledger line items.]:::component
        
        TxRepository[Transaction Data Access Repository<br/><i>[Data Access Layer]</i><br/>Executes SQL queries scoped to current tenant_id.]:::repository
        EventPublisher[Domain Event Publisher<br/><i>[Integration Component]</i><br/>Serializes events and pushes to Message Broker.]:::component
    end

    Database[(PostgreSQL DB)]:::ext
    Broker[(Message Broker)]:::ext

    APIClient --> TxController
    TxController --> IdempotencyGuard
    IdempotencyGuard --> OrderService
    OrderService --> StockManager
    OrderService --> LedgerManager
    StockManager --> TxRepository
    LedgerManager --> TxRepository
    TxRepository --> Database
    OrderService --> EventPublisher
    EventPublisher --> Broker
```
