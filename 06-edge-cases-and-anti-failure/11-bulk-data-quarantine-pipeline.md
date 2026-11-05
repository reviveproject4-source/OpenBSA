# Blueprint 11: Bulk Data Ingestion & Quarantine Pipeline

> **Target Problem:** A business owner migrates from legacy software and uploads an Excel spreadsheet of 15,000 customers. At row #4,821, there is a broken email format and invalid characters. The developer's naive script crashes midway, leaving 4,820 customers inserted and 10,180 missing, with no log of what succeeded or failed.

---

## 1. The Nightmare Scenario
A newly signed retail client tries to import their master product inventory via a CSV file containing 25,000 SKUs. 
The developer wrote a synchronous web endpoint: `POST /api/products/import-csv`. 
The file upload times out at 30 seconds due to Nginx gateway limits. 
The client tries uploading again. Now the database contains duplicate SKUs, broken pricing, and half-migrated records. 
The client demands a refund and cancels their SaaS contract before their first month ends.

---

## 2. Architectural Blueprint: Asynchronous Ingestion & Quarantine Bucket

Never process bulk file uploads synchronously in a HTTP request thread. All bulk ingestions must follow the **Asynchronous Chunking & Error Quarantine** pattern:

```mermaid
graph TD
    classDef client fill:#e1f5fe,stroke:#0288d1,stroke-width:2px;
    classDef worker fill:#ede7f6,stroke:#512da8,stroke-width:2px;
    classDef valid fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef error fill:#ffebee,stroke:#c62828,stroke-width:2px;

    User[User Uploads CSV / Excel File]:::client --> S3[Saved to Object Storage / S3]:::client
    S3 --> Event[Emit Event: <code>file_uploaded</code>]:::worker
    
    Event --> Worker[Background Worker Process]:::worker
    Worker --> Parser[Stream & Validate Row-by-Row in Batches of 500]:::worker

    Parser --> Check{Is Row Valid?}
    Check -->|YES: Valid SKU & Price| BatchInsert[Bulk Insert into Production DB]:::valid
    Check -->|NO: Corrupted Format / Missing Data| Quarantine[Write to Quarantine Error Table<br/><i>Row Number + Error Reason</i>]:::error

    BatchInsert --> Summary[Generate Ingestion Summary Report]:::worker
    Quarantine --> Summary
    Summary --> Notification[Notify User via Email / In-App:<br/><i>'14,850 rows imported. 150 rows quarantined. Download Error CSV.'</i>]:::client
```

---

## 3. Database Specification: The Ingestion Audit & Quarantine Schema

```sql
CREATE TABLE data_import_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    file_name VARCHAR(255) NOT NULL,
    total_rows INT NOT NULL DEFAULT 0,
    successful_rows INT NOT NULL DEFAULT 0,
    quarantined_rows INT NOT NULL DEFAULT 0,
    status VARCHAR(30) NOT NULL DEFAULT 'PROCESSING', -- 'PROCESSING', 'COMPLETED', 'FAILED'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE TABLE import_quarantine_records (
    id BIGSERIAL PRIMARY KEY,
    job_id UUID NOT NULL REFERENCES data_import_jobs(id) ON DELETE CASCADE,
    row_number INT NOT NULL,
    raw_row_data JSONB NOT NULL,
    rejection_reason VARCHAR(255) NOT NULL, -- e.g. 'INVALID_EMAIL_FORMAT', 'DUPLICATE_BARCODE'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## 4. User Experience Requirement

The user is NEVER shown a generic 500 error screen. Instead:
1. The system displays a progress bar: `"Processing: 45% (6,750 / 15,000 rows)..."`
2. At completion, if errors occurred, the user is provided a 1-click button: **"Download Quarantined Rows (.csv)"**. This CSV contains only the 150 failed rows with a new column explaining exactly why each row was rejected, allowing the business owner to fix and re-upload only the corrected rows.
