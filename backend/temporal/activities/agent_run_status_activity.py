"""Activity: report an autonomous run's status into the agent_runs ledger
(owned by integration-hub). Best-effort — the workflow never fails on it."""

from dataclasses import dataclass
from typing import Any

import httpx
from temporalio import activity

from shared.config import get_settings


@dataclass
class AgentRunStatusParams:
    run_id: str
    agent_id: str
    acting_company_id: str
    status: str
    step_count: int = 0
    temporal_workflow_id: str | None = None


@activity.defn
async def report_agent_run_status(params: AgentRunStatusParams) -> dict[str, Any]:
    settings = get_settings()
    if not settings.integration_hub_url or not settings.internal_service_secret:
        return {"ok": False}
    url = (
        f"{settings.integration_hub_url.rstrip('/')}/api/v1/ai-invoke/agent-run-status"
    )
    async with httpx.AsyncClient(timeout=20) as client:
        resp = await client.post(
            url,
            headers={
                "Authorization": f"Bearer {settings.internal_service_secret}",
                "Content-Type": "application/json",
            },
            json={
                "run_id": params.run_id,
                "agent_id": params.agent_id,
                "acting_company_id": params.acting_company_id,
                "status": params.status,
                "step_count": params.step_count,
                "temporal_workflow_id": params.temporal_workflow_id,
            },
        )
        return {"ok": resp.status_code < 400}
