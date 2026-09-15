# Mit Stack — User Guide: Forms, Rules & Workflows

A practical reference for builders who want to collect data, automate decisions, and orchestrate multi-step processes — no prior platform experience required.

---

## Table of Contents

1. [Platform Overview](#1-platform-overview)
2. [Forms](#2-forms)
   - [Creating a form](#21-creating-a-form)
   - [Field types](#22-field-types)
   - [Conditional logic](#23-conditional-logic)
   - [Validation](#24-validation)
   - [Publishing & embedding](#25-publishing--embedding)
   - [Receiving submissions](#26-receiving-submissions)
3. [Rules](#3-rules)
   - [How rules fit into the platform](#31-how-rules-fit-into-the-platform)
   - [Trigger events](#32-trigger-events)
   - [Rule types](#33-rule-types)
   - [Operators reference](#34-operators-reference)
   - [Actions](#35-actions)
   - [Template expressions](#36-template-expressions)
   - [Lifecycle: draft → published](#37-lifecycle-draft--published)
   - [Decision tables](#38-decision-tables)
   - [JavaScript rules](#39-javascript-rules)
   - [Rule flows](#310-rule-flows)
4. [Workflows](#4-workflows)
   - [Core concepts](#41-core-concepts)
   - [Trigger types](#42-trigger-types)
   - [Node reference](#43-node-reference)
   - [Connecting nodes & branches](#44-connecting-nodes--branches)
   - [Data flow & template interpolation](#45-data-flow--template-interpolation)
   - [Error handling](#46-error-handling)
   - [Credentials](#47-credentials)
   - [Import & export](#48-import--export)
   - [Monitoring executions](#49-monitoring-executions)
5. [Recipes: Putting it all together](#5-recipes-putting-it-all-together)

---

## 1. Platform Overview

Mit Stack has three interlocking automation layers:

| Layer | What it does | Owned by |
|---|---|---|
| **Forms** | Collect structured data from users (internal or public) | Forms builder |
| **Rules** | React to events with conditional logic — no code | Rules engine |
| **Workflows** | Orchestrate multi-step automated processes across systems | Workflow builder |

A typical pattern: a **Form** collects a request → a **Rule** validates and classifies it → a **Workflow** carries out the work (calls an API, sends email, waits for approval, updates a database).

All three share the same **template interpolation syntax** (`{{field.path}}`), the same **credential store**, and the same **trigger/event bus**, so data flows naturally between them.

---

## 2. Forms

Forms are embeddable data-collection pages. They can be kept private (internal use) or made public (external submissions via a shareable URL). Every submission can trigger rules and workflows automatically.

### 2.1 Creating a form

Navigate to **Forms → New Form**.

Every form has:

| Property | Description |
|---|---|
| **Name** | Display name used in the forms list |
| **Slug** | URL-safe identifier — the public URL is `/api/v1/public/forms/{slug}/submit` |
| **Description** | Optional internal note |
| **Fields** | Ordered list of form fields (see §2.2) |
| **Settings** | Submit button label, success message, redirect URL |

The **form builder canvas** lets you drag, drop, and reorder fields. Each field has its own configuration panel on the right.

### 2.2 Field types

#### Text & Input
| Type | Description | Key config |
|---|---|---|
| `text` | Single-line text | placeholder, min/max length |
| `textarea` | Multi-line text | placeholder, rows |
| `number` | Numeric input | min, max, step |
| `currency` | Formatted decimal for money values | currency symbol, decimal places |
| `email` | Email with built-in format validation | — |
| `phone` | Phone number with format validation | — |
| `url` | URL with built-in format validation | — |

#### Date & Time
| Type | Description | Key config |
|---|---|---|
| `date` | Date picker | min date, max date |
| `time` | Time picker | — |
| `datetime` | Combined date + time | min, max |

#### Selection
| Type | Description | Key config |
|---|---|---|
| `select` | Dropdown (single choice) | options list (label + value) |
| `radio` | Radio buttons (single choice) | options list |
| `checkbox` | Single on/off toggle | label |
| `checkbox_group` | Multiple-choice checkboxes | options list |
| `rating` | Star rating | max stars (default 5) |

#### Files & Signatures
| Type | Description | Key config |
|---|---|---|
| `file` | File upload | accepted MIME types, max file size |
| `signature` | Draw-pad for handwritten signature | — |

#### Advanced
| Type | Description | Key config |
|---|---|---|
| `datagrid` | Repeating table — rows added by submitter | column definitions (name, type) |
| `computed` | Read-only field calculated from other fields | expression (supports `{{field_name}}` and arithmetic) |
| `hidden` | Not shown to user; carries a fixed value | default value |

#### Common field properties (all types)
- **Label** — visible field name
- **Field name** — internal key used in payloads and `{{field_name}}` references
- **Required** — whether the field must be filled before submit
- **Placeholder** — hint text shown inside the input
- **Help text** — supporting copy shown below the input
- **Default value** — pre-filled value

### 2.3 Conditional logic

Fields can be shown or hidden based on other fields' values. Three tiers of increasing power:

#### Tier 1 — Simple single condition
Show/hide a field when one other field equals a specific value.

```
Show field "Reason" when field "Status" equals "Rejected"
```

Configure in the field's **Visibility** panel:
- Condition field → select another field
- Operator → one of: equals, not equals, contains, is empty, is not empty
- Value → literal value to compare

#### Tier 2 — Multi-rule with AND/OR
Multiple conditions combined with `AND` or `OR`.

```
Show "Emergency Contact" when
  field "Role" equals "Field Tech"  AND
  field "Assignment Type" equals "Onsite"
```

Add conditions using **+ Add condition** in the Visibility panel; choose whether the group uses `AND` or `OR`.

#### Tier 3 — Expression
A JavaScript-like expression evaluated at runtime. Field names are available as variables.

```js
Status === "Active" && Budget > 50000
```

This is the most powerful tier — supports arithmetic, string methods, and nested logic.

### 2.4 Validation

Beyond built-in type validation, each field supports custom rules:

| Rule | Description |
|---|---|
| `min_length` | Minimum character count (text, textarea) |
| `max_length` | Maximum character count |
| `min` | Minimum value (number, currency, date) |
| `max` | Maximum value |
| `pattern` | Regular expression the value must match |
| `required_if` | Mark required only when another field has a value |
| `custom_message` | Override the default error message |

Validation runs client-side before submit and server-side at the API layer. Submissions that fail server-side validation return `HTTP 422` with field-level error details.

### 2.5 Publishing & embedding

Toggle a form's **Public** switch in the forms list to make it accessible without authentication.

Once public, the submission URL is:
```
POST /api/v1/public/forms/{slug}/submit
Content-Type: application/json

{
  "field_name_1": "value",
  "field_name_2": 42,
  ...
}
```

Copy the URL using the **link icon** on the form card in the list.

You can embed forms in external pages or call the endpoint from any HTTP client. No API key is required for public forms.

Private forms require a valid session JWT and are submitted to the same endpoint with an `Authorization: Bearer {token}` header.

### 2.6 Receiving submissions

Every submission:

1. Is persisted in the database with a unique submission ID.
2. **Triggers any Rules** whose trigger event is `form_submit` and whose `form_id` filter matches this form.
3. **Triggers any Workflows** that have trigger type `form_submit` and whose `form_slug` config matches.

The submission payload is made available as the rule/workflow input:
```json
{
  "form_id": "uuid",
  "form_slug": "my-form",
  "submission_id": "uuid",
  "submitted_at": "2026-04-27T10:00:00Z",
  "data": {
    "field_name_1": "value",
    "field_name_2": 42
  }
}
```

Reference form fields in downstream rules and workflows as `{{data.field_name}}`.

---

## 3. Rules

Rules are conditional automations that react to platform events. They evaluate without running full workflows, making them ideal for lightweight, event-driven logic like sending a notification, tagging a record, or blocking a process.

### 3.1 How rules fit into the platform

```
Event occurs (form submit, webhook, schedule, ...)
       ↓
Rules engine evaluates all published rules for that event type
       ↓
Matching rules execute their actions
       ↓
Actions can trigger workflows, send emails, or enrich data
```

Rules execute in parallel with workflows triggered by the same event — they are not mutually exclusive.

### 3.2 Trigger events

| Event | Fires when | Payload |
|---|---|---|
| `form_submit` | A form is submitted | Form submission data incl. `form_id`, `data.*` |
| `workflow_complete` | A workflow run finishes successfully | `workflow_id`, `execution_id`, output data |
| `workflow_fail` | A workflow run fails | `workflow_id`, `execution_id`, `error` |
| `webhook` | External system POSTs to the rule's webhook URL | Raw JSON body |
| `schedule` | A cron schedule fires | `triggered_at`, schedule details |
| `manual` | Triggered explicitly via API or the Rules UI | Optional `input` payload |
| `imap_trigger` | A new email arrives in a monitored mailbox | Email fields: `from`, `subject`, `body`, `attachments` |

A rule can listen to **multiple** trigger events simultaneously.

### 3.3 Rule types

#### Condition tree (visual, recommended for most use cases)
A tree of conditions connected by `AND` / `OR` with a flat list of actions that fire when the root evaluates to `true`.

Use when:
- You need straightforward if/then logic
- Non-technical team members will maintain the rule
- Conditions draw from a consistent payload shape

#### Decision table
A spreadsheet-style table where each row is an independent condition → action mapping. Rows are evaluated top to bottom.

Hit policies control how many rows fire:

| Policy | Behaviour |
|---|---|
| `first` | Stop after the first matching row |
| `all` | Execute every matching row |
| `unique` | Like `all` but errors if two rows match (for mutually-exclusive tables) |
| `collect` | Collect all matching row outputs into an array |

Use when:
- You have many combinations (product pricing, routing, classification)
- The logic lives in a table that domain experts can edit in a spreadsheet-like UI

#### JavaScript rule
A single JavaScript function evaluated at runtime. Full JS available including array methods, string manipulation, and arithmetic.

```js
// The input payload is available as `data`
// Return true to fire actions, false to skip

if (data.total_amount > 10000 && data.region === "EMEA") {
  return true;
}
return data.priority === "critical";
```

Use when:
- Logic is complex, conditional, or requires computation
- You need to derive a value before deciding (e.g. calculate a discount then check a threshold)

### 3.4 Operators reference

Available in condition tree rules:

| Operator | Types | Description |
|---|---|---|
| `equals` | any | Strict equality |
| `not_equals` | any | Strict inequality |
| `greater_than` | number, date | `>` |
| `greater_than_or_equal` | number, date | `>=` |
| `less_than` | number, date | `<` |
| `less_than_or_equal` | number, date | `<=` |
| `contains` | string, array | Substring or array-includes |
| `not_contains` | string, array | Negated contains |
| `starts_with` | string | String prefix |
| `ends_with` | string | String suffix |
| `in` | any | Value is in a comma-separated list |
| `not_in` | any | Value is not in a list |
| `is_empty` | any | null, empty string, or empty array |
| `is_not_empty` | any | Negated empty |
| `matches_regex` | string | Regular expression |
| `between` | number, date | Inclusive range (requires `min` and `max`) |
| `is_true` | boolean | Value is truthy |
| `is_false` | boolean | Value is falsy |
| `before` | date | Date comparison |
| `after` | date | Date comparison |
| `array_length_gt` | array | Array has more than N items |
| `array_length_lt` | array | Array has fewer than N items |
| `all_of` | array | Every array item matches a sub-condition |
| `any_of` | array | At least one array item matches a sub-condition |

### 3.5 Actions

When a rule matches, it executes its action list in order. Actions can be stopped mid-way using `stop_processing`.

| Action | Description | Config |
|---|---|---|
| `trigger_workflow` | Start a workflow run | `workflow_id`, optional `input` payload |
| `send_email` | Send an email (uses platform SMTP or credential) | `to`, `subject`, `body` — all support `{{field}}` |
| `send_webhook` | POST JSON to an external URL | `url`, `payload` (JSON, supports `{{field}}`), `headers` |
| `set_field` | Enrich the event payload with a new field | `field_name`, `value` (supports expressions) |
| `add_tag` | Attach a tag to a record | `tag` |
| `stop_processing` | Halt remaining actions in this rule (and optionally further rules) | — |

Actions within a single rule execute sequentially. Multiple rules matching the same event execute in parallel.

### 3.6 Template expressions

All text fields in actions support `{{field.path}}` interpolation. The payload available depends on the trigger:

```
{{data.email}}             → form field "email"
{{data.items[0].price}}    → first item's price in array
{{submission_id}}          → submission UUID
{{triggered_at}}           → ISO timestamp
```

**Arithmetic expressions** are supported inside `{{...}}`:
```
{{data.price * 1.1}}                    → price + 10%
{{data.quantity * data.unit_price}}     → computed total
{{data.name + " (pending)"}}`           → string concatenation
```

The expression engine also supports:
- Ternary: `{{data.status === "vip" ? "Priority" : "Standard"}}`
- Conditional: `{{data.amount > 1000 ? "high-value" : "standard"}}`

### 3.7 Lifecycle: draft → published

Every rule starts in **Draft** state and must be published before it evaluates live events.

```
Draft → (save) → Draft
Draft → (publish) → Published
Published → (edit) → Draft (new version in progress)
Published → (deactivate) → Inactive
Inactive → (reactivate) → Published
```

Publishing a rule:
1. Click **Publish** in the rule editor.
2. If an approval workflow is configured (optional), the rule enters **Pending Approval** state.
3. Once approved (or if no approval required), the rule activates immediately.

**Version history**: every published version is stored. You can view past versions, compare changes, and roll back to a previous version from the rule's **History** tab.

**Audit log**: every activation, deactivation, publish, and approval action is recorded with the acting user and timestamp.

### 3.8 Decision tables

A decision table is a matrix where columns are conditions and the final columns are actions.

**Structure:**
```
| order_total | customer_tier | region   | → discount | → priority_flag |
|-------------|---------------|----------|------------|-----------------|
| > 10000     | "gold"        | *        | 15%        | true            |
| > 5000      | *             | "EMEA"   | 10%        | false           |
| *           | *             | *        | 5%         | false           |  ← default row
```

`*` means "match any value". Conditions use the same operators from §3.4.

**Output columns** hold action configurations. With `collect` hit policy, all matching rows fire and their outputs are available as an array to downstream rules/workflows.

**Creating a decision table:**
1. Choose rule type **Decision Table**
2. Add condition columns — each maps to a field path in the incoming payload
3. Add output columns — each maps to an action (or an enrichment field)
4. Add rows, one per scenario
5. Set the hit policy
6. Publish

### 3.9 JavaScript rules

The JS engine receives:
- `data` — the full event payload
- `context` — metadata (`org_id`, `triggered_at`, `rule_id`)
- `helpers` — utility functions: `helpers.formatDate(d)`, `helpers.round(n, places)`

Return `true` to fire actions, `false` or `undefined` to skip.

```js
// Example: Complex discount routing
const total = data.line_items.reduce((sum, item) => sum + item.price * item.qty, 0);
const isRepeatCustomer = data.customer.order_count > 3;
const isBigOrder = total > 5000;

return isRepeatCustomer && isBigOrder;
```

The rule actions still configure what happens when `true` is returned — the JS only controls whether the rule fires.

### 3.10 Rule flows

Rule flows are visual sequences of multiple rules that share the same trigger. They let you chain rules explicitly, passing enriched data between them.

A flow node is one of:
- **Rule** — evaluate a named rule and pass its enriched payload forward
- **Branch** — split the flow based on a condition
- **Join** — recombine parallel branches

Use flows for complex orchestrations that need to share state across multiple rules without reaching for a full workflow.

---

## 4. Workflows

Workflows orchestrate multi-step automated processes. They run on Temporal, which means they are durable — a 24-hour approval wait is a first-class operation, not a timer hack.

### 4.1 Core concepts

| Concept | Meaning |
|---|---|
| **Node** | A single step — an action, a trigger, or a control-flow operation |
| **Edge** | A connection from one node to another |
| **Branch** | An edge with a condition label (`"true"`, `"false"`, `"switch_{label}"`) |
| **Execution** | One run of a workflow, initiated by a trigger |
| **Definition** | JSON describing the node/edge graph — saved and versioned on each update |

A workflow is a directed acyclic graph (DAG). Every execution starts at the trigger node and follows edges forward until no more nodes remain.

### 4.2 Trigger types

Set the trigger when creating or editing a workflow. The trigger determines how the workflow starts.

#### Manual
The simplest option. Run the workflow from the UI or API:
```
POST /workflows/{workflow_id}/execute
Body: {"key": "any input data"}
```

#### Webhook
The workflow runs when an external system POSTs to:
```
POST /webhooks/{org_slug}/{workflow_id}
```
Configure a **webhook secret** to validate the `X-Mit-Signature` HMAC header (format: `sha256={hex_digest}`). If no secret is set, any POST triggers the workflow.

Trigger config:
```json
{ "path": "/my-hook", "method": "POST" }
```

#### Cron
The workflow runs on a schedule. Use standard 5-field cron syntax (UTC).

```
0 9 * * 1-5      → every weekday at 09:00 UTC
*/15 * * * *     → every 15 minutes
0 0 1 * *        → first of every month at midnight
```

Trigger config: `{ "cron": "0 9 * * 1-5" }`

#### Form submit
The workflow runs automatically when a specific form is submitted.

Trigger config:
```json
{ "form_slug": "my-onboarding-form", "form_id": "optional-uuid" }
```

The full form submission payload (see §2.6) is passed as workflow input.

#### IMAP (email)
The workflow runs when a new email arrives in a monitored mailbox.

Trigger config:
```json
{
  "credential_id": "imap-credential-uuid",
  "folder": "INBOX",
  "poll_cron": "*/5 * * * *",
  "mark_as_read": true,
  "max_emails_per_poll": 10
}
```

Email input payload:
```json
{
  "from": "sender@example.com",
  "to": "inbox@mycompany.com",
  "subject": "...",
  "body": "...",
  "date": "2026-04-27T10:00:00Z",
  "attachments": [{ "filename": "...", "content_type": "...", "data": "base64..." }]
}
```

### 4.3 Node reference

#### TRIGGERS

##### `manual_trigger`
No configuration. Used as the start node for manually-run or API-triggered workflows.

##### `webhook_trigger`
Receives external HTTP calls. Configured at the workflow level (see §4.2).

##### `cron_trigger`
Schedule-based. Configured at the workflow level.

##### `form_trigger`
Fires when a form is submitted. Config: `form_slug`, optional `form_id`.

##### `imap_trigger`
Fires when email arrives. Config: credential + poll settings (see §4.2).

---

#### ACTIONS

##### `http_request` — HTTP Request
Call any external API.

| Field | Description |
|---|---|
| `url` | Full URL — supports `{{interpolation}}` |
| `method` | `GET`, `POST`, `PUT`, `PATCH`, `DELETE` |
| `body` | JSON body (for POST/PUT/PATCH) |
| `credential_id` | Optional stored credential (adds auth headers automatically) |
| `timeout_minutes` | Timeout in minutes (default: 5) |
| `continue_on_error` | If `true`, treat errors as non-fatal |

Output: the parsed JSON response body (or raw text).

##### `web_scraper` — Web Scraper
Extract data from a webpage using CSS selectors.

| Field | Description |
|---|---|
| `url` | Page URL to scrape |
| `selectors` | JSON array: `[{"name": "price", "css": ".price-tag"}]` |
| `session_id` | Optional session for authenticated scraping |
| `continue_on_error` | Non-fatal on scrape failure |

Output: `{ "price": "...", ... }` — one key per named selector.

##### `db_query` — DB Query
Run a parameterised SQL query against a connected database.

| Field | Description |
|---|---|
| `sql` | SQL SELECT statement — use `$1`, `$2` for parameters |
| `credential_id` | Database credential (PostgreSQL) |

Output: array of row objects.

##### `run_code` — Code
Execute a Python snippet in a sandbox.

| Field | Description |
|---|---|
| `code` | Python code. Input available as `data`. Set `result = {...}` to produce output. |
| `language` | `python` (only supported language currently) |
| `continue_on_error` | Non-fatal on exception |

```python
# Example: calculate tax
tax_rate = 0.13
total = data["subtotal"] * (1 + tax_rate)
result = {"total": total, "tax": data["subtotal"] * tax_rate}
```

Output: the `result` variable.

##### `delay` — Delay
Pause the workflow for a fixed number of seconds.

| Field | Description |
|---|---|
| `seconds` | How long to pause |

The workflow is suspended (not polling) during the delay. No resources consumed.

---

#### LOGIC

##### `if_condition` — If / Else
Branch based on a condition expression.

| Field | Description |
|---|---|
| `expression` | JS-like expression evaluated against current payload |
| `continue_on_error` | Treat evaluation errors as `false` |

Connect two outgoing edges:
- Label `"true"` → path taken when condition matches
- Label `"false"` → path taken when condition does not match

```
expression: data.amount > 1000 && data.status === "approved"
```

##### `switch` — Switch
Multi-way branch based on a value.

| Field | Description |
|---|---|
| `expression` | Expression that produces a value |
| `cases` | JSON array: `[{"value": "A", "label": "case_a"}, ...]` |
| `default_case` | Label for the fallthrough edge |

Connect outgoing edges with labels `"switch_{case_label}"` for each case, plus `"switch_{default_case}"` for the default.

##### `for_each` — For Each
Run a sub-workflow for each item in an array.

| Field | Description |
|---|---|
| `items_path` | Dot-path to the array in the current payload (`"data.items"`) |
| `body_nodes` | JSON node list for the inner loop body |
| `body_edges` | JSON edge list for the inner loop body |
| `continue_on_error` | Don't stop if one item fails |

Each iteration receives: `{ ...current_input, item: <item_value>, _index: <n> }`.

Output: `{ "results": [...], "count": N }` — one result per iteration.

##### `merge` — Merge
Rejoin parallel branches.

| Field | Description |
|---|---|
| `mode` | How to combine: `merge`, `append`, `first`, or `last` |

| Mode | Output |
|---|---|
| `merge` | `Object.assign` all live branch outputs (last wins on key conflict) |
| `append` | `{ "items": [output1, output2, ...] }` |
| `first` | First live branch output only |
| `last` | Last live branch output only |

##### `transform` — Transform
Reshape data using a query expression.

| Field | Description |
|---|---|
| `expression` | Query string |
| `engine` | `jmespath`, `jsonpath`, or `python` |

JMESPath example: `data.items[?status == 'active'].name`

##### `evaluate_rules` — Evaluate Rules
Run all published rules matching an event type against the current payload.

| Field | Description |
|---|---|
| `event_type` | Which rules to evaluate (e.g., `form_submit`) |
| `dry_run` | If `true`, evaluate but don't fire rule actions |

Output: current payload enriched with:
- `_rule_results` — map of rule ID → result
- `_rules_matched` — list of rule IDs that matched

---

#### APPROVAL

##### `wait_approval` — Wait for Approval
Suspend workflow until a human approves or rejects. The workflow state is preserved indefinitely.

| Field | Description |
|---|---|
| `approver_email` | Who receives the approval request email |
| `prompt` | Instructions shown to the approver |
| `label` | Short label for this approval step |
| `timeout_hours` | Reject automatically after N hours (0 = wait forever) |
| `continue_on_error` | Non-fatal on timeout |

The approver receives an email with **Approve** and **Reject** links. Clicking either resumes the workflow.

Connect two outgoing edges:
- `"true"` → approved path
- `"false"` → rejected or timed-out path

##### `call_workflow` — Call Workflow
Invoke another workflow as a sub-workflow and wait for it to complete.

| Field | Description |
|---|---|
| `sub_workflow_id` | UUID of the workflow to call |
| `timeout_hours` | Maximum wait time |
| `continue_on_error` | Non-fatal if sub-workflow fails |

Output: the sub-workflow's final output.

---

#### EMAIL

All email nodes require an appropriate credential (`credential_id`).

##### `send_email` — SMTP Email
Send via a configured SMTP credential.

| Field | Description |
|---|---|
| `to` | Recipient address — supports `{{field}}` |
| `subject` | Email subject — supports `{{field}}` |
| `body` | Plain-text body — supports `{{field}}` |
| `credential_id` | SMTP credential |

##### `gmail_send` — Gmail Send
Send via a Gmail OAuth account.

| Field | Description | Notes |
|---|---|---|
| `to` | Recipient | `{{field}}` supported |
| `subject` | Subject | `{{field}}` supported |
| `body` | Plain-text body | |
| `body_html` | HTML body | |
| `cc`, `bcc` | CC/BCC addresses | |
| `credential_id` | Gmail OAuth credential | |

##### `gmail_read` — Gmail Read
Read emails from a Gmail inbox.

| Field | Description |
|---|---|
| `query` | Gmail search syntax (`from:alice@example.com`, `subject:Invoice`, `is:unread`) |
| `max_results` | Maximum messages to return |
| `mark_as_read` | Mark fetched messages as read |
| `credential_id` | Gmail OAuth credential |

Output: array of message objects — `{ message_id, thread_id, from, subject, snippet, date, body }`.

##### `outlook_send` — Outlook Send
Send via a Microsoft 365 account.

| Field | Description |
|---|---|
| `to`, `subject`, `body`, `body_html`, `cc` | Same as Gmail |
| `save_to_sent` | Save to Sent Items (default: true) |
| `credential_id` | Microsoft OAuth credential |

##### `outlook_read` — Outlook Read
Read from a Microsoft 365 mailbox.

| Field | Description |
|---|---|
| `folder` | Folder name (`Inbox`, `Sent Items`, etc.) |
| `filter_query` | OData filter (`isRead eq false`, `receivedDateTime gt 2026-04-01`) |
| `max_results` | Max messages |
| `mark_as_read` | Mark as read after fetch |
| `credential_id` | Microsoft OAuth credential |

---

#### STORAGE

##### `s3` — AWS S3

| Field | Description |
|---|---|
| `operation` | `upload`, `download`, `list`, `delete`, `get_url` |
| `bucket` | S3 bucket name |
| `key` | Object key (file path) |
| `body` | Base64-encoded content (upload only) |
| `content_type` | MIME type (upload) |
| `region` | AWS region (e.g., `us-east-1`) |
| `credential_id` | AWS credential |

##### `google_drive` — Google Drive

| Field | Description |
|---|---|
| `operation` | `upload`, `download`, `list`, `delete`, `get_link` |
| `file_id` | Drive file ID (for operations on existing files) |
| `file_name` | Filename for upload |
| `folder_id` | Parent folder ID |
| `mime_type` | MIME type for upload |
| `body` | Base64-encoded content (upload) |
| `query` | Drive query string for list (`name contains 'Invoice'`) |
| `credential_id` | Google OAuth credential |

---

#### SPREADSHEETS

##### `excel_read` — Excel Read
Parse an .xlsx file.

| Field | Description |
|---|---|
| `file_base64` | Base64-encoded .xlsx content |
| `sheet_name` | Sheet name (default: first sheet) |
| `has_header` | First row is a header row |
| `max_rows` | Limit rows read |

Output: array of row objects (when `has_header=true`) or arrays.

##### `excel_write` — Excel Write
Generate an .xlsx file from data.

| Field | Description |
|---|---|
| `sheet_name` | Sheet name |
| `include_header` | Add a header row |

Input must include a `rows` array. Output: base64-encoded .xlsx.

---

#### AI

##### `agent_node` — Run Agent
Invoke a configured AI agent (LLM + system prompt + skills).

| Field | Description |
|---|---|
| `agent_id` | UUID of the `AIAgentConfig` record |
| `input` | Input text or JSON passed to the agent |

The agent resolves its model, system prompt, and skills from the registry. Output: agent text response.

> See the AI Admin section for how to create and manage agents.

##### `agent_graph_node` — Agent Graph
Orchestrate multiple AI agents in a mini-DAG (max depth: 3).

| Field | Description |
|---|---|
| `spec` | JSON graph spec (entry node, list of agent nodes with `next` and optional `branch`) |
| `input` | Initial input |

Spec format:
```json
{
  "entry": "classifier",
  "nodes": [
    {
      "id": "classifier",
      "agent_id": "uuid-of-classifier-agent",
      "next": ["summarizer", "tagger"],
      "branch": "intent==summary"
    },
    {
      "id": "summarizer",
      "agent_id": "uuid-of-summarizer-agent",
      "next": []
    },
    {
      "id": "tagger",
      "agent_id": "uuid-of-tagger-agent",
      "next": []
    }
  ]
}
```

##### `claude_llm` — Claude AI (legacy)
Direct Claude API call without the agent registry. Prefer `agent_node` for new workflows.

| Field | Description |
|---|---|
| `prompt` | User prompt — supports `{{field}}` |
| `system_prompt` | System instructions |
| `model` | Claude model name |
| `max_tokens` | Maximum tokens in response |
| `temperature` | Sampling temperature (0–1) |
| `credential_id` | Anthropic API credential |

---

#### PAYMENTS

##### `stripe` — Stripe
Call any Stripe API endpoint.

| Field | Description |
|---|---|
| `endpoint` | Stripe API path (e.g., `/v1/charges`, `/v1/customers/{id}`) |
| `method` | `GET`, `POST`, `PUT`, `DELETE` |
| `data` | JSON request body |
| `credential_id` | Stripe API key credential |

Output: Stripe API response object.

---

#### MARKETING

##### `mailchimp` — Mailchimp
Manage subscribers in Mailchimp.

| Field | Description |
|---|---|
| `operation` | `subscribe`, `update`, `archive`, `get_member`, `add_tag` |
| `list_id` | Mailchimp audience ID |
| `email` | Member email address — supports `{{field}}` |
| `merge_fields` | JSON map of Mailchimp merge fields (`{"FNAME": "Alice"}`) |
| `tags` | JSON array of tag strings |
| `credential_id` | Mailchimp API credential |

---

### 4.4 Connecting nodes & branches

**Draw an edge**: in the workflow canvas, hover a node to reveal its output port (right side). Drag from the port to another node's input port (left side).

**Default edges** (no label): the downstream node runs whenever the upstream node succeeds or produces any non-error status.

**Conditional edges**: after drawing an edge, click it to set a branch label.

| Label | When to use |
|---|---|
| `"true"` | `if_condition` or `wait_approval` — approved/matched path |
| `"false"` | `if_condition` or `wait_approval` — rejected/unmatched path |
| `"success"` | Only run the next node if the previous one succeeded |
| `"error"` | Error-handler path — only runs if previous node failed |
| `"switch_{label}"` | `switch` node — one edge per case, using the case label |

**Parallel branches**: draw edges from one node to multiple downstream nodes. Both branches execute concurrently. Use a `merge` node to rejoin them.

**Skipping**: if all incoming edges to a node are "dead" (their upstream node produced a non-matching status), the node is skipped entirely.

### 4.5 Data flow & template interpolation

Data flows **forward** through the graph. Each node receives the output of its parent as input.

**Trigger nodes** pass the trigger payload (webhook body, form submission, etc.) as the initial input.

**Regular nodes** pass their own output as the input to their children.

**Merge nodes** combine multiple parent outputs per the configured mode.

**Template syntax** is available in almost every text config field:

```
{{data.email}}               → payload path
{{data.items[0].price}}      → array element
{{data.user.name}}           → nested object
{{data.amount * 1.13}}       → arithmetic
{{data.status == "vip" ? "Priority" : "Standard"}}  → ternary
```

Template evaluation happens at execution time, so you can reference the output of any earlier node by its field path.

**In `for_each` body nodes**, the special variables are available:
```
{{item}}          → current array element
{{item.field}}    → field inside current element
{{_index}}        → current iteration index (0-based)
```

### 4.6 Error handling

By default, if a node fails (network error, timeout, exception), the entire workflow execution fails.

**Options to change this:**

1. **`continue_on_error: true`** — the node records an error but the workflow continues, treating the node output as empty / `{}`.

2. **Error edges** — draw an edge from a node with branch label `"error"`. This is only traversed if the node fails. Use it to run a notification or cleanup node before the workflow ends.

3. **`call_workflow` timeout** — sub-workflows that exceed `timeout_hours` fail their calling node; `continue_on_error` applies.

**Approval timeouts**: if `wait_approval` times out and no action is taken, the edge labelled `"false"` (rejection) is followed if present; otherwise the node fails.

### 4.7 Credentials

Nodes that call external services need a **credential** — a stored API key, OAuth token, or connection string. Credentials are managed under **Settings → Integrations**.

When configuring a node, select the credential from the `credential_id` dropdown. The runtime looks up the credential at execution time and injects it — your workflow definition never stores raw secrets.

Credential types:
- **API Key** — for HTTP requests, Stripe, Mailchimp
- **Gmail OAuth** — for `gmail_send` / `gmail_read`
- **Microsoft OAuth** — for `outlook_send` / `outlook_read`
- **Google OAuth** — for `google_drive`
- **AWS** — for `s3` (access key + secret)
- **SMTP** — for `send_email`
- **PostgreSQL** — for `db_query`
- **IMAP** — for `imap_trigger`

### 4.8 Import & export

**Export**: click the three-dot menu on any workflow card → **Export**. This downloads a `.workflow.json` file containing the full definition (without IDs or secrets).

**Import**: on the Workflows list page, click **Import** and upload a `.workflow.json` file. A new workflow is created with fresh IDs — any referenced credential IDs will need to be re-selected.

Export format:
```json
{
  "mit_stack_export_version": "1.0",
  "name": "My Workflow",
  "description": "...",
  "trigger_type": "webhook",
  "trigger_config": { "method": "POST" },
  "definition": { "nodes": [...], "edges": [...] }
}
```

### 4.9 Monitoring executions

**Execution list**: from the workflow card → **Run History**. Each entry shows:
- Execution ID (first 8 chars shown)
- Status: `pending`, `running`, `completed`, `failed`
- Started at / completed at
- Node-level output (click an execution to inspect each node's output)

**Run now**: on any active workflow card, click **Run** (▶ icon) to trigger a manual execution immediately. The input can be provided via API.

**Temporal UI**: for deep debugging, the Temporal web UI is accessible at port 8088 (or as configured). Search by temporal workflow ID to see the full execution trace including retries and activity logs.

---

## 5. Recipes: Putting it all together

### Recipe A — Contact form with email notification

**Goal**: Visitor submits a "Contact Us" form; you receive an email notification and the submission is logged.

1. **Build the form**
   - Create a form: Name=`Contact Us`, Slug=`contact`
   - Add fields: `name` (text, required), `email` (email, required), `message` (textarea, required)
   - Publish (make public)

2. **Create a workflow**
   - Trigger type: `form_submit`
   - Trigger config: `{ "form_slug": "contact" }`
   - Add a `send_email` node:
     - `to`: your address
     - `subject`: `New contact from {{data.name}}`
     - `body`: `From: {{data.email}}\n\n{{data.message}}`
   - Activate the workflow

Submissions to `/api/v1/public/forms/contact/submit` will immediately trigger the email.

---

### Recipe B — Purchase order approval

**Goal**: When a PO form is submitted over $10,000, route to manager approval before processing.

1. **Build the form** with fields: `vendor`, `amount` (currency), `description`

2. **Create a rule** (condition tree):
   - Trigger: `form_submit`
   - Condition: `data.amount > 10000`
   - Action: `trigger_workflow` → the approval workflow

3. **Build the approval workflow**:
   - Trigger: `manual` (called by the rule)
   - Node 1 — `wait_approval`:
     - `approver_email`: `{{data.manager_email}}`
     - `prompt`: `PO from {{data.vendor}} for ${{data.amount}} is awaiting approval`
     - `timeout_hours`: 48
   - Node 2 (true branch) — `http_request` → ERP system
   - Node 3 (false branch) — `send_email` → notify submitter of rejection

---

### Recipe C — Weekly report from database

**Goal**: Every Monday at 9am, query the database, generate a report, and email it.

1. **Create a workflow**
   - Trigger type: `cron`
   - Trigger config: `{ "cron": "0 9 * * 1" }`

2. **Add nodes**:
   - `db_query` → `SELECT vendor, SUM(amount) FROM purchase_orders WHERE created_at > NOW() - INTERVAL '7 days' GROUP BY vendor`
   - `run_code` → format the results into a summary string
     ```python
     lines = [f"{row['vendor']}: ${row['sum']:.2f}" for row in data["rows"]]
     result = {"summary": "\n".join(lines)}
     ```
   - `send_email` → `to`: `finance@mycompany.com`, `body`: `{{summary}}`

---

### Recipe D — Email-to-Slack bridge with AI triage

**Goal**: New emails to your support inbox are classified by AI and routed to the correct Slack channel via webhook.

1. **Create a workflow**
   - Trigger type: `imap_trigger`
   - Trigger config: `{ "credential_id": "imap-cred", "folder": "INBOX", "poll_cron": "*/5 * * * *" }`

2. **Add nodes**:
   - `agent_node` → AI agent that classifies `{{subject}} {{body}}` into `billing`, `technical`, or `general`
   - `switch` → `expression: data.category`
     - `case billing` → `http_request` → Slack `#billing` webhook
     - `case technical` → `http_request` → Slack `#support-tech` webhook
     - `default` → `http_request` → Slack `#support-general` webhook

---

### Recipe E — Decision table for lead scoring

**Goal**: Incoming lead form submissions get scored based on company size and industry.

1. **Build a rule** — Decision table:
   - Conditions: `data.company_size` (number), `data.industry` (string)
   - Output columns: `score` (number), `tier` (string)

| company_size | industry | → score | → tier |
|---|---|---|---|
| > 500 | "Financial Services" | 100 | "Enterprise" |
| > 500 | * | 80 | "Enterprise" |
| between 50 and 499 | * | 60 | "Mid-Market" |
| * | * | 30 | "SMB" |

   - Hit policy: `first`

2. **Trigger the rule** from a form submission:
   - Rule trigger: `form_submit`, `form_id` = your lead form

3. **The rule enriches the payload** with `score` and `tier` fields that downstream workflows can use.

---

### Reference: Common payload paths

| Context | Path | Value |
|---|---|---|
| Form submission | `data.{field_name}` | The submitted field value |
| Form submission | `submission_id` | UUID of the submission |
| Form submission | `form_slug` | Form slug |
| Email trigger | `from` | Sender address |
| Email trigger | `subject` | Email subject |
| Email trigger | `body` | Email body text |
| For-each iteration | `item` | Current array element |
| For-each iteration | `_index` | Current index (0-based) |
| Rule results | `_rules_matched` | List of rule IDs that fired |
| Rule results | `_rule_results.{rule_id}` | Per-rule output |
