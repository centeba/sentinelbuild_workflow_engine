"""
Rule Engine Service

Evaluates stored rules against event data and executes matched actions.
Rules are evaluated in priority order (lower number = higher priority).

Changes in this version:
  Gap 1  — Redis rule cache via rule_cache.get_cached_rules()
  Gap 2  — `between` operator  (value = "min,max")
  Gap 5  — correlation_id passed through to RuleAuditLog
  Gap 7  — Decision table evaluation
"""

import ast as _ast
import operator
import re
import time
import uuid
from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from api.constants import RULE_TYPE_DECISION_TABLE, RULE_TYPE_JAVASCRIPT
from shared.config import get_settings

# ─── Field access ─────────────────────────────────────────────────────────────


def _get_field(data: dict[str, Any], field_path: str) -> Any:
    """Dot-notation field access. 'data.email' → data['data']['email']"""
    val: Any = data
    for part in field_path.split("."):
        if isinstance(val, dict):
            val = val.get(part)
        else:
            return None
    return val


def _coerce_numeric(a: Any, b: Any) -> tuple[float, float] | None:
    try:
        return float(a), float(b)
    except (TypeError, ValueError):
        return None


# ─── Date helpers ──────────────────────────────────────────────────────────────


def _parse_date(val: Any) -> datetime | None:
    """Parse anything date-like into an aware UTC datetime."""
    if isinstance(val, datetime):
        return val if val.tzinfo else val.replace(tzinfo=UTC)
    try:
        dt = datetime.fromisoformat(str(val))
        return dt if dt.tzinfo else dt.replace(tzinfo=UTC)
    except (ValueError, TypeError):
        return None


# ─── Safe arithmetic evaluator ────────────────────────────────────────────────

_SAFE_OPS: dict[type[_ast.AST], Callable[..., Any]] = {
    _ast.Add: operator.add,
    _ast.Sub: operator.sub,
    _ast.Mult: operator.mul,
    _ast.Div: operator.truediv,
    _ast.FloorDiv: operator.floordiv,
    _ast.Mod: operator.mod,
    _ast.Pow: operator.pow,
    _ast.USub: operator.neg,
    _ast.UAdd: operator.pos,
}
_SAFE_FUNCS: dict[str, Callable[..., Any]] = {
    "round": round,
    "abs": abs,
    "min": min,
    "max": max,
    "int": int,
    "float": float,
    "len": len,
}


def _safe_ast_eval(node: _ast.AST, ctx: dict[str, Any]) -> Any:
    match node:
        case _ast.Constant():
            return node.value
        case _ast.Name() if node.id in ctx:
            return ctx[node.id]
        case _ast.BinOp():
            op_fn = _SAFE_OPS.get(type(node.op))
            if op_fn is None:
                raise ValueError(f"Unsupported binary op: {type(node.op)}")
            return op_fn(
                _safe_ast_eval(node.left, ctx), _safe_ast_eval(node.right, ctx)
            )
        case _ast.UnaryOp():
            op_fn = _SAFE_OPS.get(type(node.op))
            if op_fn is None:
                raise ValueError(f"Unsupported unary op: {type(node.op)}")
            return op_fn(_safe_ast_eval(node.operand, ctx))
        case _ast.Call() if (
            isinstance(node.func, _ast.Name) and node.func.id in _SAFE_FUNCS
        ):
            args = [_safe_ast_eval(a, ctx) for a in node.args]
            return _SAFE_FUNCS[node.func.id](*args)
        case _:
            raise ValueError(f"Unsafe AST node: {type(node).__name__}")


_CALC_OPS_RE = re.compile(r"[+\-*/%]")
_IDENTIFIER_RE = re.compile(r"[a-zA-Z_][a-zA-Z0-9_.]*")


def _eval_calc(expr: str, data: dict[str, Any]) -> str:
    """Evaluate a safe arithmetic expression string with field-path substitution."""

    def _repl_path(m: re.Match[str]) -> str:
        v = _get_field(data, m.group(0))
        try:
            return str(float(v)) if v is not None else "0"
        except (TypeError, ValueError):
            return f'"{v}"'

    resolved = _IDENTIFIER_RE.sub(_repl_path, expr)
    try:
        tree = _ast.parse(resolved, mode="eval")
        result = _safe_ast_eval(tree.body, {})
        return str(round(result, 10) if isinstance(result, float) else result)
    except Exception:
        return resolved


