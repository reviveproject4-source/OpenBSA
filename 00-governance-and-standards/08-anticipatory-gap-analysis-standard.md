# Anticipatory Gap Analysis Standard

> **Purpose:** Help a Business Systems Analyst (BSA) identify missing needs, plausible future conditions, and business exposure before they become incidents, costly changes, or disputes.
>
> **Status: PROPOSED — METHOD FOR REVIEW.** This standard supports structured analysis; it does not claim that every future event can be predicted or prevented.

## 1. Why this standard exists

A business may describe what it wants today while leaving important questions unanswered:

- What happens when the normal process cannot be followed?
- What changes when transaction volume, staff, locations, or customer types increase?
- Who is affected when a person, supplier, system, or approval is unavailable?
- Which decisions become expensive or difficult to reverse later?
- What information is needed to notice that the business is drifting toward a problem?

A BSA should not invent requirements merely to make a document look complete. The responsibility is to surface relevant unknowns, test assumptions, explain consequences, and help stakeholders decide what to address now, later, or not at all.

## 2. Four kinds of analysis statements

Every material finding must be labelled so that a possibility is not presented as a fact.

| Label | Meaning | Example |
|---|---|---|
| **FACT** | Confirmed by observation, record, or reliable source | Two staff members currently approve refunds |
| **ASSUMPTION** | Treated as true for planning but not yet confirmed | The supplier will continue supporting the current file format |
| **POSSIBLE GAP** | A missing rule, capability, decision, or scenario worth investigating | No process is defined for a refund when the original payment channel is unavailable |
| **DECISION** | A stakeholder has explicitly accepted an option or trade-off | Refunds above a chosen threshold require a second approver |

Record the source, owner, and date for important facts and decisions. Give assumptions an owner and a way to validate them.

## 3. Gap discovery domains

Use these domains as prompts, not as a mandatory checklist to fill blindly. Mark each domain as relevant, not relevant (with reason), or not yet assessed.

### A. Business goals and boundaries
- Are the business outcome and success measures clear?
- Are exclusions, constraints, and non-goals explicit?
- Could a department or stakeholder have a conflicting objective?
- What would make the proposed solution no longer worthwhile?

### B. People, roles, and authority
- Who performs, requests, approves, reviews, and overrides each important action?
- What happens when the responsible person is absent, leaves, or changes role?
- Could one person create and approve the same sensitive transaction?
- Are temporary staff, contractors, delegated authority, and emergency access considered?

### C. Normal process and exceptions
- What starts and ends each process?
- What happens with incomplete, duplicate, late, incorrect, cancelled, disputed, or out-of-order requests?
- Can work be paused, resumed, reversed, corrected, or escalated?
- Are manual workarounds visible and controlled?

### D. Customer and stakeholder experience
- What happens when a customer changes their mind, makes a mistake, loses access, or needs assistance?
- Are complaints, accessibility needs, language, consent, and communication preferences considered?
- What happens when the business cannot meet a promise or expected service level?

### E. Data and records
- Who owns each important data item and who may view or change it?
- Where does data originate, how is it checked, and how long is it retained?
- How are duplicates, conflicting updates, missing records, corrections, exports, and deletion requests handled?
- Which records must remain available for accounting, disputes, or lawful obligations?

### F. Money and commercial exposure
- Are pricing, discounts, fees, refunds, deposits, commissions, tax, and settlement rules clear?
- What happens with partial payments, overpayments, chargebacks, failed settlements, and reconciliation differences?
- Could a delay, rounding issue, or manual override create financial leakage?
- Who bears the loss when an external party fails?

### G. Time, volume, and growth
- What changes during peak periods, seasonal demand, rapid growth, or multiple locations?
- Are deadlines, time zones, cut-off times, queues, and service expectations defined?
- What breaks first if volume multiplies or processing is delayed?
- Which decisions are cheap now but expensive to change later?

### H. External parties and dependencies
- What if a bank, payment provider, courier, messaging service, identity provider, or supplier is unavailable or changes its service?
- Are responsibilities, response expectations, data exchange, and exit arrangements understood?
- Is there a safe manual or alternative process?

### I. Security, misuse, and trust
- What could an ordinary user, careless employee, dishonest insider, or compromised account do?
- Are sensitive actions reviewable and attributable?
- What happens after lost devices, leaked credentials, suspicious activity, or mistaken access?
- Are privacy and regulatory questions referred to qualified reviewers where necessary?

### J. Continuity, recovery, and change
- What happens during power, network, device, site, or system outages?
- Which activities must continue, and which may safely wait?
- How are backups, recovery, corrections, and communication tested?
- How will new rules, migrations, integrations, vendors, and business models affect existing work?

