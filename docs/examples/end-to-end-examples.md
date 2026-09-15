# End-to-End Examples

Two fully worked examples you can build from scratch. Every field value, node config, and rule condition is specified exactly as you would enter it in the UI or API.

---

## Example 1 — Automated Overdue Invoice Processing (no form)

**What it does**: every morning at 8am, query the database for invoices that have been unpaid for more than 30 days, classify each one by outstanding amount using a decision table, and take a different action per tier: send a gentle email reminder for small invoices, send the reminder plus alert the sales rep for medium ones, and open a human escalation for large ones.

**Components**:
- 1 cron-triggered workflow
- 1 decision-table rule (invoice tier classification)
- `db_query` → `evaluate_rules` → `for_each` → `switch` → email/approval nodes

---

### Step 1 — Create the rule: Invoice Tier Classification

Navigate to **Rules → New Rule**.

| Setting | Value |
|---|---|
| Name | `Invoice Tier Classification` |
| Trigger events | `manual` (this rule is invoked by the workflow, not an external event) |
| Rule type | **Decision table** |
| Hit policy | `first` |

**Condition columns:**

| Column label | Field path | Operator |
|---|---|---|
| Amount Overdue | `amount_due` | (numeric comparison per row) |

**Output columns:**

| Column label | Output field name |
|---|---|
| Tier | `tier` |
| Action | `action` |

**Rows** (top to bottom, first-match wins):

| amount_due | → tier | → action |
|---|---|---|
| `>= 50000` | `"enterprise"` | `"escalate"` |
| `>= 10000` | `"medium"` | `"alert_rep"` |
| `*` (any) | `"small"` | `"remind"` |

Click **Publish** to activate the rule.

---

### Step 2 — Create the workflow

Navigate to **Workflows → New Workflow**.

| Setting | Value |
|---|---|
| Name | `Daily Overdue Invoice Processing` |
| Description | `Runs every morning, processes all invoices overdue > 30 days` |
| Trigger type | `cron` |
| Trigger config | `{ "cron": "0 8 * * *" }` |
| Active | Yes |

---

### Step 3 — Build the node graph

Build these nodes in order. After placing each node, click it to open the config panel.

#### Node 1: `db_query` — Fetch Overdue Invoices

| Field | Value |
|---|---|
| Node type | `db_query` |
| Node name | `Fetch Overdue Invoices` |
| SQL | see below |
| credential_id | *(select your PostgreSQL credential)* |

```sql
SELECT
  id,
  invoice_number,
  customer_name,
  customer_email,
  sales_rep_email,
  amount_due,
  due_date,
  NOW() - due_date AS days_overdue
FROM invoices
WHERE
  status = 'unpaid'
  AND due_date < NOW() - INTERVAL '30 days'
ORDER BY amount_due DESC
```

Output shape (one row example):
```json
{
  "rows": [
    {
      "id": "inv-001",
      "invoice_number": "INV-2026-0042",
      "customer_name": "Acme Corp",
      "customer_email": "ap@acme.com",
      "sales_rep_email": "alice@mycompany.com",
      "amount_due": 75000,
      "due_date": "2026-02-15",
      "days_overdue": "72 days"
    }
  ]
}
```

#### Node 2: `for_each` — Process Each Invoice

Connect from Node 1 (default edge, no branch label).

