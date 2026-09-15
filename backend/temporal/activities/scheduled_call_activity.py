"""Generic scheduled outbound call (framework primitive).

Domain-agnostic: makes one HTTP request to a configured URL with caller-supplied
headers (so the framework never needs to know the target's auth scheme — the
registrant supplies e.g. an ``X-Internal-Key`` header value). Driven on a cron by
``ScheduledCallWorkflow``. First user: restoration's SLA ``/sla/sweep``, but any
vertical can register a periodic callback.
"""

from dataclasses import dataclass, field
from typing import Any

import httpx
import structlog
from temporalio import activity

log = structlog.get_logger(__name__)


@dataclass
class ScheduledCallParams:
    call_id: str
    url: str
    method: str = "POST"
    headers: dict[str, str] = field(default_factory=dict)
    payload: dict[str, Any] | None = None
    timeout_seconds: int = 30


@activity.defn
async def perform_scheduled_call(params: ScheduledCallParams) -> dict[str, Any]:
    """One request per cron tick. Never raises for a non-2xx — returns the
    status so a flaky target doesn't spam Temporal retries; transport errors do
    propagate (so the retry policy can cover a blip)."""
    try:
        async with httpx.AsyncClient(timeout=params.timeout_seconds) as client:
            resp = await client.request(
                params.method.upper(),
                params.url,
                headers=params.headers or {},
                json=params.payload,
            )
        log.info(
            "scheduled_call_done",
            call_id=params.call_id,
            url=params.url,
            status=resp.status_code,
        )
        body: Any
        try:
            body = resp.json()
        except Exception:
            body = resp.text[:500]
        return {
            "call_id": params.call_id,
            "status_code": resp.status_code,
            "ok": resp.is_success,
            "body": body,
        }
    except Exception as exc:
        log.error(
            "scheduled_call_failed",
            call_id=params.call_id,
            url=params.url,
            error=str(exc),
        )
        raise
