"""Internal service-to-service API — no user JWT required.

Authentication: X-API-Key header must match INTERNAL_API_KEY env var.

Endpoints:
  POST /internal/events/{event_type}
      Find all active workflows registered for the given trigger type
      within the given org and fire each one with the supplied payload.

      Used by:
        - email-extractor: fires "email_extracted" after each LLM extraction
        - esignature: (future) fires "envelope_completed" after signing

Example request (from email-extractor):
  POST /api/v1/internal/events/email_extracted
  X-API-Key: <INTERNAL_API_KEY>
  {
    "org_id": "<uuid>",
    "event_data": { "extraction_id": "...", "subject": "...", ... }
  }
"""

from __future__ import annotations

import hmac
import logging
import uuid
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from api.models.pack_node_type import PackNodeType
from api.models.workflow import Workflow
from api.services.rule_engine import evaluate_condition_group
from api.services.workflow_service import trigger_workflow
from shared.config import get_settings
from shared.db import get_db

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/internal", tags=["internal"])


# ── Auth ──────────────────────────────────────────────────────────────────────


def _verify_internal_key(
    # Canonical platform header name; old `X-API-Key` is accepted as a
    # transitional alias so existing callers don't break mid-rollout.
    # Once every caller is on `X-Internal-Key`, drop the alias.
    x_internal_key: str | None = Header(default=None, alias="X-Internal-Key"),
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
) -> None:
    settings = get_settings()
    if not settings.internal_api_key:
        raise HTTPException(
            status_code=503,
            detail="Internal API not configured (INTERNAL_API_KEY is not set)",
        )
    supplied = x_internal_key or x_api_key
    # M6 — constant-time compare to avoid leaking the key via timing.
    if not supplied or not hmac.compare_digest(supplied, settings.internal_api_key):
        raise HTTPException(status_code=401, detail="Unauthorized")


# ── Schemas ───────────────────────────────────────────────────────────────────


class EventPayload(BaseModel):
    org_id: str
    event_data: dict[str, Any] = {}


class EventDispatchResponse(BaseModel):
    event_type: str
    org_id: str
    triggered: int
    execution_ids: list[str]


class ScrapeRunPayload(BaseModel):
    """Synchronous scrape request (used by the agent-callable scrape tool)."""

    org_id: str
    url: str
    selectors: list[dict[str, Any]] = []
    actions: list[dict[str, Any]] = []
    session_id: str | None = None
    wait_for_selector: str | None = None
    timeout_ms: int = 30000


class PackNodeTypeUpsertPayload(BaseModel):
    pack_name: str
    kind: str  # "trigger" | "action" | "group"
    key: str
    manifest_json: dict[str, Any]


class PackNodeTypeUpsertResponse(BaseModel):
    pack_name: str
    kind: str
    key: str
    inserted: bool  # True = new row; False = updated existing row


# ── Endpoint ──────────────────────────────────────────────────────────────────


