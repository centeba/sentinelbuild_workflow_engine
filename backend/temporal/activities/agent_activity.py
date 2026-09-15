"""Phase B — execute a configured AI agent from a workflow ``agent_node``.

A workflow's ``agent_node`` carries an ``agent_id`` (UUID of an
``AIAgentConfig`` row) plus an interpolated ``prompt``. This activity
round-trips the call to integration-hub's ``POST /api/v1/ai-invoke/run``
endpoint, where the smart-llm runtime loads the agent's configured
provider, model, system prompt, and attached skills, then executes
``Agent.run_with_skills``.

Auth: the worker sends ``Authorization: Bearer ${INTERNAL_SERVICE_SECRET}``
— the same raw shared-secret string used by ``action_activity``.
Verified by integration-hub's ``InternalServiceDep`` / ``AnyAuthDep``.
This replaces the previous approach (now deleted) of minting a forged
``role=system_admin`` JWT, which was a security smell.

``company_id`` is forwarded as the workflow run's ``org_id`` so the
agent is loaded under the correct tenant.
"""

from dataclasses import dataclass
from typing import Any, cast

import httpx
from temporalio import activity

from shared.config import get_settings


@dataclass
class AgentParams:
    # Exactly one of agent_id / agent_name identifies the agent. ``agent_id``
    # is a per-company AIAgentConfig UUID; ``agent_name`` is the portable
    # qualified name (e.g. ``restoration:project_summary``) that integration-
    # hub's /ai-invoke/run also accepts — preferred for seed workflows that
    # ship before per-company agent UUIDs exist.
    agent_id: str | None = None
    agent_name: str | None = None
    prompt: str = ""  # interpolated user input
    org_id: str = ""  # workflow tenant — forwarded as body company_id
    context: str | None = None
    timeout_seconds: int = 120  # agents are slower than tools (LLM calls + skills)


@activity.defn
async def run_agent_node(params: AgentParams) -> dict[str, Any]:
    """POST to integration-hub ``/ai-invoke/run`` and return the result
    payload. Errors are surfaced as Temporal activity failures so the
    standard retry policy applies."""
    settings = get_settings()
    if not settings.integration_hub_url:
        raise RuntimeError("INTEGRATION_HUB_URL is not configured")
    if not settings.internal_service_secret:
        raise RuntimeError(
            "INTERNAL_SERVICE_SECRET is not configured — required for "
            "worker calls to integration-hub /ai-invoke/run."
        )

    url = f"{settings.integration_hub_url.rstrip('/')}/api/v1/ai-invoke/run"

    # integration-hub requires EXACTLY ONE of agent_name / agent_id. Prefer the
    # portable qualified name when supplied; otherwise fall back to the UUID.
    body: dict[str, Any] = {
        "prompt": params.prompt,
        "context": params.context,
        "company_id": params.org_id or None,
    }
    if params.agent_name:
        body["agent_name"] = params.agent_name
    else:
        body["agent_id"] = params.agent_id
    ref = params.agent_name or params.agent_id

    async with httpx.AsyncClient(timeout=params.timeout_seconds) as client:
        resp = await client.post(
            url,
            headers={
                "Authorization": f"Bearer {settings.internal_service_secret}",
                "Content-Type": "application/json",
            },
            json=body,
        )
        if resp.status_code >= 400:
            # Echo the integration-hub error body into the activity
            # failure so workflow run history shows useful detail.
            raise RuntimeError(
                f"agent_node '{ref}' failed (HTTP {resp.status_code}): {resp.text}"
            )
        return cast(dict[str, Any], resp.json())
