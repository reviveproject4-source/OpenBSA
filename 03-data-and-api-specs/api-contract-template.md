# API Functional Contract Specification Template

> **Protocol:** RESTful over HTTPS / TLS 1.3  
> **Content-Type:** `application/json`  
> **Standard:** OpenAPI 3.1 compatible  
> **Author:** [Tri Raida / Author Name]

---

## 1. Global Standards & Conventions

### 1.1 Authentication & Header Invariants
All protected endpoints require the following request headers:

```http
Authorization: Bearer <JWT_ACCESS_TOKEN>
X-Tenant-ID: <UUID_V4>
X-Request-ID: <UUID_V4>
Content-Type: application/json
Accept: application/json
```

For state-mutating requests (`POST`, `PUT`, `PATCH`), the client must provide an **Idempotency Key**:
```http
Idempotency-Key: <UNIQUE_UUID_OR_HASH>
```

### 1.2 Canonical Error Envelope
All error responses (`4xx` and `5xx`) adhere to the RFC 7807 Problem Details specification:

```json
{
  "type": "https://api.domain.com/errors/insufficient-inventory",
  "title": "Insufficient Inventory Balance",
  "status": 422,
  "detail": "Requested 5 units of SKU-1092, but only 2 units are currently available.",
  "instance": "/v1/tenants/t_102/orders",
  "trace_id": "req_88192039a",
  "invalid_params": [
    {
      "name": "line_items[1].quantity",
      "reason": "Exceeds available stock balance (Max: 2)"
    }
  ]
}
```

---

## 2. Endpoint Specification: Create Transaction / Order

### `POST /v1/transactions`
Creates an atomic transaction record, decrements warehouse inventory, and emits domain event for CRM processing.

#### 2.1 Request Headers
| Header | Type | Required | Description |
|---|---|---|---|
| `Authorization` | String | **Yes** | Bearer JWT containing user identity and role. |
| `Idempotency-Key`| String | **Yes** | Unique token to prevent duplicate charges upon network retry. |
| `X-Request-ID` | String | **Yes** | Distributed tracing correlation identifier. |

#### 2.2 Request Body Schema (JSON Schema)
```json
{
  "customer_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "payment_method": "QRIS",
  "payment_reference": "QRIS_TX_9812903",
  "discount_code": "PROMO10",
  "line_items": [
    {
      "product_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed",
      "quantity": 2,
      "unit_price": 150000.00
    },
    {
      "product_id": "2c9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bee",
      "quantity": 1,
      "unit_price": 75000.00
    }
  ],
  "notes": "Customer requested gift wrap."
}
```

#### 2.3 Response Codes & Payloads

##### `201 Created` — Order Successfully Placed
```json
{
  "data": {
    "transaction_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    "invoice_number": "INV/2026/11/0042",
    "subtotal": 375000.00,
    "discount_amount": 37500.00,
    "tax_amount": 37125.00,
    "total_amount": 374625.00,
    "payment_status": "PAID",
    "fulfillment_status": "PENDING",
    "created_at": "2026-11-03T06:30:00Z"
  }
}
```

##### `409 Conflict` — Idempotency Key Already Executing
```json
{
  "type": "https://api.domain.com/errors/concurrent-idempotent-request",
  "title": "Conflict",
  "status": 409,
  "detail": "An identical request with this Idempotency-Key is currently being processed."
}
```

##### `422 Unprocessable Entity` — Business Validation Failure
```json
{
  "type": "https://api.domain.com/errors/stock-deficit",
  "title": "Validation Error",
  "status": 422,
  "detail": "Product SKU-994 has only 0 available stock."
}
```

---

## 3. Webhook Specification: Payment Provider Notification

### `POST /v1/webhooks/payment-inbound`
Dispatched by payment providers (e.g. Stripe, Midtrans) to notify asynchronous settlement.

#### Verification Algorithm:
1. Extract signature from `X-Signature-SHA256` header.
2. Concatenate: `${HTTP_TIMESTAMP}.${RAW_REQUEST_BODY}`.
3. Compute HMAC with stored merchant secret.
4. Compare using a constant-time comparison function (`timingSafeEqual`) to prevent timing attacks.

#### Expected Response:
* The consumer must return `HTTP 200 OK` within **3,000 milliseconds** of receiving the payload, offloading heavy processing to an asynchronous worker queue.