# ─── Condition evaluation ─────────────────────────────────────────────────────


def _eval_leaf(data: dict[str, Any], rule: dict[str, Any]) -> bool:
    """Evaluate a single leaf condition."""
    field = rule.get("field", "")
    op = rule.get("operator", "eq")
    ref = rule.get("value", "")
    actual = _get_field(data, field)
    actual_str = str(actual) if actual is not None else ""

    match op:
        case "eq":
            return actual_str == str(ref)
        case "neq":
            return actual_str != str(ref)
        case "contains":
            return str(ref) in actual_str
        case "not_contains":
            return str(ref) not in actual_str
        case "starts_with":
            return actual_str.startswith(str(ref))
        case "ends_with":
            return actual_str.endswith(str(ref))
        case "gt":
            nums = _coerce_numeric(actual, ref)
            return nums[0] > nums[1] if nums else False
        case "gte":
            nums = _coerce_numeric(actual, ref)
            return nums[0] >= nums[1] if nums else False
        case "lt":
            nums = _coerce_numeric(actual, ref)
            return nums[0] < nums[1] if nums else False
        case "lte":
            nums = _coerce_numeric(actual, ref)
            return nums[0] <= nums[1] if nums else False
        case "in":
            options = (
                ref
                if isinstance(ref, list)
                else [s.strip() for s in str(ref).split(",")]
            )
            return actual_str in [str(o) for o in options]
        case "not_in":
            options = (
                ref
                if isinstance(ref, list)
                else [s.strip() for s in str(ref).split(",")]
            )
            return actual_str not in [str(o) for o in options]
        # Gap 2: between operator — ref format "min,max"
        case "between":
            try:
                parts = str(ref).split(",", 1)
                lo, hi = float(parts[0].strip()), float(parts[1].strip())
                v = float(actual)
                return lo <= v <= hi
            except (TypeError, ValueError, IndexError):
                return False
        case "is_empty":
            return actual is None or actual_str.strip() == ""
        case "is_not_empty":
            return actual is not None and actual_str.strip() != ""
        case "matches_regex":
            try:
                return bool(re.search(str(ref), actual_str))
            except re.error:
                return False
        case "is_true":
            return actual_str.lower() in ("true", "1", "yes")
        case "is_false":
            return actual_str.lower() in ("false", "0", "no", "")
        case "date_before":
            a, b = _parse_date(actual), _parse_date(ref)
            return a < b if a and b else False
        case "date_after":
            a, b = _parse_date(actual), _parse_date(ref)
            return a > b if a and b else False
        case "date_equals":
            a, b = _parse_date(actual), _parse_date(ref)
            return a.date() == b.date() if a and b else False
        case "within_last_n_days":
            a = _parse_date(actual)
            if not a:
                return False
            try:
                return (datetime.now(UTC) - a).days <= int(ref)
            except (TypeError, ValueError):
                return False
        case "older_than_n_days":
            a = _parse_date(actual)
            if not a:
                return False
            try:
                return (datetime.now(UTC) - a).days > int(ref)
            except (TypeError, ValueError):
                return False
        case _:
            return False


def evaluate_condition_group(
    data: dict[str, Any], group: dict[str, Any] | None
) -> bool:
    """
    Recursively evaluate a condition group tree.

    Empty/None group → always True (no restrictions).
    """
    if not group or not group.get("rules"):
        return True

    combinator = group.get("combinator", "and").lower()
    results = []
    for rule in group["rules"]:
        if "combinator" in rule:
            results.append(evaluate_condition_group(data, rule))
        else:
            results.append(_eval_leaf(data, rule))

    if combinator == "or":
        return any(results)
    if combinator == "not":
        return not results[0] if results else True
    return all(results)


# ─── Decision table evaluation (Gap 7) ────────────────────────────────────────


