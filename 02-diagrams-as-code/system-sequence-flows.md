# System Sequence Flow Patterns (Mermaid.js)

> **Purpose:** Reusable, enterprise-grade sequence flows covering the most critical technical interactions in modern SaaS and distributed architectures.

---

## 1. Idempotent Transaction Submission with Distributed Lock

Guarantees that network retries or double-clicks by a cashier never result in duplicate orders or double-billing.

```mermaid
sequenceDiagram
    autonumber
    actor Cashier as Cashier Terminal
    participant Gateway as API Gateway
    participant LockManager as Redis Lock & Idempotency
    participant TxEngine as Transaction Service
    participant DB as PostgreSQL (RLS)
    participant Broker as Domain Event Stream

    Cashier->>Gateway: POST /v1/transactions<br/>Header: Idempotency-Key: `idem_8f9a2b`<br/>Payload: {items, total, payment}
    
    Gateway->>LockManager: SETNX lock:idem_8f9a2b (TTL 30s)
    alt Lock Acquisition Failed (Duplicate in-flight request)
        LockManager-->>Gateway: Lock already held
        Gateway-->>Cashier: HTTP 409 Conflict ("Request currently in progress")
    else Lock Acquired Successfully
        LockManager-->>Gateway: Lock granted
        Gateway->>TxEngine: Process Transaction Request
        
        TxEngine->>DB: BEGIN TRANSACTION (ISOLATION LEVEL READ COMMITTED)
        TxEngine->>DB: SELECT stock FROM products WHERE id IN (...) FOR UPDATE
        
        alt Insufficient Stock Available
            DB-->>TxEngine: Stock deficit detected
            TxEngine->>DB: ROLLBACK
            Gateway->>LockManager: DEL lock:idem_8f9a2b
            Gateway-->>Cashier: HTTP 422 Unprocessable ("Insufficient stock for SKU-102")
        else Stock Validated
            TxEngine->>DB: UPDATE products SET stock = stock - qty
            TxEngine->>DB: INSERT INTO transactions (...) RETURNING id
            TxEngine->>DB: INSERT INTO transaction_items (...)
            TxEngine->>DB: COMMIT TRANSACTION
            
            TxEngine->>Broker: Publish `order.placed` {tx_id, customer_id, total}
            TxEngine-->>Gateway: Transaction Successful (TxID: 44012)
            
            Gateway->>LockManager: SET result:idem_8f9a2b = ResponseBody (TTL 24h)
            Gateway->>LockManager: DEL lock:idem_8f9a2b
            Gateway-->>Cashier: HTTP 201 Created {status: "COMPLETED", invoice_no: "INV-2026-001"}
        end
    end
```

---

## 2. Secure Webhook Ingestion with HMAC Verification & Dead-Letter Queue (DLQ)

Pattern for receiving external asynchronous notifications (e.g., Stripe, WhatsApp, Payment Gateways) with replay attack protection.

```mermaid
sequenceDiagram
    autonumber
    participant Provider as External Provider (e.g. Stripe)
    participant Edge as Edge Webhook Ingress
    participant SecretVault as Key Management (Vault)
    participant Queue as High-Priority Event Buffer
    participant Consumer as Webhook Background Worker
    participant DLQ as Dead-Letter Queue

    Provider->>Edge: POST /webhooks/payments<br/>Header: X-Signature-256: `t=1700000000,v1=abc...`<br/>Payload: JSON event
    
    Edge->>Edge: Parse timestamp `t` (Validate timestamp < 300s old to prevent replay)
    Edge->>SecretVault: Fetch Webhook Signing Secret
    SecretVault-->>Edge: `whsec_live_9921...`
    Edge->>Edge: Compute HMAC-SHA256(timestamp + "." + payload, secret)
    
    alt Signature Mismatch
        Edge-->>Provider: HTTP 401 Unauthorized (Drop invalid payload)
    else Signature Valid
        Edge->>Queue: Push raw event to buffer (Fast ACK)
        Edge-->>Provider: HTTP 200 OK (Acknowledged)
        
        Queue->>Consumer: Consume event for processing
        alt Processing Succeeds
            Consumer->>Consumer: Update Transaction Status to "PAID"
            Consumer->>Queue: ACK Message
        else Retriable Failure (Database lock/timeout)
            Consumer->>Queue: NACK with Retry Delay (Attempt 1 of 3)
        else Unrecoverable Failure (Invalid internal state after 3 retries)
            Consumer->>DLQ: Route to Dead-Letter Queue (Alert DevOps on PagerDuty)
            Consumer->>Queue: ACK original queue to prevent head-of-line blocking
        end
    end
```

---

## 3. OAuth2 PKCE Authentication & Rotating Token Flow

Secure authentication flow for Single Page Applications (Next.js / React) and mobile apps without exposing client secrets.

```mermaid
sequenceDiagram
    autonumber
    actor User as Store Operator
    participant Client as Next.js SPA
    participant AuthServer as Authorization Server (Auth0 / Supabase)
    participant APIGateway as Protected API Gateway

    User->>Client: Click "Sign In with Work Email"
    Client->>Client: Generate `code_verifier` & compute `code_challenge = SHA256(code_verifier)`
    Client->>AuthServer: GET /authorize?response_type=code&code_challenge=xyz&code_challenge_method=S256
    
    AuthServer-->>User: Display Login & MFA Challenge
    User->>AuthServer: Enter Credentials & OTP Code
    AuthServer-->>Client: Redirect to callback URL with `?code=AUTH_CODE_123`
    
    Client->>AuthServer: POST /oauth/token {code: AUTH_CODE_123, code_verifier: VERIFIER_SECRET}
    AuthServer->>AuthServer: Validate `SHA256(code_verifier) == code_challenge`
    AuthServer-->>Client: Return {access_token (JWT, exp: 15m), refresh_token (exp: 30d)}
    
    Note over Client,APIGateway: Accessing Protected Resources
    Client->>APIGateway: GET /api/v1/store/metrics<br/>Header: Authorization: Bearer <access_token>
    APIGateway->>APIGateway: Verify RS256 Signature using cached Auth Public Key
    APIGateway-->>Client: HTTP 200 OK (Protected Business Data)
```
