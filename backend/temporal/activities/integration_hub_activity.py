"""Generic Integration Hub activity — delegates third-party calls to Integration Hub via HTTP."""

from dataclasses import dataclass
from typing import Any, cast

import httpx
from temporalio import activity
from temporalio.exceptions import ApplicationError

from shared.config import get_settings


@dataclass
class IntegrationHubParams:
    endpoint: str  # e.g. "gmail/send", "stripe/call", "s3/operation"
    payload: dict[str, Any]  # action-specific fields including credential_id
    timeout_seconds: int = 30  # per-integration timeout override


@activity.defn
async def call_integration_hub(params: IntegrationHubParams) -> dict[str, Any]:
    settings = get_settings()
    if not settings.integration_hub_url:
        raise RuntimeError("INTEGRATION_HUB_URL is not configured")
    if not settings.integration_hub_api_key:
        raise RuntimeError("INTEGRATION_HUB_API_KEY is not configured")

    url = f"{settings.integration_hub_url.rstrip('/')}/api/v1/integrations/{params.endpoint}"
    async with httpx.AsyncClient(timeout=params.timeout_seconds) as client:
        resp = await client.post(
            url,
            # Match the platform-wide M2M auth header name. Other
            # services use `X-Internal-Key`; mit-stack used to send
            # `X-API-Key`. Keep both for transitional compat — drop
            # the alias once every integration-hub caller is on the
            # canonical name.
            headers={
                "X-Internal-Key": settings.integration_hub_api_key,
                "X-API-Key": settings.integration_hub_api_key,
            },
            json=params.payload,
        )
        # Surface 4xx as non-retryable so Temporal doesn't burn worker
        # slots retrying a call that will never self-heal (bad
        # credential, validation error, missing endpoint, etc.).
        # 5xx falls through to a normal exception and Temporal's
        # default retry policy.
        if 400 <= resp.status_code < 500:
            raise ApplicationError(
                f"integration-hub returned {resp.status_code}: {resp.text[:500]}",
                non_retryable=True,
                type="IntegrationHubClientError",
            )
        resp.raise_for_status()
        return cast(dict[str, Any], resp.json())