## 4. Future-gap scenarios

For each important process, consider a small number of plausible changes. Select scenarios based on the business context; do not force every scenario onto every project.

- **Growth:** transaction volume, customers, staff, branches, or product range increases.
- **Contraction:** budget, staffing, demand, or supplier capacity decreases.
- **Absence:** a key person, approver, owner, or vendor is unavailable.
- **Disruption:** internet, electricity, premises, device, or external service fails.
- **Abuse or error:** fraud, accidental action, duplicate request, wrong data, or credential compromise occurs.
- **Change:** price, policy, law, ownership, process, integration, or provider changes.
- **Dispute:** customer, employee, supplier, or regulator challenges a transaction or decision.
- **Exit:** a customer leaves, a vendor is replaced, data must be exported, or the system is retired.

For each selected scenario, ask: **What changes, who is affected, what could be lost, how would we notice, and what decision or fallback is needed?**

## 5. Assess and prioritize without false precision

Prioritize a gap using business judgement and available evidence. Consider:

1. **Impact:** effect on customers, revenue, cash flow, operations, trust, safety, or obligations.
2. **Exposure:** how often the situation could arise and how many people or transactions it could affect.
3. **Detectability:** how quickly the business would notice the issue.
4. **Reversibility:** how difficult or costly it would be to correct after the decision is made.
5. **Readiness:** whether an owner, workaround, control, or decision already exists.

Use plain-language priority labels:

- **Critical:** credible risk of severe harm, material loss, major interruption, or serious obligation breach; resolve or explicitly control before proceeding.
- **High:** significant business impact or expensive future change; obtain an owner and plan before the relevant milestone.
- **Medium:** meaningful but manageable exposure; schedule or monitor.
- **Low:** limited impact or easy reversibility; document and revisit if conditions change.
- **Watch:** plausible but currently weakly evidenced; define a trigger that would justify reassessment.

Do not assign numerical probability, financial loss, or risk scores unless the inputs and calculation method are supported by evidence. If evidence is missing, say so.

## 6. Required gap record

Every material gap should capture:

- Unique ID and concise title.
- Business process and affected stakeholders.
- Statement of the gap or unanswered question.
- Classification: current / emerging / future possibility.
- Evidence and source; clearly identify assumptions and unknowns.
- Trigger or early warning sign that would make the scenario relevant.
- Consequence and affected business area.
- Priority and rationale.
- Proposed response: prevent, detect, respond, recover, accept, or investigate.
- Responsible decision-maker and action owner.
- Decision deadline or review trigger, where relevant.
- Status and evidence that closes or reduces the gap.

A gap is not closed merely because a developer says it is handled. Confirm the business rule, responsible owner, acceptance condition, and appropriate evidence.

## 7. From gap to useful action

For each prioritized gap, choose one of these outcomes:

- **Resolve now:** clarify the business rule or requirement before scope approval.
- **Design for later:** preserve a reasonable option without building speculative features now.
- **Create a fallback:** define a manual or alternate process for a disruption.
- **Monitor:** identify an observable trigger and review owner.
- **Accept:** record who accepts the exposure and why.
- **Investigate:** gather evidence before selecting a solution.
- **Out of scope:** document the boundary and likely consequence so it is not mistaken for an omission.

The BSA explains the business need and acceptance outcome. The developer and technical specialists determine an appropriate implementation with the project stakeholders.

## 8. Review points

Revisit the gap register:

- Before scope and budget are agreed.
- Before a major design or vendor decision.
- When a new stakeholder, location, product, or integration is added.
- When a process, policy, law, or external dependency changes.
- During testing, pilot, handover, and post-launch review.
- After incidents, complaints, near misses, or unexpected workarounds.

Do not keep a gap register alive for its own sake. Retire items that are no longer relevant and record why.

## 9. BSA deliverable

A useful anticipatory analysis should leave the business with:

1. A clear picture of confirmed facts and unresolved assumptions.
2. A prioritized list of current and plausible future gaps.
3. Named owners for decisions and actions.
4. Early warning triggers for important future risks.
5. Explicit accepted trade-offs and out-of-scope items.
6. Business-readable acceptance conditions for the agreed responses.

## 10. Limitations and integrity

- This method cannot predict every future event.
- A scenario is not proof that the event will happen.
- Legal, tax, privacy, safety, and regulatory conclusions require qualified and jurisdiction-specific review.
- Avoid speculative feature expansion. A plausible gap must have a business reason, consequence, and proportionate response.
- Record uncertainty honestly. Never label an assumption as verified evidence.

**Guiding principle:** Find the gap early, explain why it matters, prepare a proportionate response, and leave the implementation choice to the appropriate team.
