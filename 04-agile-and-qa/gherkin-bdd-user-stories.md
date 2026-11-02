# Gherkin BDD User Stories & Acceptance Criteria

> **Standard:** Behavior-Driven Development (BDD) using Gherkin syntax (`Feature`, `Scenario Outline`, `Given`, `When`, `Then`, `And`).  
> **Target Audience:** Product Owners, Developers, and QA Automation Engineers.

---

## Feature: Automated Customer Re-Engagement Trigger upon Order Completion

```gherkin
Feature: Automated Customer Re-engagement on POS Order
  As a Store Owner
  I want the system to automatically flag dormant customers when they complete a purchase
  So that my sales team can trigger personalized retention workflows and prevent future churn.

  Background:
    Given the store tenant "Toko Kopi Maju" exists with ID "tenant_102"
    And cashier "Budi" is logged into the POS terminal with role "CASHIER"

  # ==============================================================
  # Happy Path: Dormant customer reactivated after 75 days
  # ==============================================================
  @e2e @crm @high-priority
  Scenario: Successfully reactivate a dormant customer with a qualifying purchase
    Given a customer "Siti Rahma" exists with:
      | Field            | Value                 |
      | customer_id      | cust_881              |
      | last_order_date  | 75 days ago           |
      | lifecycle_status | DORMANT               |
      | total_orders     | 4                     |
    When cashier "Budi" submits a new order for "Siti Rahma":
      | Product SKU | Quantity | Unit Price |
      | SKU-BEANS-01| 2        | 120000     |
    And the payment of 240000 IDR is confirmed via "QRIS"
    Then the transaction should be saved with status "PAID"
    And an asynchronous event "retail.order.placed" should be emitted
    And within 2 seconds the customer "cust_881" should be updated to:
      | Field            | Value                 |
      | lifecycle_status | RE_ENGAGED            |
      | total_orders     | 5                     |
    And a CRM follow-up task "Send Welcome Back Message" should be queued in the CRM worker

  # ==============================================================
  # Edge Case: Regular active customer should not trigger re-engagement
  # ==============================================================
  @regression
  Scenario: Standard repeat purchase does not alter status of already active customer
    Given a customer "Andi Wijaya" exists with:
      | Field            | Value                 |
      | customer_id      | cust_992              |
      | last_order_date  | 3 days ago            |
      | lifecycle_status | ACTIVE                |
    When cashier "Budi" submits a new order for "Andi Wijaya" totaling 50000 IDR
    Then the transaction should be saved with status "PAID"
    And the customer "cust_992" lifecycle_status should remain "ACTIVE"
    And no re-engagement task should be generated

  # ==============================================================
  # Error & Guardrail Scenario: Out of stock item prevents order commit
  # ==============================================================
  @inventory @negative-test
  Scenario Outline: Attempting to purchase item exceeding warehouse stock
    Given product "<sku>" currently has <available_stock> units in inventory
    When cashier "Budi" attempts to add <requested_qty> units of "<sku>" to the cart
    Then the POS screen should display an error "<error_message>"
    And the checkout button should remain disabled
    And no inventory reservation should be committed to the database

    Examples:
      | sku          | available_stock | requested_qty | error_message                                 |
      | SKU-COLD-01  | 0               | 1             | "Item is currently out of stock."             |
      | SKU-PASTRY-02| 3               | 5             | "Only 3 units available. Cannot add 5 units."|
```

---

## 2. Best Practices for Writing Gherkin Stories

1. **Focus on Business Intent:** Avoid UI-specific implementation details like *"When I click the blue button with CSS selector #btn-submit"*. Instead write: *"When cashier submits a new order"*.
2. **Use Declarative Test Tables:** Data tables clearly communicate data preconditions (`Given`) and database assertions (`Then`).
3. **Cover Both Golden Paths & Edge Cases:** Every user story must contain at least one happy path, one boundary edge case, and one negative/error scenario.
