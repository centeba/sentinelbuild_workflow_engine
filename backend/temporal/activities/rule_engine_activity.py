"""
Temporal activity: evaluate_rules

Used as a workflow node type "evaluate_rules". Loads and evaluates
stored rules for a given event type against the node's input data.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from temporalio import activity


@dataclass
class EvaluateRulesParams:
    event_type: str
    event_data: dict[str, Any]
    org_id: str
    dry_run: bool = False


@activity.defn
async def evaluate_rules(params: EvaluateRulesParams) -> dict[str, Any]:
    """
    Evaluate all active rules for the org matching event_type.
    Returns merged event_data enriched by any set_field/add_tag actions,
    plus a _rule_results list with per-rule outcomes.
    """
    from api.services.rule_engine import process_event
    from shared.db import AsyncSessionLocal

    async with AsyncSessionLocal() as db:
        async with db.begin():
            results = await process_event(
                event_type=params.event_type,
                event_data=dict(params.event_data),
                org_id=params.org_id,
                db=db,
                dry_run=params.dry_run,
            )

    enriched = dict(params.event_data)
    enriched["_rule_results"] = results
    enriched["_rules_matched"] = len(results)
    return enriched