@router.post("/events/{event_type}", response_model=EventDispatchResponse)
async def dispatch_event(
    event_type: str,
    body: EventPayload,
    _key: None = Depends(_verify_internal_key),
    db: AsyncSession = Depends(get_db),
) -> EventDispatchResponse:
    """
    Find all active workflows with trigger_type == event_type for the given
    org and trigger each one with the provided event_data as input payload.

    Returns the number of workflows triggered and their execution IDs.
    A 200 response is returned even if no workflows are registered — that
    is a normal state (org hasn't set up a matching workflow yet).
    """
    try:
        org_id = uuid.UUID(body.org_id)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid org_id: {body.org_id!r}")

    # Find active workflows for this org that listen on the given event type.
    # Also include system-scoped is_mandated workflows (they apply to all orgs).
    q = select(Workflow).where(
        Workflow.trigger_type == event_type,
        Workflow.is_active == True,  # noqa: E712
        (
            (Workflow.org_id == org_id)
            | ((Workflow.scope == "system") & (Workflow.is_mandated == True))  # noqa: E712
        ),
    )
    result = await db.execute(q)
    workflows = result.scalars().all()

    if not workflows:
        logger.debug(
            "No active workflows for event_type=%s org_id=%s", event_type, org_id
        )
        return EventDispatchResponse(
            event_type=event_type,
            org_id=str(org_id),
            triggered=0,
            execution_ids=[],
        )

    execution_ids: list[str] = []
    for wf in workflows:
        # Structured trigger filter: gate firing on the workflow's domain
        # conditions, evaluated against the event payload. The condition
        # leaves carry domain/entity metadata (ignored here) plus the bare
        # ``field`` key, which resolves directly against the flat payload.
        # Cross-entity conditions needing a live fetch land in a later phase;
        # for now a referenced field absent from the payload simply fails its
        # leaf. Empty/no conditions → always fire. Eval errors fail open.
        conditions = (wf.trigger_config or {}).get("conditions")
        if isinstance(conditions, dict) and (conditions.get("rules") or []):
            try:
                if not evaluate_condition_group(body.event_data, conditions):
                    logger.info(
                        "Workflow %s skipped: trigger conditions not met (event=%s)",
                        wf.id,
                        event_type,
                    )
                    continue
            except Exception:
                logger.exception(
                    "Trigger-filter eval failed for wf=%s; firing anyway", wf.id
                )
        try:
            execution = await trigger_workflow(
                db,
                wf,
                body.event_data,
                trigger_type=event_type,
                version_id=wf.active_version_id,
            )
            execution_ids.append(str(execution.id))
            logger.info(
                "Dispatched event=%s → workflow=%s execution=%s",
                event_type,
                wf.id,
                execution.id,
            )
        except Exception:
            logger.exception(
                "Failed to trigger workflow=%s for event=%s", wf.id, event_type
            )

    return EventDispatchResponse(
        event_type=event_type,
        org_id=str(org_id),
        triggered=len(execution_ids),
        execution_ids=execution_ids,
    )


# ── Pack node-type registry upsert ───────────────────────────────────────────


@router.post(
    "/node-types/upsert",
    response_model=PackNodeTypeUpsertResponse,
)
async def upsert_pack_node_type(
    body: PackNodeTypeUpsertPayload,
    _key: None = Depends(_verify_internal_key),
    db: AsyncSession = Depends(get_db),
) -> PackNodeTypeUpsertResponse:
    """Insert or update a single pack-contributed node type spec.

    Called by integration-hub's pack bootstrap loop, once per
    ``WorkflowTriggerSpec`` / ``WorkflowActionSpec`` / ``PaletteGroupSpec``
    on every host startup. Idempotent: re-running with the same payload
    is a no-op write; updated specs overwrite ``manifest_json`` in place.

    The workflow-builder palette endpoint (Phase 2) reads this table to
    build the per-company palette response.
    """
    if body.kind not in (
        "trigger",
        "action",
        "group",
        "theme",
        "data_domain",
        "scraper_connector",
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                f"Invalid kind {body.kind!r}; "
                f"expected trigger/action/group/theme/data_domain/scraper_connector"
            ),
        )

    existing = (
        (
            await db.execute(
                select(PackNodeType).where(
                    PackNodeType.pack_name == body.pack_name,
                    PackNodeType.kind == body.kind,
                    PackNodeType.key == body.key,
                )
            )
        )
        .scalars()
        .first()
    )

    inserted = existing is None
    if existing is None:
        row = PackNodeType(
            pack_name=body.pack_name,
            kind=body.kind,
            key=body.key,
            manifest_json=body.manifest_json,
        )
        db.add(row)
    else:
        existing.manifest_json = body.manifest_json
    await db.commit()

    logger.info(
        "pack_node_type %s: pack=%s kind=%s key=%s",
        "inserted" if inserted else "updated",
        body.pack_name,
        body.kind,
        body.key,
    )
    return PackNodeTypeUpsertResponse(
        pack_name=body.pack_name,
        kind=body.kind,
        key=body.key,
        inserted=inserted,
    )


