import copy
import uuid
from collections.abc import Sequence
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from api.deps import CurrentUser, get_current_user
from api.models.pack_node_type import PackNodeType
from api.models.scraper import ScraperSession
from api.schemas.scraper import (
    ConnectorConnectRequest,
    ScraperSessionCreate,
    ScraperSessionResponse,
)
from api.services.credential_service import create_credential
from api.services.workflow_service import create_workflow
from shared.db import get_db

router = APIRouter(prefix="/scraper/sessions", tags=["scraper"])


@router.post(
    "/from-connector/{pack}/{connector_key}",
    response_model=ScraperSessionResponse,
    status_code=201,
)
async def create_session_from_connector(
    pack: str,
    connector_key: str,
    body: ConnectorConnectRequest,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ScraperSession:
    """Instantiate a per-tenant scraper session from a pack connector template.

    The template (login URL, selectors, MFA config — site knowledge) is shared
    across tenants; this tenant's secrets are encrypted in a new per-org
    credential. Tenant-identifier secrets (e.g. company id) named in the
    template's ``tenant_field`` are injected into the session's login fields.
    Run ``POST /scraper/sessions/{id}/refresh`` afterward to capture the session.
    """
    row = (
        await db.execute(
            select(PackNodeType).where(
                PackNodeType.pack_name == pack,
                PackNodeType.kind == "scraper_connector",
                PackNodeType.key == connector_key,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="Connector template not found")

    tmpl = row.manifest_json or {}
    secret_fields = tmpl.get("secret_fields", []) or []
    tenant_field = tmpl.get("tenant_field", {}) or {}
    provided = body.secrets or {}

    # secret_fields may be rich specs ({key,label,type,required}) or bare
    # strings; only required fields gate onboarding.
    required_keys = [
        (f["key"] if isinstance(f, dict) else f)
        for f in secret_fields
        if not isinstance(f, dict) or f.get("required", True)
    ]
    missing = [k for k in required_keys if not provided.get(k)]
    if missing:
        raise HTTPException(
            status_code=400, detail=f"Missing required secrets: {missing}"
        )

    # Tenant-identifier secrets (mapped to a login field) go into the session's
    # extra_fields; the genuine secrets are encrypted in a credential.
    cred_secrets = {k: v for k, v in provided.items() if k not in tenant_field}
    cred = await create_credential(
        db,
        current.org_id,
        current.user_id,
        body.name or f"{connector_key} ({pack})",
        "basic_auth",
        cred_secrets,
        {},
    )
    await db.flush()

    login_config = copy.deepcopy(tmpl.get("login_config", {}) or {})
    extra = {
        f.get("selector"): dict(f)
        for f in (login_config.get("extra_fields") or [])
        if f.get("selector")
    }
    field_values: dict[str, str] = {}
    for secret_name, selector in tenant_field.items():
        val = provided.get(secret_name)
        if val is not None and selector:
            extra.setdefault(selector, {"selector": selector})["value"] = str(val)
            field_values[secret_name] = str(val)
    login_config["extra_fields"] = list(extra.values())
    # Named tenant identifiers for declarative login_steps interpolation
    # ({{field.<key>}}). Identifiers only — genuine secrets stay in the credential.
    login_config["field_values"] = field_values

    session = ScraperSession(
        org_id=current.org_id,
        name=body.name or str(tmpl.get("label") or connector_key),
        base_url=tmpl.get("base_url", ""),
        login_url=tmpl.get("login_url", ""),
        credential_id=cred.id,
        login_config=login_config,
    )
    db.add(session)
    await db.flush()

    # Lever 2 — materialize each connector target into a runnable, manual
    # web_scraper workflow for this tenant (source_app = the owning pack), so the
    # scrapes are callable from the workflow surface without hand-building them.
    if body.materialize_targets:
        for target in tmpl.get("targets", []) or []:
            definition = {
                "nodes": [
                    {
                        "id": "scrape",
                        "type": "web_scraper",
                        "config": {
                            "url": target.get("url", ""),
                            "session_id": str(session.id),
                            "selectors": target.get("selectors", []),
                            "actions": target.get("actions", []),
                        },
                    }
                ],
                "edges": [],
                "meta": {"connector": connector_key, "target": target.get("key")},
            }
            await create_workflow(
                db,
                current.org_id,
                current.user_id,
                f"{tmpl.get('label', connector_key)} — {target.get('label', target.get('key'))}",
                f"Scrape {target.get('label', target.get('key'))} via the "
                f"{tmpl.get('label', connector_key)} connector.",
                definition,
                "manual",
                {},
                source_app=pack,
            )

    return session


@router.get("", response_model=list[ScraperSessionResponse])
async def list_sessions(
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Sequence[ScraperSession]:
    result = await db.execute(
        select(ScraperSession).where(ScraperSession.org_id == current.org_id)
    )
    return result.scalars().all()


@router.post("", response_model=ScraperSessionResponse, status_code=201)
async def create_session(
    body: ScraperSessionCreate,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ScraperSession:
    # SEC-M1 — validate the referenced credential belongs to the caller's org
    # before binding it to the session. org_id is forced from the JWT, but a
    # caller-supplied credential_id was stored unchecked, so the worker could
    # be pointed at another tenant's stored secret at scrape/login time.
    credential_id = getattr(body, "credential_id", None)
    if credential_id is not None:
        from api.models.credential import Credential

        owned = (
            await db.execute(
                select(Credential.id).where(
                    Credential.id == credential_id,
                    Credential.org_id == current.org_id,
                )
            )
        ).scalar_one_or_none()
        if owned is None:
            raise HTTPException(
                status_code=400, detail="credential_id not found for this organization"
            )

    session = ScraperSession(org_id=current.org_id, **body.model_dump())
    db.add(session)
    await db.flush()
    return session


@router.get("/{session_id}", response_model=ScraperSessionResponse)
async def get_session(
    session_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ScraperSession:
    result = await db.execute(
        select(ScraperSession).where(
            ScraperSession.id == session_id, ScraperSession.org_id == current.org_id
        )
    )
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return session


@router.post("/{session_id}/refresh", response_model=ScraperSessionResponse)
async def refresh_session(
    session_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ScraperSession:
    """Re-authenticate the session using stored credentials (Playwright)."""
    result = await db.execute(
        select(ScraperSession).where(
            ScraperSession.id == session_id, ScraperSession.org_id == current.org_id
        )
    )
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    # Queue a Temporal activity to re-login

    from api.services.workflow_service import get_temporal_client
    from shared.config import get_settings

    settings = get_settings()

    client = await get_temporal_client()
    # Dispatch as a one-off activity via a workflow
    # The scraper worker will handle headless login and save new session_data
    await client.start_workflow(
        "RefreshScraperSessionWorkflow",
        {"session_id": str(session_id), "org_id": str(current.org_id)},
        id=f"refresh-session-{session_id}",
        task_queue=settings.temporal_task_queue,
    )
    return session


@router.delete("/{session_id}", status_code=204)
async def delete_session(
    session_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> None:
    result = await db.execute(
        select(ScraperSession).where(
            ScraperSession.id == session_id, ScraperSession.org_id == current.org_id
        )
    )
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    await db.delete(session)
