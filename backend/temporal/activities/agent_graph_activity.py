"""Phase E2 — execute a multi-agent graph from a workflow ``agent_graph_node``.

A workflow's ``agent_graph_node`` carries an ``AgentGraphSpec`` JSON
(entry node + DAG of agent IDs with branch predicates) plus an
interpolated ``input`` string. This activity round-trips the call to
integration-hub's ``POST /api/v1/ai-invoke/run-graph`` endpoint, where
the smart-llm ``orchestrator`` module validates the spec (cycle
detection, ``MAX_DEPTH=3`` cost guardrail) and dispatches each agent in
parallel/sequence.

Mirrors :mod:`agent_activity` (Phase B) — same auth path
(``INTERNAL_SERVICE_SECRET`` bearer), same tenant forwarding, same
RuntimeError → Temporal-failure shape so the standard retry policy
applies. The timeout default is higher (300s vs 120s) because a depth=3
graph can fire up to ~13 LLM calls (1 entry + 3 children + 9
grandchildren).
"""

from dataclasses import dataclass, field
from typing import Any, cast

import httpx
from temporalio import activity

from shared.config import get_settings


@dataclass
class AgentGraphParams:
    spec: dict[str, Any] = field(default_factory=dict)  # AgentGraphSpec JSON
    input_text: str = ""  # interpolated user input
    org_id: str = ""  # workflow tenant
    context: str | None = None
    timeout_seconds: int = 300  # depth=3 graphs can take a while


@activity.defn
async def run_agent_graph_node(params: AgentGraphParams) -> dict[str, Any]:
    """POST to integration-hub ``/ai-invoke/run-graph`` and return the
    merged result payload from the graph's leaf nodes. Errors surface
    as Temporal activity failures so the workflow's retry policy
    applies."""
    settings = get_settings()
    if not settings.integration_hub_url:
        raise RuntimeError("INTEGRATION_HUB_URL is not configured")
    if not settings.internal_service_secret:
        raise RuntimeError(
            "INTERNAL_SERVICE_SECRET is not configured — required for "
            "worker calls to integration-hub /ai-invoke/run-graph."
        )

    url = f"{settings.integration_hub_url.rstrip('/')}/api/v1/ai-invoke/run-graph"

    async with httpx.AsyncClient(timeout=params.timeout_seconds) as client:
        resp = await client.post(
            url,
            headers={
                "Authorization": f"Bearer {settings.internal_service_secret}",
                "Content-Type": "application/json",
            },
            json={
                "spec": params.spec,
                "input": params.input_text,
                "context": params.context,
                "company_id": params.org_id or None,
            },
        )
        if resp.status_code >= 400:
            # Echo the integration-hub error body so workflow run
            # history shows useful detail (cycle detected, depth
            # exceeded, missing agent_id, etc.).
            raise RuntimeError(
                f"agent_graph_node failed (HTTP {resp.status_code}): {resp.text}"
            )
        return cast(dict[str, Any], resp.json())
