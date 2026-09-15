# Mit Stack — Two Worked Examples

This is a hands-on walkthrough of the platform. By the end you will
have:

1. **Example 1** — an Order Approval workflow that asks a rule "is
   this a high-value order?" and branches accordingly.
2. **Example 2** — a public Support Ticket form whose urgent
   submissions automatically page on-call via a rule.

Each step lists the exact button to click and the exact text to
type. If you would rather skip the clicking, run the seed script
described at the end.

> **Note on email.** `send_email` enqueues messages through the
> internal dispatcher; in the default development setup nothing is
> actually delivered to a mail server. The "send email" steps below
> still produce a workflow execution row you can inspect — just
> assume the recipient never sees the message until SMTP is wired up
> for your environment.

---

## Concepts (60-second tour)

| Concept | What it is |
|---|---|
| **Workflow** | A DAG of nodes (`Manual Trigger → HTTP → Send Email`). Runs once per trigger. |
| **Rule** | A policy: *when this event happens, if these conditions hold, do these actions*. Lives in the **Rules** screen. |
| **Form** | A public web form that, on submit, fires a `form_submit` event. Optionally also runs a workflow. |
| **Event** | A small JSON payload with an `event_type` (`order.received`, `form_submit`, …) routed through the rule engine. |
| **Automation Category** | Optional taxonomy bucket for rules and workflows. Manage in **Settings → Automation Category**. |

The **Evaluate Rules** node (under the *Automate* group in the
workflow palette) is how a workflow asks the rule engine "tell me
which rules matched this event." Decision tables are not a separate
node — they are a *rule type* (`decision_table`) authored on the
Rules screen.

---

## Example 1 — Use a rule inside a workflow

**Story.** When an order arrives, classify it as "high value" or
not, and route the approval email to the right team.

### Step 1 — Create the rule

Sidebar → **Rules** → **+ New Rule**.

| Field | Value |
|---|---|
| Name | `High-value order classifier` |
| Status | `published` |
| Active | on |
| Priority | `10` |
| Trigger events | `order.received` |
| Rule type | `condition_tree` |
| Conditions | `data.amount` `>` `1000` |
| Actions | `add_tag` → `high_value` |

Click **Save**. The rule appears in the table with a "1 condition
(and)" summary and "1 action(s)".

### Step 2 — Create the workflow

Sidebar → **Workflows** → **+ New Workflow**.

| Field | Value |
|---|---|
| Name | `Order Approval Routing` |
| Trigger | `manual` |

In the canvas, drag in five nodes and wire them like this:

```
[Manual Trigger] → [Evaluate Rules] → [If Condition] ─true──→ [Send Email: approver]
                                                  └─false──→ [Send Email: ops]
```

Node-by-node config:

- **Evaluate Rules**
  - `event_type = order.received`
  - `dry_run = false`

- **If Condition**
  - `expression = data['_rules_matched'] > 0`
  - **Why this expression?** The rule engine returns
    `_rules_matched` (the count of rules that fired) on the output
    payload. Tag/field mutations made by rule actions are dropped
    at the activity boundary, so we branch on the match count, not
    on the tag itself.

- **Send Email: approver**
  - To: `approver@example.com`
  - Subject: `High-value order needs approval`
  - Body: `Order {{data.order_id}} for ${{data.amount}}`

- **Send Email: ops**
  - To: `ops@example.com`
  - Subject: `Order auto-approved`
  - Body: `Order {{data.order_id}} processed.`

Click **Save**, then **Publish**.

### Step 3 — Run it

Open the workflow → **Run** with input
`{"order_id": "O-1", "amount": 1500}`. The execution graph lights
up the **approver** branch.

Re-run with `{"order_id": "O-2", "amount": 50}`. The **ops** branch
lights up instead.

---

## Example 2 — Form → Rule → Workflow

**Story.** A public Support Ticket form. Every submission is
stored. Urgent submissions also page on-call by triggering a pager
workflow.

### Step 1 — Create the pager workflow

Sidebar → **Workflows** → **+ New Workflow**.

| Field | Value |
|---|---|
| Name | `Urgent Support Pager` |
| Trigger | `manual` |

Two nodes: `[Manual Trigger] → [Send Email: oncall]`.

| Email field | Value |
|---|---|
| To | `oncall@example.com` |
| Subject | `URGENT support ticket from {{data.email}}` |
| Body | `Priority: {{data.priority}}\n\n{{data.description}}` |

**Save**, **Publish**, then copy the workflow's UUID from the
workflows list — you will paste it into the rule next.

### Step 2 — Create the routing rule

Sidebar → **Rules** → **+ New Rule**.

