"""FastAPI dependency injection — auth + DB.

Token acceptance order
----------------------
1. **User Master JWT** (if ``USER_MASTER_SECRET_KEY`` is configured):
   Decoded using User Master's secret.  Must have ``scope == "full"``.
   The corresponding Organisation and User are auto-provisioned in Mit Stack's
   DB on first use via ``identity_sync.sync_identity``.

2. **Native Mit Stack JWT** (always tried as a fallback):
   Standard tokens issued by Mit Stack's own /auth/login endpoint.
   Must have ``type == "access"``.

If both fail the request is rejected with HTTP 401.
"""

import uuid
from collections.abc import Awaitable, Callable
from typing import Annotated, Any

import jwt
import structlog
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from smart_llm.platform_auth import decode_platform_token, platform_auth_configured
from smart_llm.token_revocation import token_is_revoked
from sqlalchemy import ColumnElement, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import InstrumentedAttribute

from api.models.user import User
from api.services.auth_service import decode_token
from shared.config import get_settings
from shared.db import get_db, set_current_org

log = structlog.get_logger(__name__)
bearer = HTTPBearer(auto_error=False)


class CurrentUser:
    def __init__(
        self,
        user: User,
        office_id: str | None = None,
        office_scope: list[str] | None = None,
    ):
        self.user = user
        self.user_id: uuid.UUID = user.id
        self.org_id: uuid.UUID = user.org_id
        self.role: str = user.role
        self.email: str = user.email
        # Office scoping (from the JWT). office_id = home office (None =
        # company-wide); office_scope = visible office ids (None = company-wide,
        # no filter). See sentinelbuild_sdk.office_scope for the read rule.
        self.office_id: str | None = office_id
        self.office_scope: list[str] | None = (
            [str(x) for x in office_scope] if office_scope is not None else None
        )

    @property
    def office_id_value(self) -> uuid.UUID | None:
        """Home office as a UUID (for stamping new artifacts); None = shared."""
        return uuid.UUID(self.office_id) if self.office_id else None

    def office_clause(
        self, office_col: InstrumentedAttribute[Any]
    ) -> ColumnElement[bool] | None:
        """SQLAlchemy WHERE clause enforcing office scoping on ``office_col``,
        or ``None`` (company-wide caller → no filter). Company-shared rows
        (office_id IS NULL) and rows in the caller's visible subtree pass."""
        if self.office_scope is None:
            return None
        from sqlalchemy import or_

        return or_(office_col.is_(None), office_col.in_(self.office_scope))

    def office_where(
        self, office_col: InstrumentedAttribute[Any]
    ) -> list[ColumnElement[bool]]:
        """List form of :meth:`office_clause` for splatting into ``.where(...)``
        — empty for company-wide callers (adds no predicate)."""
        c = self.office_clause(office_col)
        return [c] if c is not None else []


async def get_current_user(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> CurrentUser:
    _401 = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired token",
        headers={"WWW-Authenticate": "Bearer"},
    )

    if not credentials:
        log.warning("auth_missing_token", path=request.url.path)
        raise _401

    s = get_settings()
    token = credentials.credentials
    client_ip = request.client.host if request.client else "unknown"

    # ── 1. Try User Master JWT ─────────────────────────────────────────────────
    if s.user_master_secret_key or platform_auth_configured():
        try:
            um_payload = decode_platform_token(token, s.user_master_secret_key)
            # Gate 3: reject tokens revoked before their exp (shared denylist).
            # No-op unless TOKEN_REVOCATION_REDIS_URL is set.
            if await token_is_revoked(um_payload):
                raise _401
            if um_payload.get("scope") == "full":
                from api.services.identity_sync import sync_identity

                try:
                    user = await sync_identity(db, um_payload)
                except ValueError as exc:
                    # Don't leak sync_identity's internal complaint to the
                    # client — could include DB constraint names or claim
                    # contents. Log the full exception for ops, surface a
                    # generic 403.
                    log.warning(
                        "auth_identity_sync_failed",
                        exc_info=True,
                        sub=um_payload.get("sub"),
                        ip=client_ip,
                    )
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="Identity provisioning failed.",
                    ) from exc
                structlog.contextvars.bind_contextvars(
                    user_id=str(user.id), org_id=str(user.org_id)
                )
                set_current_org(user.org_id)  # RLS tenant GUC for this request
                return CurrentUser(
                    user,
                    office_id=um_payload.get("office_id"),
                    office_scope=um_payload.get("office_scope"),
                )
        except jwt.PyJWTError:
            pass  # Not a valid User Master token — try native JWT next.

    # ── 2. Native Mit Stack JWT ────────────────────────────────────────────────
    try:
        payload = decode_token(token)
        if payload.get("type") != "access":
            log.warning(
                "auth_invalid_token_type", token_type=payload.get("type"), ip=client_ip
            )
            raise _401
        user_id = payload.get("sub")
        if not user_id:
            log.warning("auth_missing_sub_claim", ip=client_ip)
            raise _401
    except jwt.PyJWTError:
        # The exception class itself is the diagnostic ("ExpiredSignatureError"
        # vs "InvalidTokenError"); exc_info=True captures the stack so we
        # can see where the decode failed without leaking the message into
        # the (warning) log payload at info-volume.
        log.warning(
            "auth_jwt_invalid", exc_info=True, ip=client_ip, path=request.url.path
        )
        raise _401

    result = await db.execute(
        select(User).where(User.id == uuid.UUID(user_id), User.is_active == True)
    )
    db_user = result.scalar_one_or_none()
    if not db_user:
        log.warning("auth_user_not_found", user_id=user_id, ip=client_ip)
        raise _401
    user = db_user

    structlog.contextvars.bind_contextvars(
        user_id=str(user.id), org_id=str(user.org_id)
    )
    set_current_org(user.org_id)  # RLS tenant GUC for this request
    return CurrentUser(
        user,
        office_id=payload.get("office_id"),
        office_scope=payload.get("office_scope"),
    )


