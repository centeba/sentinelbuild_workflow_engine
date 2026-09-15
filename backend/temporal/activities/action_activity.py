"""Phase F1.5 — execute a registered ``ActionTool`` from a workflow node.

A workflow's ``action_node`` carries a registered tool name + a typed
args dict. This activity round-trips the call to integration-hub's
``POST /api/v1/ai-tools/run`` endpoint, where the smart-llm runtime
dispatches to the correct service.

Auth: the worker sends ``Authorization: Bearer ${INTERNAL_SERVICE_SECRET}``
— a raw shared-secret string verified by integration-hub's
``InternalServiceDep`` / ``AnyAuthDep``. This replaces the previous
approach of minting a forged ``role=system_admin`` JWT, which was a
security smell (any code with the shared secret could impersonate a
platform admin with a manufactured token). The raw-secret path is
audited separately from human JWT calls so worker-sourced dispatches
are distinguishable in integration-hub logs.

``company_id`` (``org_id`` from the workflow run) is passed in the
request body rather than being embedded in a JWT. The route injects
it into args for tenant-scoped tools.
"""

from dataclasses import dataclass, field
from typing import Any, cast

import httpx
from temporalio import activity

from shared.config import get_settings


@dataclass
class ActionParams:
    skill_name: str  # registry name, e.g. "postgres_run_query"
    args: dict[str, Any] = field(default_factory=dict)
    org_id: str = ""  # workflow run's tenant — forwarded as body company_id
    timeout_seconds: int = 60


@activity.defn
async def run_action_node(params: ActionParams) -> dict[str, Any]:
    """POST to integration-hub ``/ai-tools/run`` and return the result
    payload. Errors are surfaced as Temporal activity failures so the
    standard retry policy applies."""
    settings = get_settings()
    if not settings.integration_hub_url:
        raise RuntimeError("INTEGRATION_HUB_URL is not configured")
    if not settings.internal_service_secret:
        raise RuntimeError(
            "INTERNAL_SERVICE_SECRET is not configured — required for "
            "worker calls to integration-hub /ai-tools/run."
        )

    url = f"{settings.integration_hub_url.rstrip('/')}/api/v1/ai-tools/run"

    async with httpx.AsyncClient(timeout=params.timeout_seconds) as client:
        resp = await client.post(
            url,
            headers={
                "Authorization": f"Bearer {settings.internal_service_secret}",
                "Content-Type": "application/json",
            },
            json={
                "skill_name": params.skill_name,
                "args": params.args,
                "company_id": params.org_id or None,
            },
        )
        if resp.status_code >= 400:
            # Echo the integration-hub error body into the activity
            # failure so workflow run history shows useful detail.
            raise RuntimeError(
                f"action_node '{params.skill_name}' failed "
                f"(HTTP {resp.status_code}): {resp.text}"
            )
        return cast(dict[str, Any], resp.json())
