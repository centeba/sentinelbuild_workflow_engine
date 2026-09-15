import hashlib
import hmac
import uuid
from collections.abc import Sequence
from typing import Annotated, Any, cast

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from api.constants import (
    ROLE_COMPANY_ADMIN,
    ROLE_SYSTEM_ADMIN,
    WF_VERSION_ACTIVE,
    WF_VERSION_ARCHIVED,
)
from api.deps import CurrentUser, get_current_user
from api.models.execution import NodeExecution, WorkflowExecution
from api.models.workflow import Workflow
from api.models.workflow_version import WorkflowVersion
from api.schemas.execution import ExecutionResponse
from api.schemas.workflow import (
    PublishRequest,
    TriggerInfoResponse,
    TriggerResponse,
    WorkflowCreate,
    WorkflowResponse,
    WorkflowUpdate,
    WorkflowVersionResponse,
)
from api.services import workflow_service
from shared.config import get_settings
from shared.db import get_db

_s = get_settings()

log = structlog.get_logger(__name__)
router = APIRouter(prefix="/workflows", tags=["workflows"])


class _ShareRequest(BaseModel):
    company_id: uuid.UUID


def _shared_with_ids(wf: Workflow) -> list[str]:
    return [str(x) for x in (wf.shared_with or [])]


async def _load_workflow_for_access(
    db: AsyncSession,
    workflow_id: uuid.UUID,
    current: CurrentUser,
    *,
    require_active: bool = False,
) -> Workflow:
    """Fetch a workflow enforcing cross-company access (Phase 2c).

    Allowed when: the caller's org owns it, the caller is a system/platform
    admin, OR the workflow is shared with the caller's org — dual-read of the
    legacy ``shared_with`` list AND the authz service. A 404 (not 403) hides the
    workflow's existence from orgs without access. Previously GET/execute only
    matched ``org_id``, so shared workflows were unreachable and there was no
    cross-company gate at all.
    """
    wf = (
        await db.execute(select(Workflow).where(Workflow.id == workflow_id))
    ).scalar_one_or_none()
    if wf is None:
        raise HTTPException(status_code=404, detail="Workflow not found")

    is_admin = current.role in (ROLE_SYSTEM_ADMIN, "platform_admin")
    if str(wf.org_id) != str(current.org_id) and not is_admin:
        ids = _shared_with_ids(wf)
        legacy_ok = str(current.org_id) in ids or str(current.user_id) in ids
        authz_ok = False
        if not legacy_ok:
            try:
                from api.services.authz_share import authz_can_view_workflow

                authz_ok = await authz_can_view_workflow(
                    user_id=current.user_id, workflow_id=workflow_id
                )
            except Exception:  # noqa: BLE001
                authz_ok = False
        if not (legacy_ok or authz_ok):
            raise HTTPException(status_code=404, detail="Workflow not found")

    # Office scoping: an office user can't reach an own-org workflow outside
    # their subtree (shared / admin / cross-org workflows are unaffected).
    if (
        str(wf.org_id) == str(current.org_id)
        and current.office_scope is not None
        and wf.office_id is not None
        and str(wf.office_id) not in current.office_scope
    ):
        raise HTTPException(status_code=404, detail="Workflow not found")

    if require_active and not wf.is_active:
        raise HTTPException(status_code=404, detail="Workflow not found or inactive")
    return wf


