# Business-to-Developer Handoff Standard

> **Purpose:** Make the business analysis understandable, actionable, and reviewable by a developer before implementation begins.
>
> **Status: PROPOSED — METHOD FOR REVIEW.** This standard defines the quality of the handoff, not a required software stack, architecture, or coding method.

## 1. The handoff promise

A developer should be able to read the handoff and understand:

1. What business problem needs to be solved and why it matters.
2. Who uses or is affected by the process.
3. What the process does in normal and exceptional situations.
4. Which business rules must be followed.
5. What the system must demonstrate for the business to accept the result.
6. Which assumptions, decisions, risks, and gaps remain unresolved.

The handoff does not tell developers which programming language, framework, database, or architecture they must use unless the business has a documented constraint approved by the responsible stakeholder.

## 2. Minimum handoff contents

A handoff is ready for developer estimation or implementation planning when the relevant items below are clear. Mark an item **Not applicable** with a reason, or **Open** with an owner and next action. Do not silently leave important uncertainty.

### A. Business context
- Business problem and evidence that it exists.
- Desired business outcome and how success will be observed.
- Scope, exclusions, constraints, and affected business areas.
- Stakeholders, users, customers, and decision-makers.

### B. Process understanding
- Current process and pain points.
- Intended future process in plain language or a simple flow.
- Start and end conditions.
- Roles and responsibilities at each important step.
- Normal path, exception paths, corrections, cancellation, and recovery.

### C. Business rules
- Conditions that allow or prevent an action.
- Approval limits and delegated authority.
- Timing, cut-off, expiry, and sequence rules.
- Pricing, payment, refund, stock, or other calculations where relevant.
- Duplicate handling and rules for reversing or correcting transactions.
- Rules that are explicitly out of scope.

### D. Data and information
- Information the business needs to collect, display, update, or retain.
- Business meaning of important fields and statuses.
- Source of truth and responsible owner.
- Who may see or change sensitive information, described in business roles.
- Recordkeeping, history, export, correction, and retention needs.

### E. Exceptions and anticipatory gaps
- Known failure and exception scenarios.
- Plausible future scenarios that matter to this business.
- Early warning signs and operational fallback.
- Consequences if no action is taken.
- Response selected: resolve now, prepare for later, fallback, monitor, investigate, accept, or out of scope.

### F. Acceptance and handover
- Observable acceptance criteria in business language.
- Example cases, including important negative and boundary cases.
- Who reviews and accepts the result.
- Training, operational ownership, support, and handover needs.
- Open decisions and dependencies that could block delivery.

## 3. Describe behavior, not implementation

Write requirements in terms of business outcomes and observable behavior.

**Prefer:** "A refund request must be linked to the original sale. The business must be able to identify who requested and approved it."

**Avoid unless specifically required:** "Create a RefundService class with a PostgreSQL trigger and Redis lock."

The developer may propose the implementation. The BSA and business owner verify that the proposal satisfies the agreed business rules, constraints, and acceptance conditions.

## 4. Make exceptions visible

For each important process, ask whether the handoff covers:

- Missing, invalid, duplicate, late, or conflicting information.
- Cancellation, correction, reversal, and dispute.
- Partial completion or partial payment.
- A person with authority being unavailable.
- An external provider or dependency being unavailable.
- A process interrupted midway and later resumed.
- Manual workaround and later reconciliation.
- Growth, new locations, new user groups, or policy changes where relevant.

Do not add every scenario automatically. Record only those that are plausible and consequential for the project, and explain why.

## 5. Requirement and decision traceability

Give each important requirement, rule, gap, and decision a stable identifier. Link them where practical:

**Business problem → business rule / requirement → gap or risk → acceptance criterion → evidence / decision.**

A developer should be able to ask why a requirement exists and find its business reason. A business owner should be able to see which agreed need a delivered behavior satisfies.

## 6. Open questions are not hidden

Every unresolved item must state:
- What is unknown or undecided.
- Why the answer matters.
- Who can decide or provide evidence.
- When the answer is needed.
- What work is blocked or what assumption would otherwise be used.

Do not present an unapproved assumption as a confirmed requirement. If implementation can proceed safely with a temporary assumption, record it and obtain explicit approval.

## 7. Handoff readiness

Use these outcomes:

- **Ready for estimation:** business problem, scope, main workflow, key rules, major gaps, and acceptance outcomes are understandable. Open items are visible and do not invalidate a reasonable estimate.
- **Ready for implementation:** decisions and dependencies needed for the next work increment are resolved; acceptance criteria are testable; accountable reviewers are named.
- **Not ready:** critical business rules, authority, financial handling, scope, or major dependencies remain ambiguous.

Readiness is not a claim that every future situation is known. It is a transparent statement of what has been analyzed and what remains uncertain.

## 8. Developer clarification and change loop

Developers are expected to raise:
- Contradictions between requirements.
- Missing decisions or ambiguous wording.
- Cases where a requested behavior conflicts with a stated constraint.
- New risks discovered during design or implementation.
- A simpler or safer alternative that preserves the business outcome.

The BSA records the question, obtains a business decision, updates the relevant requirement and acceptance criteria, and communicates the approved change. Developers should not silently invent business policy to fill a gap.

## 9. Definition of a useful handoff

A useful handoff lets a developer say:

- I understand the business problem and intended outcome.
- I know the users, roles, workflow, and business rules.
- I can see the important exceptions and future risks already considered.
- I know what is decided, assumed, open, and out of scope.
- I know how the business will judge whether the result is correct.
- I can propose the technical solution without guessing the business policy.

**Guiding principle:** The BSA makes the business intent and its edge cases visible. The developer turns that intent into a sound technical solution and raises any new uncertainty before it becomes hidden behavior.