def _eval_dt_row(
    data: dict[str, Any], input_cols: list[dict[str, Any]], row: dict[str, Any]
) -> bool:
    """Return True if all input conditions in a decision table row match."""
    for col, cond in zip(input_cols, row.get("conditions", [])):
        op = cond.get("operator", "eq")
        if op == "ANY":
            continue
        leaf = {
            "field": col.get("field", ""),
            "operator": op,
            "value": cond.get("value", ""),
        }
        if not _eval_leaf(data, leaf):
            return False
    return True


def _dt_row_to_actions(
    output_cols: list[dict[str, Any]], row: dict[str, Any], data: dict[str, Any]
) -> list[dict[str, Any]]:
    """Convert a matching decision table row to set_field actions."""
    return [
        {
            "type": "set_field",
            "field": col.get("field", ""),
            "value": _interp(str(output.get("value", "")), data),
        }
        for col, output in zip(output_cols, row.get("outputs", []))
    ]


def evaluate_decision_table(
    data: dict[str, Any], table: dict[str, Any]
) -> tuple[bool, list[dict[str, Any]]]:
    """
    Evaluate a decision table against event_data.

    Gap 14: supports hit_policy in the table dict:
      - "first"       (default): stop at first matching row
      - "collect_all": all matching rows, actions merged in order
      - "any_match":  return True/False only (no output actions)
      - "unique":     all matching rows, but raise ValueError if any output field
                      is produced by more than one row (use for conflict detection)

    Returns (matched: bool, set_field_actions: list[dict]).
    Operator "ANY" in a cell is a wildcard that always passes.
    """
    input_cols = table.get("input_columns", [])
    output_cols = table.get("output_columns", [])
    rows = table.get("rows", [])
    hit_policy = table.get("hit_policy", "first")

    if hit_policy == "first":
        for row in rows:
            if _eval_dt_row(data, input_cols, row):
                return True, _dt_row_to_actions(output_cols, row, data)
        return False, []

    elif hit_policy == "collect_all":
        all_actions: list[dict[str, Any]] = []
        matched_any = False
        for row in rows:
            if _eval_dt_row(data, input_cols, row):
                matched_any = True
                all_actions.extend(_dt_row_to_actions(output_cols, row, data))
        return matched_any, all_actions

    elif hit_policy == "any_match":
        for row in rows:
            if _eval_dt_row(data, input_cols, row):
                return True, []
        return False, []

    elif hit_policy == "unique":
        # Collect all matches; error if same output field produced by multiple rows
        matches: list[list[dict[str, Any]]] = []
        for row in rows:
            if _eval_dt_row(data, input_cols, row):
                matches.append(_dt_row_to_actions(output_cols, row, data))
        if not matches:
            return False, []
        # Flatten and check uniqueness per output field
        seen_fields: set[str] = set()
        merged: list[dict[str, Any]] = []
        for row_actions in matches:
            for action in row_actions:
                field = action.get("field", "")
                if field in seen_fields:
                    # Conflict — return first match only with a warning flag
                    return True, [
                        {
                            "type": "error",
                            "message": f"unique hit policy: field '{field}' matched multiple rows",
                        }
                    ]
                seen_fields.add(field)
                merged.append(action)
        return True, merged

    # Unknown hit_policy: fall back to first
    for row in rows:
        if _eval_dt_row(data, input_cols, row):
            return True, _dt_row_to_actions(output_cols, row, data)
    return False, []


# ─── Interpolation ────────────────────────────────────────────────────────────


def _interp(template: str, data: dict[str, Any]) -> str:
    """
    {{field.path}} → value from data dict.
    {{price * 0.9}} → safe arithmetic with field substitution.
    """

    def _replace(m: re.Match[str]) -> str:
        expr = m.group(1).strip()
        if _CALC_OPS_RE.search(expr):
            return _eval_calc(expr, data)
        val = _get_field(data, expr)
        return str(val) if val is not None else ""

    return re.sub(r"\{\{(.+?)\}\}", _replace, str(template))


# ─── Action execution ─────────────────────────────────────────────────────────


