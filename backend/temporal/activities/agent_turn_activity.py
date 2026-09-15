"""Durable autonomous agent — one provider turn + one tool dispatch.

These two activities back the :class:`AgentRunWorkflow`. They round-trip to
integration-hub's ``/ai-invoke/agent-turn`` and ``/ai-invoke/agent-tool-dispatch``
endpoints (where the smart-llm runtime + policy gate live). The workflow holds
the opaque, provider-shaped ``messages`` array and orchestrates approvals; all
LLM I/O + policy evaluation happen here, inside activities (never in workflow
code), so workflow replay stays deterministic.

Auth: ``Authorization: Bearer ${INTERNAL_SERVICE_SECRET}`` (same as agent_activity).
"""

from dataclasses import dataclass, field
from typing import Any, cast

import httpx
from temporalio import activity

from shared.config import get_settings


def _hub_url(path: str) -> str:
    settings = get_settings()
    if not settings.integration_hub_url:
        raise RuntimeError("INTEGRATION_HUB_URL is not configured")
    if not settings.internal_service_secret:
        raise RuntimeError("INTERNAL_SERVICE_SECRET is not configured")
    return f"{settings.integration_hub_url.rstrip('/')}{path}"


def _headers() -> dict[str, str]:
    settings = get_settings()
    return {
        "Authorization": f"Bearer {settings.internal_service_secret}",
        "Content-Type": "application/json",
    }


@dataclass
class AgentTurnParams:
    agent_id: str
    org_id: str  # acting company (forwarded as company_id)
    messages: list[dict[str, Any]] = field(default_factory=list)
    tool_results: list[dict[str, Any]] | None = None
    timeout_seconds: int = 180


@activity.defn
async def run_agent_turn(params: AgentTurnParams) -> dict[str, Any]:
    """POST one turn to integration-hub. Returns
    ``{status, messages, content?, tool_calls, usage}``."""
    async with httpx.AsyncClient(timeout=params.timeout_seconds) as client:
        resp = await client.post(
            _hub_url("/api/v1/ai-invoke/agent-turn"),
            headers=_headers(),
            json={
                "agent_id": params.agent_id,
                "company_id": params.org_id or None,
                "acting_company_id": params.org_id or None,
                "messages": params.messages,
                "tool_results": params.tool_results,
            },
        )
        if resp.status_code >= 400:
            raise RuntimeError(
                f"agent-turn for {params.agent_id} failed "
                f"(HTTP {resp.status_code}): {resp.text}"
            )
        return cast(dict[str, Any], resp.json())


@dataclass
class ToolDispatchParams:
    agent_id: str
    org_id: str
    tool_call_id: str
    tool_name: str
    tool_input: dict[str, Any] = field(default_factory=dict)
    timeout_seconds: int = 120


@activity.defn
async def run_agent_tool_dispatch(params: ToolDispatchParams) -> dict[str, Any]:
    """POST one approved tool dispatch. Returns ``{tool_call_id, name, content}``."""
    async with httpx.AsyncClient(timeout=params.timeout_seconds) as client:
        resp = await client.post(
            _hub_url("/api/v1/ai-invoke/agent-tool-dispatch"),
            headers=_headers(),
            json={
                "agent_id": params.agent_id,
                "company_id": params.org_id or None,
                "acting_company_id": params.org_id or None,
                "tool_call_id": params.tool_call_id,
                "tool_name": params.tool_name,
                "tool_input": params.tool_input,
            },
        )
        if resp.status_code >= 400:
            raise RuntimeError(
                f"agent-tool-dispatch {params.tool_name} failed "
                f"(HTTP {resp.status_code}): {resp.text}"
            )
        return cast(dict[str, Any], resp.json())
