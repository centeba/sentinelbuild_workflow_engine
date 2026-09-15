from typing import Annotated

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from api.deps import CurrentUser, get_current_user
from api.models.user import User
from api.schemas.auth import (
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
)
from api.services import auth_service
from shared.config import get_settings
from shared.db import get_db

log = structlog.get_logger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])


def _require_standalone() -> None:
    """Raise 501 when standalone auth has been disabled (integrated with User Master)."""
    if not get_settings().standalone_auth:
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED,
            detail=(
                "Standalone authentication is disabled on this instance. "
                "Please authenticate via User Master."
            ),
        )


@router.post("/register", response_model=TokenResponse, status_code=201)
async def register(
    body: RegisterRequest, db: Annotated[AsyncSession, Depends(get_db)]
) -> TokenResponse:
    _require_standalone()
    try:
        org, user = await auth_service.register(
            db, body.org_name, body.org_slug, body.email, body.password
        )
    except Exception as exc:
        # Don't echo the underlying exception (could include DB
        # constraint name "uq_user_email" etc., which is a small but
        # real disclosure). Log full exc for ops.
        log.warning(
            "auth_register_failed",
            exc_info=True,
            org_slug=body.org_slug,
            email=body.email,
        )
        raise HTTPException(
            status_code=400,
            detail="Registration failed — please verify the org slug "
            "and email are not already in use.",
        ) from exc
    return TokenResponse(
        access_token=auth_service.create_access_token(str(user.id), str(org.id)),
        refresh_token=auth_service.create_refresh_token(str(user.id), str(org.id)),
    )


@router.post("/login", response_model=TokenResponse)
async def login(
    body: LoginRequest, db: Annotated[AsyncSession, Depends(get_db)]
) -> TokenResponse:
    _require_standalone()
    user = await auth_service.authenticate(db, body.email, body.password)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return TokenResponse(
        access_token=auth_service.create_access_token(str(user.id), str(user.org_id)),
        refresh_token=auth_service.create_refresh_token(str(user.id), str(user.org_id)),
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh(body: RefreshRequest) -> TokenResponse:
    try:
        payload = auth_service.decode_token(body.refresh_token)
        if payload.get("type") != "refresh":
            raise ValueError("Not a refresh token")
        return TokenResponse(
            access_token=auth_service.create_access_token(
                payload["sub"], payload["org"]
            ),
            refresh_token=auth_service.create_refresh_token(
                payload["sub"], payload["org"]
            ),
        )
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid refresh token")


@router.get("/me", response_model=UserResponse)
async def me(current: Annotated[CurrentUser, Depends(get_current_user)]) -> User:
    return current.user