| Field | Value |
|---|---|
| Name | `Urgent support routing` |
| Status | `published` |
| Trigger events | `form_submit` |
| Trigger filter | `form_slug = support-ticket` |
| Conditions | `data.priority` `==` `urgent` |
| Actions | `trigger_workflow` → *(paste pager workflow UUID)* |

### Step 3 — Create the form

Sidebar → **Forms** → **+ New Form**.

| Field | Value |
|---|---|
| Name | `Support Ticket` |
| Public | ✓ |
| Slug | `support-ticket` |
| Linked workflow | *(leave empty — the rule does the linking)* |

Fields:

| Field key | Type | Notes |
|---|---|---|
| `email` | text | required |
| `priority` | select | options: `low / normal / urgent` |
| `description` | textarea | |

The form's public URL appears at the top of the form builder:
`http://<host>/forms/support-ticket`.

### Step 4 — Submit and verify

From an incognito window, open the public URL. Submit twice — once
with `priority = urgent`, once with `priority = low`.

Back in the admin UI:

- **Forms → Support Ticket → Submissions** lists both rows.
- **Rules → Urgent support routing → Audit** shows one match
  (the urgent submission).
- **Workflows → Urgent Support Pager → Executions** shows one run
  (also the urgent one). The low-priority submission is just
  stored, no rule match.

---

## How it fits together

```
┌────────────┐   form_submit   ┌────────────┐
│ Public     │ ───────────────▶│ Rule       │
│ Form       │                 │ Engine     │
└────────────┘                 └─────┬──────┘
                                     │ trigger_workflow action
                                     ▼
                               ┌────────────┐
                               │ Workflow   │
                               │ Engine     │
                               └─────┬──────┘
                                     │
                                     ▼
                                Side effects
                              (emails, HTTP, …)
```

Rules and workflows are independently composable. A workflow can
call rules (Example 1, via the **Evaluate Rules** node). Rules can
trigger workflows (Example 2, via the `trigger_workflow` action).
Forms emit `form_submit` events that rules listen to.

---

## Appendix — JSON shapes saved to the DB

For users who want to drive the platform via API rather than the
UI, here is what each row looks like once saved:

### Rule (Example 1)

```json
{
  "name": "High-value order classifier",
  "status": "published",
  "is_active": true,
  "priority": 10,
  "rule_type": "condition_tree",
  "trigger_events": ["order.received"],
  "trigger_filter": {},
  "conditions": {
    "combinator": "and",
    "rules": [
      {"field": "data.amount", "operator": "gt", "value": 1000}
    ]
  },
  "actions": [
    {"type": "add_tag", "tag": "high_value"}
  ]
}
```

### Workflow definition (Example 1, abridged)

```json
{
  "trigger_type": "manual",
  "definition": {
    "nodes": [
      {"id": "n1", "type": "manual_trigger"},
      {"id": "n2", "type": "evaluate_rules",
       "config": {"event_type": "order.received", "dry_run": false}},
      {"id": "n3", "type": "if_condition",
       "config": {"expression": "data['_rules_matched'] > 0"}},
      {"id": "n4", "type": "send_email",
       "config": {"to": "approver@example.com", "subject": "...", "body": "..."}},
      {"id": "n5", "type": "send_email",
       "config": {"to": "ops@example.com",      "subject": "...", "body": "..."}}
    ],
    "edges": [
      {"from": "n1", "to": "n2"},
      {"from": "n2", "to": "n3"},
      {"from": "n3", "to": "n4", "condition": "true"},
      {"from": "n3", "to": "n5", "condition": "false"}
    ]
  }
}
```

### Rule (Example 2)

```json
{
  "name": "Urgent support routing",
  "status": "published",
  "trigger_events": ["form_submit"],
  "trigger_filter": {"form_slug": "support-ticket"},
  "conditions": {
    "combinator": "and",
    "rules": [
      {"field": "data.priority", "operator": "eq", "value": "urgent"}
    ]
  },
  "actions": [
    {"type": "trigger_workflow", "workflow_id": "<PAGER_UUID>"}
  ]
}
```

---

## Skipping the clicks: seed script

If you want to recreate everything in one shot (or after a wipe),
run the idempotent seeder:

```bash
cd backend
python -m scripts.seed_examples
```

It uses fixed UUIDs for upserts, so re-runs are no-ops. Output:

```
[ok] org      11111111-…  "Demo org"
[ok] rule     22222222-…  "High-value order classifier"
[ok] workflow 33333333-…  "Order Approval Routing"
[ok] workflow 44444444-…  "Urgent Support Pager"
[ok] rule     55555555-…  "Urgent support routing"
[ok] form     66666666-…  "Support Ticket"  (public URL: /forms/support-ticket)
```

After it finishes, re-open the UI — both examples are ready to run.