async def resolve_user_from_token(token: str, db: AsyncSession) -> "CurrentUser | None":
    """Decode a JWT (User Master, then native Mit Stack) → ``CurrentUser``.

    Non-raising counterpart of :func:`get_current_user` for WebSocket
    handshakes, where the JWT arrives in the first message (browsers can't set
    headers on ``new WebSocket()``). Returns ``None`` on any failure — the
    caller closes the socket with the appropriate code. Mirrors the two-step
    decode above; kept separate so the HTTP path's error/logging contract is
    untouched.
    """
    if not token:
        return None
    s = get_settings()
    if s.user_master_secret_key or platform_auth_configured():
        try:
            um_payload = decode_platform_token(token, s.user_master_secret_key)
            # Gate 3: a revoked token is treated as no-auth here (non-raising
            # WebSocket path). No-op unless TOKEN_REVOCATION_REDIS_URL is set.
            if await token_is_revoked(um_payload):
                return None
            if um_payload.get("scope") == "full":
                from api.services.identity_sync import sync_identity

                try:
                    user = await sync_identity(db, um_payload)
                    return CurrentUser(
                        user,
                        office_id=um_payload.get("office_id"),
                        office_scope=um_payload.get("office_scope"),
                    )
                except ValueError:
                    return None
        except jwt.PyJWTError:
            pass
    try:
        payload = decode_token(token)
        if payload.get("type") != "access":
            return None
        user_id = payload.get("sub")
        if not user_id:
            return None
    except jwt.PyJWTError:
        return None
    result = await db.execute(
        select(User).where(User.id == uuid.UUID(user_id), User.is_active == True)
    )
    db_user = result.scalar_one_or_none()
    if not db_user:
        return None
    user = db_user
    return CurrentUser(
        user,
        office_id=payload.get("office_id"),
        office_scope=payload.get("office_scope"),
    )


# ── Cross-service AI budget gate (Phase F) — single entry point via SDK ─────
# The legacy ``api/services/budget_gate.py`` shim is gone — there is
# one entry point now, owned by the SDK's SmartLlmInvokeClient.

import os as _os

from shared._platform import SentinelBuildSettings, SmartLlmInvokeClient

_mit_settings = get_settings()
_sdk_settings = SentinelBuildSettings(
    integration_hub_url=(
        _os.environ.get("INTEGRATION_HUB_URL") or _mit_settings.integration_hub_url
    ).rstrip("/"),
    internal_api_key=(
        _mit_settings.integration_hub_api_key
        or _mit_settings.internal_api_key
        or _os.environ.get("INTERNAL_API_KEY")
        or _os.environ.get("INTERNAL_SERVICE_SECRET")
        or ""
    ),
)


def get_smart_llm_invoke_client() -> SmartLlmInvokeClient:
    return SmartLlmInvokeClient(_sdk_settings)


SmartLlmGateDep = Annotated[SmartLlmInvokeClient, Depends(get_smart_llm_invoke_client)]


def require_role(*roles: str) -> Callable[..., Awaitable[CurrentUser]]:
    async def check(
        current: Annotated[CurrentUser, Depends(get_current_user)],
    ) -> CurrentUser:
        if current.role not in roles:
            log.warning(
                "auth_insufficient_role",
                user_id=str(current.user_id),
                role=current.role,
                required=list(roles),
            )
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return current

    return check