@router.get("", response_model=list[WorkflowResponse])
async def list_workflows(
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    source_app: str | None = Query(
        default=None,
        description=(
            "Vertical-app ownership filter. Omit (default) for the generic "
            "platform builder — returns only workflows with no source_app. "
            "Pass e.g. 'restoration' to scope to a domain app's workflows."
        ),
    ),
) -> Sequence[Workflow]:
    """Return all workflows visible to the current user, scoped to one app:
    - system-mandated workflows (scope=system, is_mandated=True) — shown to everyone
    - company-mandated workflows for the user's org
    - the user's own personal workflows
    - workflows explicitly shared with this user/org

    The ``source_app`` filter is applied as an authoritative AND on top of
    the visibility rules — including the system-admin-sees-all clause — so a
    domain app's workflows never leak into the generic chassis builder
    (``source_app IS NULL``) and vice-versa.
    """
    from sqlalchemy import cast, or_
    from sqlalchemy.dialects.postgresql import JSONB

    user_id_str = str(current.user_id)
    org_id_str = str(current.org_id)

    # Authoritative app-ownership scope. None → generic platform workflows
    # only; a value → that app's workflows only.
    app_filter = (
        Workflow.source_app == source_app
        if source_app
        else Workflow.source_app.is_(None)
    )

    q = (
        select(Workflow)
        .where(
            app_filter,
            or_(
                # system-mandated: visible to all
                (Workflow.scope == "system") & (Workflow.is_mandated == True),  # noqa: E712
                # company-mandated: visible to members of the org
                (Workflow.scope == "company")
                & (Workflow.org_id == current.org_id)
                & (Workflow.is_mandated == True),  # noqa: E712
                # personal: the user's own workflows in their org
                (Workflow.scope == "personal")
                & (Workflow.org_id == current.org_id)
                & (Workflow.created_by == current.user_id),
                # shared with this org or user
                Workflow.shared_with.contains(cast([org_id_str], JSONB)),
                Workflow.shared_with.contains(cast([user_id_str], JSONB)),
                # system_admin sees everything (within the app scope above)
                *(
                    [Workflow.id.is_not(None)]
                    if current.role in (ROLE_SYSTEM_ADMIN, "platform_admin")
                    else []
                ),
            ),
            *current.office_where(Workflow.office_id),
        )
        .order_by(Workflow.scope.asc(), Workflow.created_at.desc())
    )

    result = await db.execute(q)
    return result.scalars().all()


def _check_scope_permission(role: str, scope: str, is_mandated: bool) -> None:
    """Raise HTTPException if the user's role doesn't permit the requested scope/mandate."""
    if scope == "system" and role not in (ROLE_SYSTEM_ADMIN, "platform_admin"):
        raise HTTPException(
            status_code=403,
            detail="Only system admins can create system-scoped workflows",
        )
    if scope == "company" and role not in (
        ROLE_SYSTEM_ADMIN,
        "platform_admin",
        ROLE_COMPANY_ADMIN,
    ):
        raise HTTPException(
            status_code=403,
            detail="Only company admins can create company-scoped workflows",
        )
    if is_mandated and role not in (
        ROLE_SYSTEM_ADMIN,
        "platform_admin",
        ROLE_COMPANY_ADMIN,
    ):
        raise HTTPException(status_code=403, detail="Only admins can mandate workflows")


# S4 — node types that run arbitrary code / SQL / outbound requests or read
# internal state. Authoring OR executing a definition that uses any of them is
# restricted to company-admins+; for a plain member it's a 403. "Admin only"
# was previously convention, not enforcement.
_PRIVILEGED_NODE_TYPES = {"run_code", "db_query", "http_request", "web_scraper"}
_ADMIN_ROLES = (ROLE_SYSTEM_ADMIN, "platform_admin", ROLE_COMPANY_ADMIN)


def _check_privileged_nodes(role: str, definition: dict[str, Any] | None) -> None:
    """Raise 403 if a non-admin authors/runs a definition with a privileged node."""
    if role in _ADMIN_ROLES:
        return
    nodes = (definition or {}).get("nodes") or []
    used = sorted(
        _PRIVILEGED_NODE_TYPES.intersection(
            n.get("type") for n in nodes if isinstance(n, dict)
        )
    )
    if used:
        raise HTTPException(
            status_code=403,
            detail=(
                "Only company admins can author or run workflows using "
                f"privileged nodes: {used}"
            ),
        )


def _derive_trigger_type(definition: dict[str, Any] | None, fallback: str) -> str:
    """Derive a workflow's trigger_type from its entry pack_trigger node.

    Pack-contributed triggers carry the subscribed event in node config:
    the generic "any restoration event" trigger puts the chosen event in
    ``config.event_type``; specific triggers carry it in ``config.node_key``
    (which already equals the event key, e.g. ``restoration.project_created``).
    The event-bus fans out by matching ``Workflow.trigger_type`` to the
    emitted event_type, so we copy that value up to the workflow level.

    Returns ``fallback`` (the client-supplied trigger_type) when there's no
    pack_trigger entry node — generic webhook/cron/manual workflows are
    unaffected.
    """
    if not isinstance(definition, dict):
        return fallback
    nodes = definition.get("nodes") or []
    edges = definition.get("edges") or []
    has_incoming = {e.get("to") for e in edges if isinstance(e, dict)}
    for node in nodes:
        if not isinstance(node, dict) or node.get("type") != "pack_trigger":
            continue
        # Prefer the true entry node (no incoming edges); fall back to the
        # first pack_trigger if positions/edges are incomplete.
        if node.get("id") in has_incoming:
            continue
        cfg = node.get("config") or {}
        event = cfg.get("event_type") or cfg.get("node_key")
        if event:
            return str(event)
    # No clean entry node — try any pack_trigger.
    for node in nodes:
        if isinstance(node, dict) and node.get("type") == "pack_trigger":
            cfg = node.get("config") or {}
            event = cfg.get("event_type") or cfg.get("node_key")
            if event:
                return str(event)
    return fallback


