import uuid
from collections.abc import Sequence
from typing import Annotated

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from api.deps import CurrentUser, get_current_user
from api.models.form import Form
from api.schemas.form import FormCreate, FormResponse, FormUpdate
from shared.db import get_db

log = structlog.get_logger(__name__)
router = APIRouter(prefix="/forms", tags=["forms"])


async def _get_owned(form_id: uuid.UUID, org_id: uuid.UUID, db: AsyncSession) -> Form:
    form = await db.get(Form, form_id)
    if form is None or form.org_id != org_id:
        raise HTTPException(status_code=404, detail="Form not found")
    return form


@router.get("", response_model=list[FormResponse])
async def list_forms(
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Sequence[Form]:
    """List the current org's forms, newest first."""
    result = await db.execute(
        select(Form)
        .where(Form.org_id == current.org_id)
        .order_by(Form.created_at.desc())
    )
    return result.scalars().all()


@router.post("", response_model=FormResponse, status_code=201)
async def create_form(
    body: FormCreate,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Form:
    form = Form(
        org_id=current.org_id,
        name=body.name,
        description=body.description,
        schema=body.schema.model_dump(),
        is_active=body.is_active,
    )
    db.add(form)
    await db.commit()
    await db.refresh(form)
    log.info("form_created", form_id=str(form.id), org_id=str(current.org_id))
    return form


@router.get("/{form_id}", response_model=FormResponse)
async def get_form(
    form_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Form:
    return await _get_owned(form_id, current.org_id, db)


@router.put("/{form_id}", response_model=FormResponse)
async def update_form(
    form_id: uuid.UUID,
    body: FormUpdate,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Form:
    form = await _get_owned(form_id, current.org_id, db)
    if body.name is not None:
        form.name = body.name
    if body.description is not None:
        form.description = body.description
    if body.schema is not None:
        form.schema = body.schema.model_dump()
    if body.is_active is not None:
        form.is_active = body.is_active
    await db.commit()
    await db.refresh(form)
    return form


@router.delete("/{form_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_form(
    form_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> None:
    form = await _get_owned(form_id, current.org_id, db)
    await db.delete(form)
    await db.commit()
