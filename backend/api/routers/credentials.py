import uuid
from collections.abc import Sequence
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from api.deps import CurrentUser, get_current_user
from api.models.credential import Credential
from api.schemas.credential import CredentialCreate, CredentialResponse
from api.services.credential_service import create_credential
from shared.db import get_db

router = APIRouter(prefix="/credentials", tags=["credentials"])


@router.get("", response_model=list[CredentialResponse])
async def list_credentials(
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Sequence[Credential]:
    result = await db.execute(
        select(Credential)
        .where(Credential.org_id == current.org_id)
        .order_by(Credential.created_at.desc())
    )
    return result.scalars().all()


@router.post("", response_model=CredentialResponse, status_code=201)
async def create(
    body: CredentialCreate,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Credential:
    cred = await create_credential(
        db,
        current.org_id,
        current.user_id,
        body.name,
        body.type,
        body.secret_data,
        body.metadata,
    )
    return cred


@router.delete("/{credential_id}", status_code=204)
async def delete_credential(
    credential_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> None:
    result = await db.execute(
        select(Credential).where(
            Credential.id == credential_id, Credential.org_id == current.org_id
        )
    )
    cred = result.scalar_one_or_none()
    if not cred:
        raise HTTPException(status_code=404, detail="Credential not found")
    await db.delete(cred)
