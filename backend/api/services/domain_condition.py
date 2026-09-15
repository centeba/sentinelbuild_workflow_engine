"""Evaluate a structured domain-condition group against fetched entity data.

A domain condition is the same AND/OR/NOT tree the rule engine uses, but each
leaf carries ``domain``/``entity`` metadata identifying *which live object* its
``field`` reads from::

    {"combinator": "and", "rules": [
        {"domain": "restoration", "entity": "document",
         "field": "document_type_key", "operator": "eq", "value": "work_authorization"},
        {"domain": "restoration", "entity": "project",
         "field": "current_phase", "operator": "eq", "value": "mitigation"}]}

The actual operator logic is reused from ``rule_engine._eval_leaf`` (eq / in /
gt / contains / date_* / …) — this module only routes each leaf to the right
fetched entity and applies "any item matches" semantics for list (cardinality
``many``) entities. The fetching itself happens in the Temporal activity; this
function is pure/sync so it's trivially unit-testable.
"""

from typing import Any

from api.services.rule_engine import _eval_leaf


def referenced_entities(group: dict[str, Any] | None) -> set[str]:
    """Distinct entity keys referenced by the group's leaves."""
    out: set[str] = set()

    def _walk(g: dict[str, Any] | None) -> None:
        if not isinstance(g, dict):
            return
        for r in g.get("rules") or []:
            if isinstance(r, dict) and "combinator" in r:
                _walk(r)
            elif isinstance(r, dict):
                e = r.get("entity")
                if e:
                    out.add(str(e))

    _walk(group)
    return out


def _eval_leaf_on_entity(leaf: dict[str, Any], fetched: dict[str, Any]) -> bool:
    entity = str(leaf.get("entity") or "")
    rule = {
        "field": leaf.get("field"),
        "operator": leaf.get("operator"),
        "value": leaf.get("value"),
    }
    data = fetched.get(entity)
    if data is None:
        # Entity couldn't be fetched / not found → evaluate against empty so the
        # leaf doesn't spuriously match (e.g. eq → False, is_empty → True).
        return _eval_leaf({}, rule)
    if isinstance(data, list):
        # Cardinality "many": the condition holds if ANY item matches.
        if not data:
            return _eval_leaf({}, rule)
        return any(
            _eval_leaf(item if isinstance(item, dict) else {}, rule) for item in data
        )
    if isinstance(data, dict):
        return _eval_leaf(data, rule)
    return _eval_leaf({}, rule)


def evaluate_group(group: dict[str, Any] | None, fetched: dict[str, Any]) -> bool:
    """Recursively evaluate the condition group against ``fetched`` entity data
    (``{entity_key: dict | list}``). Empty/None group → True (no restriction)."""
    if not group or not group.get("rules"):
        return True
    combinator = (group.get("combinator") or "and").lower()
    results: list[bool] = []
    for r in group["rules"]:
        if isinstance(r, dict) and "combinator" in r:
            results.append(evaluate_group(r, fetched))
        elif isinstance(r, dict):
            results.append(_eval_leaf_on_entity(r, fetched))
    if combinator == "or":
        return any(results)
    if combinator == "not":
        return (not results[0]) if results else True
    return all(results)
