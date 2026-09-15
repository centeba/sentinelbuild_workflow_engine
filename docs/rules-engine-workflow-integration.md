# Rules Engine — Workflow Integration

## Overview

The rules engine integrates into the workflow as a standard node type (`evaluate_rules`). It reads the current workflow execution context, evaluates configured business rules, fires any matched actions (email, webhook, sub-workflow), and returns the enriched state to the next node in the DAG.

---

## Integration Points

### 1. `evaluate_rules` node in `workflow_executor.py`

When a workflow DAG contains an `evaluate_rules` node, the executor dispatches it like any other node:

```python
case "evaluate_rules":
    result = await workflow.execute_activity(
        evaluate_rules,
        EvaluateRulesParams(
            event_type=node_config["event_type"],
            event_data=execution_context,   # entire workflow state
            org_id=org_id,
            dry_run=node_config.get("dry_run", False),
        ),
        start_to_close_timeout=timedelta(seconds=30),
    )
```

The full workflow execution context is passed as `event_data`, so every variable produced by prior nodes is available for rule conditions to match against.

### 2. `rule_engine_activity.py` — Temporal activity

A thin adapter between Temporal and the engine service (`temporal/activities/rule_engine_activity.py`):

```python
@activity.defn
async def evaluate_rules(params: EvaluateRulesParams) -> dict[str, Any]:
    async with AsyncSessionLocal() as db:
        results = await process_event(
            params.event_type, params.event_data, params.org_id, db, params.dry_run
        )
    enriched = dict(params.event_data)
    enriched["_rule_results"] = results        # list of per-rule outcomes
    enriched["_rules_matched"] = len(results)  # count
    return enriched
```

Results are **merged back into the event data** before returning. The next node in the DAG receives the original workflow state plus `_rule_results` and `_rules_matched`, allowing downstream nodes to branch on how many rules fired or inspect which actions were taken.

### 3. `process_event()` in `api/services/rule_engine.py`

The core engine (~400 lines). Execution flow:

| Step | What happens |
|------|-------------|
| **1. Cache lookup** | Rules for the org fetched from Redis (`get_cached_rules`); TTL defaults to 300 s. DB is the fallback. |
| **2. Filter by `event_type`** | Only rules whose `trigger_filter.event_type` matches are considered. |
| **3. Sort by priority** | Rules execute in descending priority order. |
| **4. `trigger_filter` pre-check** | Lightweight field comparison before evaluating the full condition tree. |
| **5. Condition evaluation** | One of three modes per rule (see below). |
| **6. Action execution** | For each matched rule, actions fire in order (see below). |
| **7. Audit log** | Every rule evaluation (match or no-match) writes a `RuleAuditLog` row to the DB. |
| **8. Return** | Returns `_rule_results` — a list of dicts, one per rule that fired. |

---

## Condition Evaluation Modes

Each rule uses one of three evaluation strategies:

### Condition Tree
Recursive AND/OR/NOT groups with leaf comparisons.

Supported operators: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `between`, `contains`, `not_contains`, `starts_with`, `ends_with`, `regex`, `is_null`, `is_not_null`, plus date operators (`date_before`, `date_after`, `date_equals`).

Field paths use dot-notation (e.g. `order.customer.email`).

### Decision Table
Rows of input conditions mapped to output values. Hit policies:

| Policy | Behaviour |
|--------|-----------|
| `first` | Stop on the first matching row |
| `collect_all` | Collect outputs from all matching rows |
| `any_match` | Return true if any row matches |
| `unique` | Enforce that at most one row matches |

### JavaScript
Arbitrary JS executed via `dukpy` (Duktape sandbox). Hard timeout of 2 s (configurable via `JS_TIMEOUT_MS`). The event data dict is injected as `event`.

---

## Action Types

Actions fire in declaration order for each matched rule:

| Action | What it does |
|--------|-------------|
| `trigger_workflow` | Kicks off another Temporal workflow |
| `send_email` | Sends email via SMTP activity |
| `send_webhook` | Outbound HTTP POST; 10 s timeout (configurable via `WEBHOOK_ACTION_TIMEOUT_SECONDS`) |
| `set_field` | Mutates a key in the event data dict; visible to downstream nodes |
| `add_tag` | Appends a string to `_tags` list in event data |
| `stop_processing` | Halts further rule evaluation for this event (equivalent to `break`) |

---

## Data Flow

```
Workflow node "evaluate_rules"
        │
        ▼
evaluate_rules Temporal activity
        │  opens async DB session
        ▼
process_event(event_type, execution_context, org_id)
        │  Redis cache → filter → sort → trigger_filter
        │  → evaluate conditions → execute actions → write audit log
        ▼
returns enriched dict:
  { ...original execution context...,
    _rule_results: [ { rule_id, matched, actions_taken }, ... ],
    _rules_matched: N }
        │
        ▼
Next workflow node
  (can branch on _rules_matched, inspect _rule_results,
   or read any fields mutated by set_field actions)
```

---

## Key Files

| File | Role |
|------|------|
| `backend/temporal/activities/rule_engine_activity.py` | Temporal activity; bridges workflow executor → engine service |
| `backend/api/services/rule_engine.py` | Core engine: condition evaluation, action execution, audit logging |
| `backend/temporal/workflows/workflow_executor.py` | Dispatches `evaluate_rules` node type |
| `backend/api/models/rule.py` | ORM models: `Rule`, `RuleAuditLog` |
| `backend/api/crud/rules.py` | DB queries + Redis cache management |

---

## Configuration

| Env var | Default | Purpose |
|---------|---------|---------|
| `RULE_CACHE_TTL` | `300` | Redis cache TTL in seconds for rule sets |
| `JS_TIMEOUT_MS` | `2000` | Max execution time for JavaScript rules |
| `WEBHOOK_ACTION_TIMEOUT_SECONDS` | `10.0` | HTTP timeout for `send_webhook` actions |
