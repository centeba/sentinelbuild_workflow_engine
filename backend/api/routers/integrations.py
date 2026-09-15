import json
import uuid
from collections.abc import Sequence
from pathlib import Path
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from api.deps import CurrentUser, get_current_user
from api.models.integration import Integration
from shared.db import get_db

router = APIRouter(prefix="/integrations", tags=["integrations"])

# ── Built-in connector catalogue ──────────────────────────────────────────────
# Loaded from connectors.json so new connectors can be added without touching code.

_CATALOGUE_PATH = Path(__file__).parent.parent / "connectors.json"
CONNECTOR_CATALOGUE: list[dict[str, Any]] = json.loads(
    _CATALOGUE_PATH.read_text(encoding="utf-8")
)


class IntegrationCreate(BaseModel):
    connector_type: str
    name: str
    credential_id: uuid.UUID | None = None
    config: dict[str, Any] = {}


class IntegrationResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    connector_type: str
    name: str
    credential_id: uuid.UUID | None
    config: dict[str, Any]

    model_config = {"from_attributes": True}


@router.get("/catalogue")
async def get_catalogue() -> list[dict[str, Any]]:
    """List all available connector types."""
    return CONNECTOR_CATALOGUE


@router.get("", response_model=list[IntegrationResponse])
async def list_integrations(
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Sequence[Integration]:
    result = await db.execute(
        select(Integration).where(Integration.org_id == current.org_id)
    )
    return result.scalars().all()


@router.post("", response_model=IntegrationResponse, status_code=201)
async def create_integration(
    body: IntegrationCreate,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Integration:
    integration = Integration(org_id=current.org_id, **body.model_dump())
    db.add(integration)
    await db.flush()
    return integration


@router.delete("/{integration_id}", status_code=204)
async def delete_integration(
    integration_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> None:
    result = await db.execute(
        select(Integration).where(
            Integration.id == integration_id, Integration.org_id == current.org_id
        )
    )
    integration = result.scalar_one_or_none()
    if not integration:
        raise HTTPException(status_code=404, detail="Integration not found")
    await db.delete(integration)