| Field | Value |
|---|---|
| Node type | `for_each` |
| Node name | `For Each Invoice` |
| items_path | `rows` |
| continue_on_error | `true` *(one bad invoice shouldn't stop the rest)* |

For the `body_nodes` and `body_edges` fields, you will build the inner loop body directly on the canvas once you drop this node. The inner body contains Nodes 3–7 below.

> **Tip**: In the workflow builder, after dropping `for_each`, click **Edit Body** to open the inner canvas for the loop body. Build Nodes 3–7 inside that inner canvas.

Each iteration receives:
```json
{
  "rows": [...],           // full outer list still available
  "item": {               // the current invoice row
    "id": "inv-001",
    "invoice_number": "INV-2026-0042",
    "customer_name": "Acme Corp",
    "amount_due": 75000,
    ...
  },
  "_index": 0              // iteration counter
}
```

#### Node 3 (inner): `evaluate_rules` — Classify This Invoice

| Field | Value |
|---|---|
| Node type | `evaluate_rules` |
| Node name | `Classify Invoice` |
| event_type | `manual` |
| dry_run | `false` |

This node runs the **Invoice Tier Classification** decision table you published in Step 1 against the current invoice. The payload fed to the rule is the current `item` — so `amount_due` resolves correctly against the `amount_due` column in the decision table.

After this node the payload is enriched:
```json
{
  "item": { ... },
  "_rule_results": {
    "<rule-uuid>": { "tier": "enterprise", "action": "escalate" }
  },
  "_rules_matched": ["<rule-uuid>"],
  "tier": "enterprise",
  "action": "escalate"
}
```

#### Node 4 (inner): `switch` — Route by Action

Connect from Node 3 (default edge).

| Field | Value |
|---|---|
| Node type | `switch` |
| Node name | `Route by Tier` |
| expression | `action` |
| cases | `[{"value":"remind","label":"remind"}, {"value":"alert_rep","label":"alert_rep"}, {"value":"escalate","label":"escalate"}]` |
| default_case | `remind` |

This produces three outgoing edges:
- `switch_remind` → Node 5
- `switch_alert_rep` → Node 6
- `switch_escalate` → Node 7

#### Node 5 (inner): `gmail_send` — Gentle Reminder

Connect from the `switch_remind` edge.

| Field | Value |
|---|---|
| Node type | `gmail_send` |
| Node name | `Send Reminder Email` |
| to | `{{item.customer_email}}` |
| subject | `Friendly reminder: Invoice {{item.invoice_number}} is overdue` |
| body | `Hi {{item.customer_name}},\n\nThis is a friendly reminder that invoice {{item.invoice_number}} for ${{item.amount_due}} was due on {{item.due_date}}.\n\nPlease arrange payment at your earliest convenience.\n\nThank you,\nAccounts Receivable` |
| credential_id | *(select your Gmail OAuth credential)* |

#### Node 6 (inner): `gmail_send` — Reminder + Rep Alert (two parallel nodes)

Connect from the `switch_alert_rep` edge to **both** of these nodes in parallel.

**Node 6a** — Customer reminder (same template as Node 5)

**Node 6b** — Sales rep alert

| Field | Value |
|---|---|
| Node type | `gmail_send` |
| Node name | `Alert Sales Rep` |
| to | `{{item.sales_rep_email}}` |
| subject | `Action needed: {{item.customer_name}} invoice overdue ({{item.days_overdue}})` |
| body | `Hi,\n\nYour customer {{item.customer_name}} has an overdue invoice.\n\nInvoice: {{item.invoice_number}}\nAmount: ${{item.amount_due}}\nOverdue by: {{item.days_overdue}}\n\nPlease follow up directly.\n\nThanks,\nFinance` |
| credential_id | *(select your Gmail OAuth credential)* |

#### Node 7 (inner): `wait_approval` — Manual Escalation

Connect from the `switch_escalate` edge.

| Field | Value |
|---|---|
| Node type | `wait_approval` |
| Node name | `Escalation Approval` |
| approver_email | `cfo@mycompany.com` |
| prompt | `Invoice {{item.invoice_number}} from {{item.customer_name}} is ${{item.amount_due}} overdue by {{item.days_overdue}}. Please approve escalation to collections or mark for write-off review.` |
| label | `Invoice Escalation` |
| timeout_hours | `48` |
| continue_on_error | `true` |

**Node 7a** (true branch — approved, proceed to collections):

| Field | Value |
|---|---|
| Node type | `http_request` |
| Node name | `Send to Collections API` |
| url | `https://collections.mycompany.com/api/cases` |
| method | `POST` |
| body | `{"invoice_id": "{{item.id}}", "amount": {{item.amount_due}}, "customer": "{{item.customer_name}}"}` |
| credential_id | *(select your collections API credential)* |

**Node 7b** (false branch — timed out or rejected, just log):

| Field | Value |
|---|---|
| Node type | `gmail_send` |
| Node name | `Notify Finance — Escalation Skipped` |
| to | `finance@mycompany.com` |
| subject | `Escalation not approved: {{item.invoice_number}}` |
| body | `The CFO escalation for {{item.customer_name}} ({{item.invoice_number}}, ${{item.amount_due}}) was not approved within 48 hours. Manual review required.` |
| credential_id | *(select Gmail credential)* |

---

### Complete node graph (text diagram)

```
[cron_trigger]
    │
    ▼
[db_query: Fetch Overdue Invoices]
    │
    ▼
[for_each: For Each Invoice]   ← iterates over rows[]
    │
    ▼ (inner body)
[evaluate_rules: Classify Invoice]
    │
    ▼
[switch: Route by Tier]
    │               │               │
 switch_remind  switch_alert_rep  switch_escalate
    │               │               │
    ▼               ▼               ▼
[gmail_send:   [gmail_send: +  [wait_approval:
 Reminder]      gmail_send:    Escalation]
                Alert Rep]      ├─ true ──▶ [http_request: Collections]
                                └─ false ─▶ [gmail_send: Notify Finance]
```

---

### What you get

Every morning at 8am:
- All invoices unpaid for 30+ days are fetched
- Each is classified in under a second using the decision table
- Small invoices get a polite email automatically
- Medium invoices trigger a customer email and a rep nudge in parallel
- Large invoices pause the workflow until the CFO takes action — the workflow state is preserved safely in Temporal and resumes immediately once a decision is made

No form involved. No human interaction required for the first two tiers.

---

---

## Example 2 — New Vendor Onboarding with Risk-Based Approval

**What it does**: a procurement team member fills out a vendor registration form. A rule fires immediately to classify the vendor's risk level. A workflow then picks up the submission, checks risk, and routes the application through different approval tracks before provisioning access.

**Components**:
- 1 vendor onboarding form
- 1 condition-tree rule (risk classification → trigger workflow)
- 1 main workflow (form_trigger → approval → provisioning)
- 1 sub-workflow (provisioning steps, called at the end)

---

### Step 1 — Build the form

Navigate to **Forms → New Form**.

| Setting | Value |
|---|---|
| Name | `Vendor Registration` |
| Slug | `vendor-registration` |
| Description | `Internal form for registering new vendors` |
| Public | No (internal, requires login) |

**Add these fields in order:**

| # | Field name | Label | Type | Required | Notes |
|---|---|---|---|---|---|
| 1 | `vendor_name` | Vendor Company Name | `text` | Yes | — |
| 2 | `vendor_contact_email` | Vendor Contact Email | `email` | Yes | — |
| 3 | `vendor_type` | Vendor Type | `select` | Yes | Options: `software`, `hardware`, `services`, `financial_services`, `legal`, `facilities` |
| 4 | `annual_contract_value` | Estimated Annual Contract Value ($) | `currency` | Yes | — |
| 5 | `data_access` | Will this vendor access company data? | `radio` | Yes | Options: `yes`, `no` |
| 6 | `data_types` | What types of data will they access? | `checkbox_group` | No | Options: `PII`, `Financial`, `IP/Trade Secrets`, `None` |
| 7 | `requestor_name` | Your Name | `text` | Yes | — |
| 8 | `requestor_email` | Your Email | `email` | Yes | — |
| 9 | `business_justification` | Business Justification | `textarea` | Yes | min_length: 50 |
| 10 | `existing_nda` | NDA already signed? | `radio` | Yes | Options: `yes`, `no` |
| 11 | `nda_date` | NDA Date | `date` | No | Hidden unless `existing_nda` = `yes` |

**Conditional logic on `data_types` field**:
- Show when: `data_access` equals `yes`

**Conditional logic on `nda_date` field**:
- Show when: `existing_nda` equals `yes`

**Computed field** (add as field 12):

| Field name | Label | Type | Expression |
|---|---|---|---|
| `risk_score_hint` | Estimated Risk Score | `computed` | `annual_contract_value > 100000 ? "High" : data_access === "yes" ? "Medium" : "Low"` |

This gives the submitter a live preview of their risk classification before submitting.

Click **Save**. Leave the form private.

---

### Step 2 — Create the rule: Vendor Risk Classification

Navigate to **Rules → New Rule**.

| Setting | Value |
|---|---|
| Name | `Vendor Risk Classification` |
| Trigger events | `form_submit` |
| Rule type | **Condition tree** |
| Form filter | *(set form_id to match the Vendor Registration form)* |

**Condition tree** (AND logic):

```
Root (OR)
  ├── Branch A (AND): High Risk
  │     ├── data.annual_contract_value >= 100000
  │     └── (no further condition needed — value alone triggers high)
  │
  ├── Branch B (AND): Medium Risk — data access
  │     └── data.data_access equals "yes"
  │
  └── Branch C: Financial / Legal — always elevated
        └── data.vendor_type in "financial_services,legal"
```

> **How to build this**: create the root as an `OR` group. Inside it add three `AND` sub-groups, each with the conditions above. The rule fires if any branch matches.

**Actions** (execute in order):

1. **`set_field`** — Compute risk level:
   - Field name: `risk_level`
   - Value: `"high"` *(use a separate rule per level — see note below)*

> **Note on multiple rules**: because you need to set different risk levels, create **three separate rules** in order, each with a `stop_processing` action at the end to prevent multiple rules firing:

**Rule 1 — High Risk** (priority 1):
- Condition: `data.annual_contract_value >= 100000` OR `data.vendor_type in "financial_services,legal"`
- Actions:
  1. `set_field` → `risk_level` = `"high"`
  2. `trigger_workflow` → Vendor Onboarding Workflow (input: `{"risk_level": "high"}`)
  3. `stop_processing`

**Rule 2 — Medium Risk** (priority 2):
- Condition: `data.data_access equals "yes"` OR `data.annual_contract_value >= 25000`
- Actions:
  1. `set_field` → `risk_level` = `"medium"`
  2. `trigger_workflow` → Vendor Onboarding Workflow (input: `{"risk_level": "medium"}`)
  3. `stop_processing`

**Rule 3 — Low Risk** (priority 3, no condition needed — catch-all):
- Condition: *(none — always matches if rules 1 and 2 didn't fire and stop)*
- Actions:
  1. `set_field` → `risk_level` = `"low"`
  2. `trigger_workflow` → Vendor Onboarding Workflow (input: `{"risk_level": "low"}`)

Publish all three rules. Because each high/medium rule ends with `stop_processing`, only one fires per submission.

> The `trigger_workflow` action passes the original form payload **plus** the `risk_level` field to the workflow. The workflow input looks like:
> ```json
> {
>   "data": {
>     "vendor_name": "Acme Payments Ltd",
>     "vendor_type": "financial_services",
>     "annual_contract_value": 150000,
>     "data_access": "yes",
>     ...
>   },
>   "risk_level": "high",
>   "form_id": "...",
>   "submission_id": "...",
>   "submitted_at": "..."
> }
> ```

---

### Step 3 — Create the provisioning sub-workflow

Build this first so you can reference its ID in the main workflow.

Navigate to **Workflows → New Workflow**.

| Setting | Value |
|---|---|
| Name | `Vendor Provisioning` |
| Trigger type | `manual` *(called by the main workflow)* |
| Active | Yes |

**Nodes:**

**Node 1: `http_request` — Create Vendor in ERP**

| Field | Value |
|---|---|
| url | `https://erp.mycompany.com/api/vendors` |
| method | `POST` |
| body | `{"name": "{{data.vendor_name}}", "contact_email": "{{data.vendor_contact_email}}", "type": "{{data.vendor_type}}", "risk_level": "{{risk_level}}"}` |
| credential_id | *(ERP API credential)* |

Output: `{ "vendor_id": "VND-0042", "status": "created" }` (from ERP)

**Node 2: `gmail_send` — Welcome Email to Vendor** (connect from Node 1)

| Field | Value |
|---|---|
| to | `{{data.vendor_contact_email}}` |
| subject | `Welcome to our vendor network — next steps` |
| body | `Dear {{data.vendor_name}},\n\nYour vendor registration has been approved and you have been added to our system (ID: {{vendor_id}}).\n\nA member of our procurement team will be in touch within 3 business days to complete onboarding.\n\nThank you,\nProcurement Team` |
| credential_id | *(Gmail credential)* |

**Node 3: `gmail_send` — Notify Requestor** (connect from Node 1 in parallel with Node 2)

| Field | Value |
|---|---|
| to | `{{data.requestor_email}}` |
| subject | `Vendor approved: {{data.vendor_name}}` |
| body | `Hi {{data.requestor_name}},\n\nYour vendor registration for {{data.vendor_name}} has been approved and provisioned (ERP ID: {{vendor_id}}).\n\nYou can now raise purchase orders against this vendor.\n\nThanks,\nProcurement` |
| credential_id | *(Gmail credential)* |

Note the provisioning workflow ID after saving — you'll reference it in Step 4.

---

### Step 4 — Create the main onboarding workflow

Navigate to **Workflows → New Workflow**.

| Setting | Value |
|---|---|
| Name | `Vendor Onboarding` |
| Trigger type | `manual` *(triggered by rules, not directly by form)* |
| Active | Yes |

> **Why `manual` and not `form_submit`?** The rules engine triggers this workflow, not the form directly. The rules run first to set `risk_level`, then the rule action calls `trigger_workflow` with an enriched payload. If you used `form_submit` trigger directly on the workflow, you'd lose the risk classification step.

---

**Node 1: `if_condition` — Check Risk Level**

| Field | Value |
|---|---|
| Node type | `if_condition` |
| Node name | `Is High Risk?` |
| expression | `risk_level === "high"` |

Connect two outgoing edges:
- Label `"true"` → Node 2 (high-risk track)
- Label `"false"` → Node 5 (medium/low track)

---

**Node 2: `wait_approval` — Legal Review (high-risk only)**

Connect from `"true"` edge of Node 1.

| Field | Value |
|---|---|
| Node type | `wait_approval` |
| Node name | `Legal Review` |
| approver_email | `legal@mycompany.com` |
| prompt | `New HIGH RISK vendor registration requires legal review.\n\nVendor: {{data.vendor_name}}\nType: {{data.vendor_type}}\nContract Value: ${{data.annual_contract_value}}\nData Access: {{data.data_access}}\nJustification: {{data.business_justification}}\n\nPlease approve or reject.` |
| label | `Legal Review — {{data.vendor_name}}` |
| timeout_hours | `72` |
| continue_on_error | `false` |

Connect two outgoing edges:
- Label `"true"` → Node 3 (legal approved)
- Label `"false"` → Node 4 (legal rejected / timed out)

---

**Node 3: `wait_approval` — CFO Approval (high-risk, after legal)**

Connect from `"true"` edge of Node 2.

| Field | Value |
|---|---|
| Node type | `wait_approval` |
| Node name | `CFO Approval` |
| approver_email | `cfo@mycompany.com` |
| prompt | `Legal has reviewed and approved this high-risk vendor. Financial approval required.\n\nVendor: {{data.vendor_name}}\nAnnual Contract Value: ${{data.annual_contract_value}}\nRisk Level: {{risk_level}}\n\nApprove to proceed with provisioning.` |
| label | `CFO Approval — {{data.vendor_name}}` |
| timeout_hours | `48` |

Connect:
- Label `"true"` → Node 6 (merge, proceed to provisioning)
- Label `"false"` → Node 4 (rejection)

---

**Node 4: `gmail_send` — Rejection Notification**

This node is shared — connect to it from any rejection path (Node 2 false, Node 3 false, Node 5 false).

| Field | Value |
|---|---|
| Node type | `gmail_send` |
| Node name | `Send Rejection Notice` |
| to | `{{data.requestor_email}}` |
| subject | `Vendor registration not approved: {{data.vendor_name}}` |
| body | `Hi {{data.requestor_name}},\n\nUnfortunately, the vendor registration for {{data.vendor_name}} has not been approved at this time.\n\nIf you believe this is in error or have additional information, please contact procurement@mycompany.com.\n\nThank you,\nProcurement` |
| credential_id | *(Gmail credential)* |

---

**Node 5: `if_condition` — Medium vs Low (from false branch of Node 1)**

Connect from `"false"` edge of Node 1.

| Field | Value |
|---|---|
| Node type | `if_condition` |
| Node name | `Is Medium Risk?` |
| expression | `risk_level === "medium"` |

Connect:
- Label `"true"` → Node 5a (medium: single manager approval)
- Label `"false"` → Node 6 (low risk: skip approval, go straight to provisioning)

---

**Node 5a: `wait_approval` — Procurement Manager (medium risk only)**

Connect from `"true"` edge of Node 5.

| Field | Value |
|---|---|
| Node type | `wait_approval` |
| Node name | `Procurement Manager Approval` |
| approver_email | `procurement-manager@mycompany.com` |
| prompt | `Medium-risk vendor registration pending your approval.\n\nVendor: {{data.vendor_name}}\nType: {{data.vendor_type}}\nContract Value: ${{data.annual_contract_value}}\nData Access: {{data.data_access}}\nJustification: {{data.business_justification}}` |
| label | `Vendor Approval — {{data.vendor_name}}` |
| timeout_hours | `24` |

Connect:
- Label `"true"` → Node 6
- Label `"false"` → Node 4

---

**Node 6: `call_workflow` — Run Provisioning**

This is the convergence point. Connect to it from:
- Node 3 true (CFO approved)
- Node 5 false (low risk — skip approval)
- Node 5a true (medium risk approved)

| Field | Value |
|---|---|
| Node type | `call_workflow` |
| Node name | `Provision Vendor` |
| sub_workflow_id | *(UUID of the Vendor Provisioning workflow from Step 3)* |
| timeout_hours | `1` |

The full current payload is passed to the provisioning sub-workflow as its input.

---

### Complete node graph

```
[manual_trigger]  ← called by the rules engine with risk_level set
    │
    ▼
[if_condition: Is High Risk?]
    │                    │
   true                false
    │                    │
    ▼                    ▼
[wait_approval:    [if_condition: Is Medium Risk?]
 Legal Review]          │                   │
    │      │           true               false
  true   false          │                   │
    │      │            ▼                   │
    │      │     [wait_approval:            │
    │      │      Procurement Mgr]          │
    │      │       │         │              │
    │      │     true      false            │
    ▼      │      │          │              │
[wait_approval:  │          │              │
 CFO Approval]  │          │              │
    │      │    │          │              │
  true   false  │          ▼              │
    │      └────┼──▶ [gmail_send:         │
    │           │     Rejection]          │
    │           │                         │
    └─────────── ─────────────────────────┘
                              │
                              ▼
                    [call_workflow: Provision Vendor]
                              │
                              ▼
                    (Vendor Provisioning sub-workflow)
                      ├── [http_request: ERP]
                      ├── [gmail_send: Welcome Vendor]
                      └── [gmail_send: Notify Requestor]
```

---

### What happens end-to-end

1. **Procurement team member** logs in and submits the Vendor Registration form.

2. **Immediately**: the three rules evaluate the submission in parallel. The first matching rule fires, enriches the payload with `risk_level`, and calls `trigger_workflow`.

3. **Workflow starts** with the full form submission payload + `risk_level`.

4. **High risk** (financial services vendor, $150k contract):
   - Legal gets an approval email with full context. They have 72 hours.
   - On legal approval, CFO gets an approval email. 48 hours.
   - On CFO approval, provisioning runs.
   - Any rejection along the way sends the requestor a rejection email.

5. **Medium risk** (data-accessing vendor, $40k contract):
   - Procurement manager gets an approval email. 24 hours.
   - On approval, provisioning runs.

6. **Low risk** (no data access, small contract):
   - No human gate — provisioning runs immediately.

7. **Provisioning**:
   - Vendor created in ERP via API call.
   - Welcome email sent to vendor contact.
   - Confirmation email sent to requestor.

8. All approval emails include **Approve** and **Reject** buttons. Clicking either resumes the workflow immediately from where it paused — no polling, no cronjobs, no manual handoffs.

---

### Testing this before going live

1. Submit the form with `vendor_type = "facilities"` and `annual_contract_value = 5000` and `data_access = "no"` → should route as **low risk** → skip all approvals → go straight to provisioning.

2. Submit with `vendor_type = "software"` and `annual_contract_value = 5000` and `data_access = "yes"` → **medium risk** → procurement manager approval email.

3. Submit with `vendor_type = "financial_services"` → **high risk** → legal email first.

4. For approval emails: check your inbox for the approval link, click Approve, watch the Temporal execution resume in Run History.

Use **Run History** on the workflow card to inspect each step's output and confirm the payload is what you expect at each node.
