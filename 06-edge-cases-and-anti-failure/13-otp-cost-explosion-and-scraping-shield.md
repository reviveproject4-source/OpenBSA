# Blueprint 13: OTP Cost-Explosion & Scraping Shield

> **Target Problem:** A malicious bot discovers your phone verification endpoint (`/api/auth/send-otp`). Over the weekend, the bot triggers 45,000 SMS requests to premium international phone numbers (SMS Toll Fraud). On Monday, the founder wakes up to a $6,500 Twilio bill and a suspended account.

---

## 1. The Nightmare Scenario: SMS Toll Fraud (Artificially Inflated Traffic)
Unscrupulous telecommunication operators in high-rate countries collaborate with botnets to trigger automated SMS verification requests to ranges of premium-rate phone numbers they control. 
Because the application had only naive single-IP rate-limiting:
* The bot uses residential rotating proxies (1 request per IP).
* The backend happily dispatches 30,000 SMS verification messages at $0.08 each.
* Total cost: $2,400 drained in 4 hours. The startup's Stripe card is automatically billed, draining operating payroll funds.

---

## 2. Architectural Blueprint: The Multi-Layer Defense Shield

```mermaid
graph TD
    classDef client fill:#e1f5fe,stroke:#0288d1,stroke-width:2px;
    classDef shield fill:#fff3e0,stroke:#f57c00,stroke-width:2px;
    classDef blocked fill:#ffebee,stroke:#c62828,stroke-width:2px;
    classDef pass fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;

    User[User clicks 'Send OTP']:::client --> Challenge{Layer 1: Turnstile / CAPTCHA<br/>Token Valid?}:::shield
    Challenge -->|Invalid / Missing| Drop1[403 Forbidden: Bot Detected]:::blocked

    Challenge -->|Valid Token| PhoneCheck{Layer 2: Phone Prefix Allowed?}:::shield
    PhoneCheck -->|High-risk unsupported country prefix| Drop2[400 Bad Request: Region Not Supported]:::blocked

    PhoneCheck -->|Supported Country| VelocityCheck{Layer 3: Velocity & Spend Limits}:::shield
    VelocityCheck -->|Exceeds 3 requests / hour per phone| Drop3[429 Too Many Requests]:::blocked
    VelocityCheck -->|Daily Spend Limit > $50 USD Threshold| EmergencyStop[AUTOMATIC KILL-SWITCH TRIGGERED:<br/>Disable SMS & Fallback to Email OTP]:::blocked

    VelocityCheck -->|All Checks Pass| Dispatch[Dispatch SMS via Vendor API]:::pass
```

---

## 3. Database Specification: The Toll Fraud Velocity Tracker

```sql
CREATE TABLE otp_dispatch_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number_e164 VARCHAR(20) NOT NULL,
    country_code VARCHAR(5) NOT NULL,
    ip_address INET NOT NULL,
    estimated_cost_cents INT NOT NULL DEFAULT 6, -- 6 cents per SMS
    status VARCHAR(20) NOT NULL DEFAULT 'SENT',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_otp_phone_time ON otp_dispatch_log (phone_number_e164, created_at);
CREATE INDEX idx_otp_daily_spend ON otp_dispatch_log (created_at);
```

---

## 4. Hard Business Guardrails

1. **Strict Geofencing:**
   Never allow SMS dispatch to countries where your business does not operate. If your business operates in Indonesia and the US, strictly drop any requests to non-whitelisted country codes (+232, +260, etc.) before calling the SMS API.
2. **Exponential Wait Time per Phone Number:**
   * 1st Attempt: Immediate
   * 2nd Attempt: 60-second cooldown
   * 3rd Attempt: 5-minute cooldown
   * 4th Attempt: Locked for 24 hours. Must contact support.
3. **The Daily Hard Spend Kill-Switch:**
   If total daily SMS spend reaches $50 USD, the backend automatically flips a configuration flag: `SMS_KILLSWITCH_ACTIVE = true`, switching the frontend to **Email Verification Only** and alerting the founder via Telegram/Slack immediately.