async def execute_action(
    action: dict[str, Any], event_data: dict[str, Any], org_id: str, db: AsyncSession
) -> dict[str, Any]:
    """Execute a single action and return a result dict."""
    action_type = action.get("type", "")

    match action_type:
        case "trigger_workflow":
            workflow_id = action.get("workflow_id", "")
            if not workflow_id:
                return {
                    "status": "error",
                    "message": "trigger_workflow: missing workflow_id",
                }
            try:
                from sqlalchemy import select

                from api.models.workflow import Workflow
                from api.services.workflow_service import trigger_workflow

                res = await db.execute(
                    select(Workflow).where(
                        Workflow.id == uuid.UUID(workflow_id),
                        Workflow.org_id == uuid.UUID(org_id),
                        Workflow.is_active.is_(True),
                    )
                )
                wf = res.scalar_one_or_none()
                if not wf:
                    return {
                        "status": "error",
                        "message": f"Workflow {workflow_id} not found or inactive",
                    }
                execution = await trigger_workflow(
                    db, wf, event_data, trigger_type="rule_engine"
                )
                return {
                    "status": "ok",
                    "type": "trigger_workflow",
                    "execution_id": str(execution.id),
                }
            except Exception as exc:
                return {"status": "error", "message": str(exc)}

        case "send_email":
            return {
                "status": "queued",
                "type": "send_email",
                "to": _interp(action.get("to", ""), event_data),
                "subject": _interp(action.get("subject", ""), event_data),
                "body_preview": _interp(action.get("body", ""), event_data)[:100],
            }

        case "send_webhook":
            url = _interp(action.get("url", ""), event_data)
            method = action.get("method", "POST").upper()
            headers = action.get("headers", {})
            try:
                async with httpx.AsyncClient(
                    timeout=get_settings().webhook_action_timeout_seconds
                ) as client:
                    resp = await client.request(
                        method, url, json=event_data, headers=headers
                    )
                    return {
                        "status": "ok",
                        "type": "send_webhook",
                        "url": url,
                        "http_status": resp.status_code,
                    }
            except Exception as exc:
                return {
                    "status": "error",
                    "type": "send_webhook",
                    "url": url,
                    "message": str(exc),
                }

        case "set_field":
            field = action.get("field", "")
            value = _interp(str(action.get("value", "")), event_data)
            _set_nested(event_data, field, value)
            return {"status": "ok", "type": "set_field", "field": field, "value": value}

        case "add_tag":
            tag = _interp(str(action.get("tag", "")), event_data)
            tags: list[Any] = event_data.setdefault("_tags", [])
            if tag not in tags:
                tags.append(tag)
            return {"status": "ok", "type": "add_tag", "tag": tag}

        case "stop_processing":
            return {"status": "ok", "type": "stop_processing", "_halt": True}

        case _:
            return {
                "status": "error",
                "message": f"Unknown action type: {action_type!r}",
            }


def _set_nested(data: dict[str, Any], field_path: str, value: Any) -> None:
    """Set a dot-notation field on a dict, creating intermediary dicts as needed."""
    parts = field_path.split(".")
    target = data
    for part in parts[:-1]:
        target = target.setdefault(part, {})
    target[parts[-1]] = value


def _preview_actions(
    actions: list[dict[str, Any]], event_data: dict[str, Any]
) -> list[dict[str, Any]]:
    """Build a dry-run preview of actions (no side effects)."""
    return [
        {
            "type": a.get("type"),
            "preview": {
                k: _interp(str(v), event_data) for k, v in a.items() if k != "type"
            },
        }
        for a in actions
    ]


# ─── Main entry point ─────────────────────────────────────────────────────────