@router.post("/scraper/run")
async def run_scrape(
    body: ScrapeRunPayload,
    _key: None = Depends(_verify_internal_key),
) -> dict[str, Any]:
    """Run one scrape synchronously and return ``{url, data}``.

    The agent-callable ``scrape_url`` tool posts here. Playwright runs in the
    worker (where Chromium is installed); this dispatches a ``ScrapePageWorkflow``
    and awaits its result, so the scraper is callable as a plain HTTP/agent tool
    without the caller owning a browser. ``org_id`` scopes any session load.
    """
    import uuid as _uuid
    from datetime import timedelta

    from api.services.workflow_service import get_temporal_client
    from temporal.workflows.scrape_page_workflow import ScrapePageWorkflow

    settings = get_settings()
    client = await get_temporal_client()
    handle = await client.start_workflow(
        ScrapePageWorkflow.run,
        {
            "url": body.url,
            "org_id": body.org_id,
            "selectors": body.selectors,
            "actions": body.actions,
            "session_id": body.session_id,
            "wait_for_selector": body.wait_for_selector,
            "timeout_ms": body.timeout_ms,
        },
        id=f"scrape-{_uuid.uuid4()}",
        task_queue=settings.temporal_task_queue,
        execution_timeout=timedelta(minutes=11),
    )
    return await handle.result()


# ── Generic scheduled calls (cron → HTTP) ─────────────────────────────────────
# A domain-agnostic recurring-callback primitive. A vertical registers a call
# (cron + URL + headers it supplies for the target's own auth) and the framework
# fires it on schedule via ScheduledCallWorkflow. First user: restoration SLA
# `/sla/sweep`. The framework never learns the target's auth scheme — headers are
# opaque passthrough.


class ScheduledCallRegister(BaseModel):
    call_id: str  # stable id (one running schedule per id)
    cron: str  # Temporal cron, e.g. "*/5 * * * *"
    url: str
    method: str = "POST"
    headers: dict[str, str] = {}
    payload: dict[str, Any] | None = None
    timeout_seconds: int = 30


def _scheduled_call_wf_id(call_id: str) -> str:
    return f"scheduled-call-{call_id}"


@router.post("/scheduled-calls")
async def register_scheduled_call(
    body: ScheduledCallRegister,
    _key: None = Depends(_verify_internal_key),
) -> dict[str, Any]:
    """Start (or replace) a cron-scheduled HTTP call. Idempotent per ``call_id``."""
    from temporalio.common import WorkflowIDReusePolicy

    from api.services.workflow_service import get_temporal_client
    from temporal.activities.scheduled_call_activity import ScheduledCallParams
    from temporal.workflows.scheduled_call_workflow import ScheduledCallWorkflow

    settings = get_settings()
    client = await get_temporal_client()
    wf_id = _scheduled_call_wf_id(body.call_id)

    # Idempotent replacement: atomically terminate any workflow already running
    # under this id, then start the new schedule. A manual cancel-then-start
    # races — the cancel isn't awaited to completion, so start_workflow hits
    # WorkflowAlreadyStartedError and the OLD payload (e.g. a stale callback URL)
    # stays live. TERMINATE_IF_RUNNING lets the server do the swap atomically.
    await client.start_workflow(
        ScheduledCallWorkflow.run,
        ScheduledCallParams(
            call_id=body.call_id,
            url=body.url,
            method=body.method,
            headers=body.headers,
            payload=body.payload,
            timeout_seconds=body.timeout_seconds,
        ),
        id=wf_id,
        task_queue=settings.temporal_task_queue,
        cron_schedule=body.cron,
        id_reuse_policy=WorkflowIDReusePolicy.TERMINATE_IF_RUNNING,
    )
    return {
        "call_id": body.call_id,
        "workflow_id": wf_id,
        "cron": body.cron,
        "status": "scheduled",
    }


@router.delete("/scheduled-calls/{call_id}")
async def cancel_scheduled_call(
    call_id: str,
    _key: None = Depends(_verify_internal_key),
) -> dict[str, Any]:
    """Cancel a cron-scheduled call."""
    from api.services.workflow_service import get_temporal_client

    client = await get_temporal_client()
    cancelled = False
    try:
        await client.get_workflow_handle(_scheduled_call_wf_id(call_id)).cancel()
        cancelled = True
    except Exception:
        pass
    return {"call_id": call_id, "cancelled": cancelled}