def _entry_pack_trigger(definition: dict[str, Any] | None) -> dict[str, Any] | None:
    """Return the entry pack_trigger node (no incoming edges), else the first
    pack_trigger, else None."""
    if not isinstance(definition, dict):
        return None
    nodes = definition.get("nodes") or []
    edges = definition.get("edges") or []
    has_incoming = {e.get("to") for e in edges if isinstance(e, dict)}
    candidates = [
        n for n in nodes if isinstance(n, dict) and n.get("type") == "pack_trigger"
    ]
    for n in candidates:
        if n.get("id") not in has_incoming:
            return n
    return candidates[0] if candidates else None


def _derive_trigger_filter(definition: dict[str, Any] | None) -> dict[str, Any] | None:
    """Extract the entry pack_trigger node's structured condition group
    (``config.conditions``) so the event-bus can gate firing on domain data.
    Returns None when there are no conditions (don't gate)."""
    node = _entry_pack_trigger(definition)
    if node is None:
        return None
    cond = (node.get("config") or {}).get("conditions")
    if isinstance(cond, dict) and (cond.get("rules") or []):
        return cond
    return None


@router.post("", response_model=WorkflowResponse, status_code=201)
async def create_workflow(
    body: WorkflowCreate,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Workflow:
    scope = getattr(body, "scope", "personal")
    visibility = getattr(body, "visibility", "private")
    is_mandated = getattr(body, "is_mandated", False)
    shared_with = getattr(body, "shared_with", [])

    _check_scope_permission(current.role, scope, is_mandated)
    _check_privileged_nodes(current.role, body.definition)

    owner_org_id = None if scope == "system" else current.org_id

    # Pack-trigger normalisation: when the entry node is a pack_trigger
    # (e.g. the generic "any restoration event" trigger), the event the
    # workflow subscribes to lives in the node config — derive
    # trigger_type from it so the event-bus fan-out matches. Keeps the
    # generic trigger working without the builder having to set
    # trigger_type itself.
    effective_trigger_type = _derive_trigger_type(
        body.definition,
        body.trigger_type,
    )
    # Lift the entry trigger node's domain conditions up to trigger_config so
    # the event-bus can gate firing on them (trigger_config is versioned +
    # restored, so this propagates without extra plumbing).
    effective_trigger_config = dict(body.trigger_config or {})
    _filter = _derive_trigger_filter(body.definition)
    if _filter is not None:
        effective_trigger_config["conditions"] = _filter

    try:
        wf = await workflow_service.create_workflow(
            db,
            current.org_id,
            current.user_id,
            body.name,
            body.description,
            body.definition,
            effective_trigger_type,
            effective_trigger_config,
            scope=scope,
            visibility=visibility,
            is_mandated=is_mandated,
            shared_with=shared_with,
            owner_org_id=owner_org_id,
            source_app=getattr(body, "source_app", None),
            office_id=(None if scope == "system" else current.office_id_value),
        )
    except ValueError as exc:
        # ValueError here is most commonly a slug / name collision —
        # the service-layer message may include the conflicting field
        # ("workflow name 'foo' already exists"). That's largely
        # user-safe but we still funnel it through a generic message
        # for consistency and log the full exc for ops.
        log.warning(
            "workflow_create_failed",
            exc_info=True,
            org_id=str(current.org_id),
            name=body.name,
        )
        raise HTTPException(
            status_code=409,
            detail="Workflow creation conflict — name or slug may already be in use.",
        ) from exc

    # A5 — persist cross-company federation (participants + per-node authz
    # rules) the service signature doesn't carry. Defaults are empty, so
    # single-company workflows are unaffected.
    participants = getattr(body, "participants", None)
    action_authz_rules = getattr(body, "action_authz_rules", None)
    if participants or action_authz_rules:
        if participants:
            wf.participants = participants
        if action_authz_rules:
            wf.action_authz_rules = action_authz_rules
        await db.commit()
        await db.refresh(wf)

    # Start IMAP poller if applicable
    if body.trigger_type == "imap_trigger" and body.is_active:
        from api.services.imap_poller_service import sync_imap_poller

        await sync_imap_poller(
            str(wf.id), str(wf.org_id), body.trigger_config, is_active=True
        )
    return wf


@router.get("/{workflow_id}", response_model=WorkflowResponse)
async def get_workflow(
    workflow_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Workflow:
    return await _load_workflow_for_access(db, workflow_id, current)


@router.post("/{workflow_id}/share", response_model=WorkflowResponse)
async def share_workflow(
    workflow_id: uuid.UUID,
    body: _ShareRequest,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Workflow:
    """Share a workflow with another company. Only the owning org may share.
    Updates ``shared_with`` AND mirrors an authz viewer grant (+ owner tuple)."""
    wf = (
        await db.execute(
            select(Workflow).where(
                Workflow.id == workflow_id,
                Workflow.org_id == current.org_id,
                *current.office_where(Workflow.office_id),
            )
        )
    ).scalar_one_or_none()
    if not wf:
        raise HTTPException(status_code=404, detail="Workflow not found")
    cid = str(body.company_id)
    if cid not in _shared_with_ids(wf):
        wf.shared_with = [*(wf.shared_with or []), cid]
        await db.flush()
    from api.services.authz_share import write_workflow_share

    await write_workflow_share(
        workflow_id, owner_org_id=wf.org_id, grantee_company_id=cid
    )
    return wf


@router.delete("/{workflow_id}/share", response_model=WorkflowResponse)
async def unshare_workflow(
    workflow_id: uuid.UUID,
    body: _ShareRequest,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Workflow:
    """Revoke a company's share. Only the owning org may unshare."""
    wf = (
        await db.execute(
            select(Workflow).where(
                Workflow.id == workflow_id,
                Workflow.org_id == current.org_id,
                *current.office_where(Workflow.office_id),
            )
        )
    ).scalar_one_or_none()
    if not wf:
        raise HTTPException(status_code=404, detail="Workflow not found")
    cid = str(body.company_id)
    wf.shared_with = [x for x in (wf.shared_with or []) if str(x) != cid]
    await db.flush()
    from api.services.authz_share import delete_workflow_share

    await delete_workflow_share(workflow_id, grantee_company_id=cid)
    return wf


@router.put("/{workflow_id}", response_model=WorkflowResponse)
async def update_workflow(
    workflow_id: uuid.UUID,
    body: WorkflowUpdate,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Workflow:
    result = await db.execute(
        select(Workflow).where(
            Workflow.id == workflow_id,
            Workflow.org_id == current.org_id,
            *current.office_where(Workflow.office_id),
        )
    )
    wf = result.scalar_one_or_none()
    if not wf:
        raise HTTPException(status_code=404, detail="Workflow not found")
    updates = body.model_dump(exclude_none=True)
    if "definition" in updates:
        _check_privileged_nodes(current.role, updates["definition"])
    for field, val in updates.items():
        setattr(wf, field, val)
    # When the graph changed, re-lift the entry trigger node's domain
    # conditions into trigger_config (or clear them if removed).
    if "definition" in updates:
        tc = dict(wf.trigger_config or {})
        _filter = _derive_trigger_filter(wf.definition)
        if _filter is not None:
            tc["conditions"] = _filter
        else:
            tc.pop("conditions", None)
        wf.trigger_config = tc
    await db.flush()

    # Sync IMAP poller if trigger type or active state changed
    if (
        wf.trigger_type == "imap_trigger"
        or "trigger_type" in updates
        or "is_active" in updates
    ):
        from api.services.imap_poller_service import sync_imap_poller

        await sync_imap_poller(
            str(wf.id), str(wf.org_id), wf.trigger_config, is_active=wf.is_active
        )

    return wf


@router.delete("/{workflow_id}", status_code=204)
async def delete_workflow(
    workflow_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> None:
    result = await db.execute(
        select(Workflow).where(
            Workflow.id == workflow_id,
            Workflow.org_id == current.org_id,
            *current.office_where(Workflow.office_id),
        )
    )
    wf = result.scalar_one_or_none()
    if not wf:
        raise HTTPException(status_code=404, detail="Workflow not found")
    # Stop IMAP poller before deletion
    if wf.trigger_type == "imap_trigger":
        from api.services.imap_poller_service import stop_imap_poller

        await stop_imap_poller(str(wf.id), silent=True)
    await db.delete(wf)


@router.post("/{workflow_id}/execute", response_model=TriggerResponse)
async def execute_workflow(
    workflow_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: dict[str, Any] = {},
) -> TriggerResponse:
    wf = await _load_workflow_for_access(db, workflow_id, current, require_active=True)
    # Use active published version if available; fall back to draft definition for unpublished workflows
    version_id = wf.active_version_id
    # S4 — gate execution on the definition that will actually run (active
    # version's, else the draft), so a member can't run a privileged-node graph.
    run_def = wf.definition
    if version_id is not None:
        ver = (
            await db.execute(
                select(WorkflowVersion).where(WorkflowVersion.id == version_id)
            )
        ).scalar_one_or_none()
        if ver is not None:
            run_def = ver.definition
    _check_privileged_nodes(current.role, run_def)
    execution = await workflow_service.trigger_workflow(
        db, wf, body, trigger_type="manual", version_id=version_id
    )
    return TriggerResponse(
        execution_id=execution.id,
        # temporal_workflow_id is str | None on the model but required (str) on
        # the response; Pydantic already enforces non-None here at runtime.
        temporal_workflow_id=cast(str, execution.temporal_workflow_id),
        status=execution.status,
    )


@router.get("/{workflow_id}/trigger-info", response_model=TriggerInfoResponse)
async def get_trigger_info(
    workflow_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TriggerInfoResponse:
    """Return trigger type, config, and (for webhook triggers) the webhook URL and secret."""
    result = await db.execute(
        select(Workflow).where(
            Workflow.id == workflow_id,
            Workflow.org_id == current.org_id,
            *current.office_where(Workflow.office_id),
        )
    )
    wf = result.scalar_one_or_none()
    if not wf:
        raise HTTPException(status_code=404, detail="Workflow not found")

    settings = get_settings()
    webhook_url = None
    if wf.trigger_type == "webhook_trigger":
        base = (
            settings.public_base_url.rstrip("/")
            if hasattr(settings, "public_base_url")
            else ""
        )
        webhook_url = f"{base}/api/v1/webhooks/{wf.org_id}/{wf.id}"

    return TriggerInfoResponse(
        trigger_type=wf.trigger_type,
        trigger_config=wf.trigger_config or {},
        webhook_url=webhook_url,
        webhook_secret=wf.webhook_secret
        if wf.trigger_type == "webhook_trigger"
        else None,
    )


# ── Version management ────────────────────────────────────────────────────────


@router.post(
    "/{workflow_id}/publish", response_model=WorkflowVersionResponse, status_code=201
)
async def publish_workflow(
    workflow_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: PublishRequest = PublishRequest(),
) -> WorkflowVersion:
    """Snapshot the current draft definition as a new published version."""
    result = await db.execute(
        select(Workflow).where(
            Workflow.id == workflow_id,
            Workflow.org_id == current.org_id,
            *current.office_where(Workflow.office_id),
        )
    )
    wf = result.scalar_one_or_none()
    if not wf:
        raise HTTPException(status_code=404, detail="Workflow not found")
    _check_privileged_nodes(current.role, wf.definition)  # S4

    # Determine next version number
    max_result = await db.execute(
        select(func.max(WorkflowVersion.version_num)).where(
            WorkflowVersion.workflow_id == workflow_id
        )
    )
    max_num = max_result.scalar_one() or 0

    # Archive the current active version
    if wf.active_version_id:
        old_version = await db.get(WorkflowVersion, wf.active_version_id)
        if old_version:
            old_version.status = WF_VERSION_ARCHIVED
            db.add(old_version)

    # Create new version snapshot
    version = WorkflowVersion(
        workflow_id=wf.id,
        org_id=wf.org_id,
        version_num=max_num + 1,
        note=body.note,
        status=WF_VERSION_ACTIVE,
        definition=wf.definition,
        trigger_type=wf.trigger_type,
        trigger_config=wf.trigger_config,
        created_by=current.user_id,
    )
    db.add(version)
    await db.flush()

    # Point workflow to new active version
    wf.active_version_id = version.id
    db.add(wf)
    await db.flush()

    return version


@router.get("/{workflow_id}/versions", response_model=list[WorkflowVersionResponse])
async def list_versions(
    workflow_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Sequence[WorkflowVersion]:
    result = await db.execute(
        select(WorkflowVersion)
        .where(
            WorkflowVersion.workflow_id == workflow_id,
            WorkflowVersion.org_id == current.org_id,
        )
        .order_by(WorkflowVersion.version_num.desc())
    )
    return result.scalars().all()


@router.get(
    "/{workflow_id}/versions/{version_id}", response_model=WorkflowVersionResponse
)
async def get_version(
    workflow_id: uuid.UUID,
    version_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> WorkflowVersion:
    result = await db.execute(
        select(WorkflowVersion).where(
            WorkflowVersion.id == version_id,
            WorkflowVersion.workflow_id == workflow_id,
            WorkflowVersion.org_id == current.org_id,
        )
    )
    version = result.scalar_one_or_none()
    if not version:
        raise HTTPException(status_code=404, detail="Version not found")
    return version


@router.post(
    "/{workflow_id}/versions/{version_id}/rollback",
    response_model=WorkflowVersionResponse,
    status_code=201,
)
async def rollback_version(
    workflow_id: uuid.UUID,
    version_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: PublishRequest = PublishRequest(),
) -> WorkflowVersion:
    """Restore a previous version: copies its definition to draft and publishes as a new version."""
    # Load the target version
    ver_result = await db.execute(
        select(WorkflowVersion).where(
            WorkflowVersion.id == version_id,
            WorkflowVersion.workflow_id == workflow_id,
            WorkflowVersion.org_id == current.org_id,
        )
    )
    old_version = ver_result.scalar_one_or_none()
    if not old_version:
        raise HTTPException(status_code=404, detail="Version not found")
    _check_privileged_nodes(current.role, old_version.definition)  # S4

    # Load workflow
    wf = await db.get(Workflow, workflow_id)
    if not wf:
        raise HTTPException(status_code=404, detail="Workflow not found")

    # Restore the old definition to the draft
    wf.definition = old_version.definition
    wf.trigger_type = old_version.trigger_type
    wf.trigger_config = old_version.trigger_config

    # Determine next version number
    max_result = await db.execute(
        select(func.max(WorkflowVersion.version_num)).where(
            WorkflowVersion.workflow_id == workflow_id
        )
    )
    max_num = max_result.scalar_one() or 0

    # Archive current active
    if wf.active_version_id:
        current_active = await db.get(WorkflowVersion, wf.active_version_id)
        if current_active:
            current_active.status = WF_VERSION_ARCHIVED
            db.add(current_active)

    # Create new version from the rollback
    new_version = WorkflowVersion(
        workflow_id=wf.id,
        org_id=wf.org_id,
        version_num=max_num + 1,
        note=body.note or f"Rollback to v{old_version.version_num}",
        status=WF_VERSION_ACTIVE,
        definition=old_version.definition,
        trigger_type=old_version.trigger_type,
        trigger_config=old_version.trigger_config,
        created_by=current.user_id,
    )
    db.add(new_version)
    await db.flush()

    wf.active_version_id = new_version.id
    db.add(wf)
    await db.flush()

    return new_version


@router.get("/{workflow_id}/last-run-outputs")
async def get_last_run_outputs(
    workflow_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, Any]:
    """
    Return per-node output_data from the most recent execution of a workflow.
    Used by the workflow builder for the "pin output" debug feature.
    Returns: {node_id: output_data}
    """
    # Find the most recent execution
    exe_result = await db.execute(
        select(WorkflowExecution)
        .where(
            WorkflowExecution.workflow_id == workflow_id,
            WorkflowExecution.org_id == current.org_id,
        )
        .order_by(WorkflowExecution.created_at.desc())
        .limit(1)
    )
    exe = exe_result.scalar_one_or_none()
    if not exe:
        raise HTTPException(
            status_code=404, detail="No executions found for this workflow"
        )

    # Load node executions
    node_result = await db.execute(
        select(NodeExecution)
        .where(NodeExecution.execution_id == exe.id)
        .order_by(NodeExecution.created_at)
    )
    nodes = node_result.scalars().all()
    return {n.node_id: n.output_data for n in nodes}


@router.get("/{workflow_id}/export")
async def export_workflow(
    workflow_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> JSONResponse:
    """
    Export a workflow definition as a portable JSON file.
    IDs are stripped / regenerated on import so the file is org-agnostic.
    """
    result = await db.execute(
        select(Workflow).where(
            Workflow.id == workflow_id,
            Workflow.org_id == current.org_id,
            *current.office_where(Workflow.office_id),
        )
    )
    wf = result.scalar_one_or_none()
    if not wf:
        raise HTTPException(status_code=404, detail="Workflow not found")

    export_data = {
        "mit_stack_export_version": "1.0",
        "name": wf.name,
        "description": wf.description,
        "trigger_type": wf.trigger_type,
        "trigger_config": wf.trigger_config,
        "definition": wf.definition,
        # intentionally exclude: id, org_id, created_by, webhook_secret
    }
    filename = wf.name.replace(" ", "_").lower() + ".workflow.json"
    return JSONResponse(
        content=export_data,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.post("/import", response_model=WorkflowResponse, status_code=201)
async def import_workflow(
    body: dict[str, Any],
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Workflow:
    """
    Import a workflow from an exported JSON blob.
    Creates a new workflow (always new IDs — never overwrites).
    """
    if body.get("mit_stack_export_version") != "1.0":
        raise HTTPException(
            status_code=422,
            detail="Unrecognised export format. Expected mit_stack_export_version: '1.0'",
        )
    name = body.get("name") or "Imported Workflow"
    _check_privileged_nodes(current.role, body.get("definition", {}))  # S4
    # pre-existing bug fixed: passed created_by= but the service param is user_id= (required), so every import call raised TypeError
    wf = await workflow_service.create_workflow(
        db,
        org_id=current.org_id,
        user_id=current.user_id,
        name=f"{name} (imported)",
        description=body.get("description"),
        definition=body.get("definition", {}),
        trigger_type=body.get("trigger_type", "manual"),
        trigger_config=body.get("trigger_config", {}),
    )
    return wf


@router.get("/{workflow_id}/executions", response_model=list[ExecutionResponse])
async def list_executions(
    workflow_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = _s.pagination_default_limit,
) -> Sequence[WorkflowExecution]:
    result = await db.execute(
        select(WorkflowExecution)
        .where(
            WorkflowExecution.workflow_id == workflow_id,
            WorkflowExecution.org_id == current.org_id,
        )
        .order_by(WorkflowExecution.created_at.desc())
        .limit(limit)
    )
    return result.scalars().all()


# ── Public webhook endpoint ───────────────────────────────────────────────────

webhook_router = APIRouter(prefix="/webhooks", tags=["webhooks"])


@webhook_router.post("/{org_slug}/{workflow_id}")
async def receive_webhook(
    org_slug: str,
    workflow_id: uuid.UUID,
    request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, str]:
    from sqlalchemy import and_

    from api.models.organization import Organization

    # Resolve org
    org_result = await db.execute(
        select(Organization).where(Organization.slug == org_slug)
    )
    org = org_result.scalar_one_or_none()
    if not org:
        raise HTTPException(status_code=404, detail="Not found")

    # Find workflow
    wf_result = await db.execute(
        select(Workflow).where(
            and_(
                Workflow.id == workflow_id,
                Workflow.org_id == org.id,
                Workflow.is_active == True,
                Workflow.trigger_type == "webhook",
            )
        )
    )
    wf = wf_result.scalar_one_or_none()
    if not wf:
        raise HTTPException(status_code=404, detail="Not found")

    # Verify HMAC signature if secret is set
    if wf.webhook_secret:
        sig = request.headers.get("X-Mit-Signature", "")
        body_bytes = await request.body()
        expected = hmac.new(
            wf.webhook_secret.encode(), body_bytes, hashlib.sha256
        ).hexdigest()
        if not hmac.compare_digest(sig, f"sha256={expected}"):
            raise HTTPException(status_code=401, detail="Invalid signature")

    payload = await request.json()
    version_id = wf.active_version_id
    execution = await workflow_service.trigger_workflow(
        db, wf, payload, trigger_type="webhook", version_id=version_id
    )
    return {"execution_id": str(execution.id), "status": "accepted"}