async def process_event(
    event_type: str,
    event_data: dict[str, Any],
    org_id: str,
    db: AsyncSession,
    dry_run: bool = False,
    correlation_id: str | None = None,
) -> list[dict[str, Any]]:
    """
    Load all published+active rules for the org matching event_type (from cache),
    evaluate conditions in priority order, and execute actions.

    Returns a list of result dicts (one per matched or else-path rule).
    Audit rows are written for every rule evaluated unless dry_run=True.
    """
    # Gap 1: use Redis cache instead of raw DB query
    from api.services.rule_cache import get_cached_rules

    all_rules = await get_cached_rules(org_id, db)

    # Filter in Python — cache holds ALL published+active rules for the org
    rules = [r for r in all_rules if event_type in (r.get("trigger_events") or [])]
    # Sort by priority ascending (cache preserves insertion order but be explicit)
    rules.sort(key=lambda r: r.get("priority", 100))

    matched: list[dict[str, Any]] = []

    for rule in rules:
        t_start = time.monotonic()

        # Apply trigger_filter pre-check
        tf = rule.get("trigger_filter") or {}
        if tf:
            flat = {**event_data, **(event_data.get("data", {}) or {})}
            if not all(flat.get(k) == v for k, v in tf.items()):
                continue

        rule_type = rule.get("rule_type", "condition_tree")
        cond_match: bool
        override_actions: list[dict[str, Any]] | None = (
            None  # used by decision_table / javascript
        )
        js_output_data: dict[str, Any] = {}

        if rule_type == RULE_TYPE_DECISION_TABLE:
            # Gap 7: decision table evaluation (Gap 14: hit policies)
            cond_match, override_actions = evaluate_decision_table(
                event_data, rule.get("conditions") or {}
            )
        elif rule_type == RULE_TYPE_JAVASCRIPT:
            # Gap 11: scripted JavaScript rule
            from api.services.js_engine import evaluate_js_rule

            js_code = (rule.get("conditions") or {}).get("code", "")
            cond_match, js_output_data = evaluate_js_rule(js_code, event_data)
            # JS may also specify override_actions via conditions.actions list
            js_action_override = (rule.get("conditions") or {}).get("actions")
            if cond_match and js_action_override:
                override_actions = js_action_override
        else:
            cond_match = evaluate_condition_group(
                event_data, rule.get("conditions") or {}
            )

        rule_result: dict[str, Any] = {
            "rule_id": rule["id"],
            "rule_name": rule["name"],
            "priority": rule.get("priority", 100),
            "matched": cond_match,
            "path": "then" if cond_match else "else",
            "rule_type": rule_type,
            "actions_executed": [],
        }

        # Merge JS output data into event_data before executing actions
        if js_output_data:
            for k, v in js_output_data.items():
                _set_nested(event_data, k, v)

        if (
            rule_type in (RULE_TYPE_DECISION_TABLE, RULE_TYPE_JAVASCRIPT)
            and override_actions is not None
        ):
            # Decision table / JS with explicit action override
            actions_to_run = override_actions
        elif rule_type == RULE_TYPE_JAVASCRIPT and override_actions is None:
            # JS rule with no explicit actions — run the rule's actions list on match
            actions_to_run = (
                (rule.get("actions") or [])
                if cond_match
                else (rule.get("else_actions") or [])
            )
        else:
            actions_to_run = (
                (rule.get("actions") or [])
                if cond_match
                else (rule.get("else_actions") or [])
            )

        halt = False
        for action in actions_to_run:
            if dry_run:
                rule_result["actions_executed"].append(
                    {
                        "type": action.get("type"),
                        "preview": {
                            k: _interp(str(v), event_data)
                            for k, v in action.items()
                            if k != "type"
                        },
                    }
                )
            else:
                action_result = await execute_action(action, event_data, org_id, db)
                rule_result["actions_executed"].append(action_result)
                if action_result.get("_halt") or (
                    cond_match and rule.get("stop_on_match")
                ):
                    halt = True
                    break

        elapsed_ms = int((time.monotonic() - t_start) * 1000)
        rule_result["elapsed_ms"] = elapsed_ms

        # Gap 5: write audit row with correlation_id (skip on dry-run)
        if not dry_run:
            from api.models.rule_audit import RuleAuditLog

            audit = RuleAuditLog(
                rule_id=uuid.UUID(rule["id"]),
                org_id=uuid.UUID(org_id),
                rule_name=rule["name"],
                event_type=event_type,
                matched=cond_match,
                event_data=event_data,
                actions_executed=rule_result["actions_executed"],
                elapsed_ms=elapsed_ms,
                correlation_id=correlation_id,
            )
            db.add(audit)

        if cond_match or actions_to_run:
            matched.append(rule_result)

        if halt:
            break

    return matched
