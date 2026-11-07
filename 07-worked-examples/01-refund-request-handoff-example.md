# Worked Example — Refund Request Handoff

> **Illustrative example only.** This is not a claim about any specific business, legal requirement, payment provider, or production system. Amount limits, approval roles, timing, and retention rules must be confirmed by the actual business.

## 1. Business problem and outcome

**Problem:** Staff handle customer refund requests inconsistently. Some requests are discussed in chat, some are written on paper, and it is difficult to confirm whether a refund was requested, approved, processed, or reconciled.

**Desired outcome:** Every refund request has a traceable business status, is linked to the original sale, follows an approved authority rule, and can be reconciled with the payment record.

**Success looks like:** A manager can identify the original sale, refund reason, requester, approver, amount, current status, and final outcome without relying on private chat history.

## 2. Scope

**Included:** Staff refund request, review, approval or rejection, processing status, customer communication record, and reconciliation status.

**Not included:** Choosing a payment provider, designing database tables, selecting an API, or deciding a legal retention period.

## 3. Roles

| Role | Business responsibility |
|---|---|
| Frontline staff | Record the customer's request and supporting reason |
| Supervisor | Review request and approve or reject according to the approved policy |
| Finance / reconciliation role | Confirm that the payment outcome matches the recorded refund |
| Business owner | Approve refund policy, limits, and exceptions |

The business must confirm whether one person may request and approve the same refund. Until decided, this is an open policy question, not an invented rule.

## 4. Main process

1. Customer asks for a refund.
2. Staff locates the original sale and records the reason and requested amount.
3. The request is checked against the business's refund policy.
4. An authorized person approves or rejects it.
5. If approved, the refund is sent for processing through the business's chosen payment method.
6. The status remains pending until the outcome is confirmed.
7. Finance or the responsible role reconciles the refund against the payment record.
8. The customer is informed of the outcome.

## 5. Business rules

| Rule ID | Rule |
|---|---|
| BR-01 | A refund request must refer to an identifiable original sale. |
| BR-02 | The requested amount cannot exceed the refundable amount under the approved business policy. |
| BR-03 | A request must have a recorded reason. |
| BR-04 | Approval must be performed by a role authorized under the policy. |
| BR-05 | An approved request is not described as completed until the processing outcome is confirmed. |
| BR-06 | The business must be able to distinguish requested, under review, approved, rejected, processing, completed, and failed outcomes. |

## 6. Anticipated gaps and exceptions

| ID | Scenario | Why it matters | Business response to agree |
|---|---|---|---|
| GAP-01 | Customer requests only part of the original amount | Staff may refund too much or too little | Define partial-refund policy and how remaining refundable value is calculated |
| GAP-02 | Customer submits the same request twice | Duplicate processing could create financial loss | Detect possible duplicate requests and require review before another refund is processed |
| GAP-03 | Payment provider is unavailable or gives no clear result | Staff may tell the customer the refund is complete when it is not | Keep status pending, define who checks later, and avoid duplicate resubmission |
| GAP-04 | Original payment method is no longer available | The business may not know which alternative is permitted | Define approved alternative and verification process |
| GAP-05 | Staff member who normally approves is absent | Requests may accumulate or be approved informally | Define authorized backup and delegation limits |
| GAP-06 | Customer disputes the refund outcome | Business may lack a clear history of decisions and communication | Keep request history, reason, approvals, processing result, and communication record |

## 7. Acceptance criteria

| AC ID | Given | When | Then |
|---|---|---|---|
| AC-01 | A valid original sale exists | Staff submits a refund request | The request is linked to that sale and shows its requested amount and reason |
| AC-02 | No original sale can be identified | Staff tries to submit a refund request | The request is not treated as a valid refund request and the reason is visible |
| AC-03 | A request is awaiting approval | An unauthorized role attempts to approve it | The approval is not accepted and the attempt is reviewable |
| AC-04 | A refund has been approved but processing is unconfirmed | Staff views the request | The status is not shown as completed |
| AC-05 | A provider outcome is unclear | Staff checks the request | The status remains pending or under review until a confirmed outcome is recorded |
| AC-06 | A refund is completed | A manager reviews its history | The manager can see the original sale, amount, reason, requester, approver, and outcome |

## 8. Open business decisions

| ID | Decision needed | Why it matters | Decision owner |
|---|---|---|---|
| OPEN-01 | Refund approval limits by role | Determines who can approve which amounts | Business owner |
| OPEN-02 | Whether requesters may approve their own requests | Defines separation of responsibilities | Business owner |
| OPEN-03 | Time target for reviewing pending refunds | Sets customer and staff expectations | Operations owner |
| OPEN-04 | Permitted alternative when the original payment method is unavailable | Prevents informal and inconsistent workarounds | Finance / business owner |
| OPEN-05 | Applicable record-retention period | Must align with the actual business and relevant jurisdiction | Business owner with qualified adviser |

## 9. What the developer should understand

The business is not simply asking for a "refund button." It needs a controlled, traceable refund process with clear authority, distinct statuses, duplicate awareness, pending outcomes, reconciliation, and a way to handle provider uncertainty.

The developer may propose how to implement these behaviors. The business owner must decide the refund policy and approval authority. Technical implementation must not silently invent those business decisions.

## 10. Handoff status

**Ready for estimation only after** the business confirms the main policy assumptions and identifies the owner for unresolved decisions. It is not ready for full implementation while approval limits, self-approval, and alternative refund handling remain undecided.

**Lesson:** The BSA has helped the developer see the business process behind the requested feature—and the consequential cases that a simple feature description would have missed.
