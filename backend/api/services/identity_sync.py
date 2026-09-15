"""Identity synchronisation — User Master → Mit Stack.

Called on every authenticated request when a User Master JWT is presented.
Ensures that the corresponding Organisation and User exist in Mit Stack's
local DB, creating or updating them as needed.

No network calls are made: all required data is taken from the JWT payload
that User Master embeds when issuing full (scope="full") access tokens.

Role mapping
------------
User Master role          Mit Stack role
------------------------  ----------------
platform_admin            admin
company_admin             admin
user                      member
<anything else>           member
"""

import uuid
from typing import Any

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from api.models.organization import Organization
from api.models.user import User

# Sentinel password hash for externally-authenticated users.
# Starts with "!" so it can never be a valid bcrypt/argon2 hash.
_EXTERNAL_HASH = "!EXTERNAL"

_ROLE_MAP: dict[str, str] = {
    "system_admin": "admin",
    "platform_admin": "admin",
    "company_admin": "admin",
    "user": "member",
    "member": "member",
    "viewer": "member",
}

# Sentinel slug for the synthetic "platform" org used by system/platform admins
# who don't belong to any real company but still need to use Mit Stack.
_PLATFORM_ORG_SLUG = "__platform__"
_PLATFORM_ORG_NAME = "Platform"


async def sync_identity(db: AsyncSession, payload: dict[str, Any]) -> User:
    """Provision or refresh the Organisation and User derived from a User Master JWT.

    Parameters
    ----------
    db:
        Active async DB session (within a live request transaction).
    payload:
        Decoded JWT claims dict.  Must contain at minimum ``sub``
        (user UUID) and ``company_id`` (company UUID).

    Returns
    -------
    User
        The Mit Stack User ORM object, ready to wrap in CurrentUser.

    Raises
    ------
    ValueError
        If the token lacks ``company_id`` — e.g. a platform_admin who
        belongs to no company.  MIT Stack requires an organisation context.
    """
    user_id_str: str | None = payload.get("sub")
    company_id_str: str | None = payload.get("company_id")
    email: str = payload.get("email") or ""
    role_raw: str = payload.get("role") or "user"
    company_name: str = payload.get("company_name") or company_id_str or "Unknown"
    company_slug: str = payload.get("company_slug") or company_id_str or "unknown"

    # Platform-level admins don't belong to any real company; map them to a
    # synthetic "platform" org so they can use Mit Stack for admin tasks and
    # verification without being assigned to a tenant.
    is_platform_admin = role_raw in ("system_admin", "platform_admin")
    if not company_id_str:
        if is_platform_admin:
            company_slug = _PLATFORM_ORG_SLUG
            company_name = _PLATFORM_ORG_NAME
        else:
            raise ValueError(
                "Token has no company_id — this user has no company in User Master. "
                "Assign the user to a company before accessing Mit Stack."
            )

    user_id = uuid.UUID(user_id_str)
    role = _ROLE_MAP.get(role_raw, "member")

    # ── 1. Get or create the Organisation ─────────────────────────────────────
    org = await _get_or_create_org(db, company_slug, company_name)

    # ── 2. Get or create the User ──────────────────────────────────────────────
    user = await _get_or_create_user(db, user_id, org.id, email, role)

    return user


async def _get_or_create_org(
    db: AsyncSession,
    slug: str,
    name: str,
) -> Organization:
    result = await db.execute(select(Organization).where(Organization.slug == slug))
    org = result.scalar_one_or_none()
    if org is not None:
        return org

    org = Organization(name=name, slug=slug)
    db.add(org)
    try:
        await db.flush()
    except IntegrityError:
        # Concurrent request already created this org — re-fetch.
        await db.rollback()
        result = await db.execute(select(Organization).where(Organization.slug == slug))
        org = result.scalar_one()
    return org


async def _get_or_create_user(
    db: AsyncSession,
    user_id: uuid.UUID,
    org_id: uuid.UUID,
    email: str,
    role: str,
) -> User:
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if user is None:
        # Fast path: try to create. The IntegrityError fallback handles
        # both (a) a concurrent request creating the same row and (b)
        # the user-master ↔ mit-stack id-mismatch case where the two
        # services assign different UUIDs to the same logical person
        # (user-master keeps users in ``public.user`` with one PK;
        # mit-stack stores them in ``public.users`` with its own PK).
        # In that second case our INSERT trips the ``users.email``
        # UNIQUE constraint, not the PK constraint.
        user = User(
            id=user_id,
            org_id=org_id,
            email=email,
            password_hash=_EXTERNAL_HASH,
            role=role,
            is_active=True,
        )
        db.add(user)
        try:
            await db.flush()
            return user
        except IntegrityError:
            await db.rollback()

        # First, try by id (concurrent-create case).
        result = await db.execute(select(User).where(User.id == user_id))
        existing = result.scalar_one_or_none()
        if existing is not None:
            return existing

        # Fall back to email — covers the cross-service id-mismatch.
        # The local mit-stack row is the source of truth for ``user.id``
        # here on out; CurrentUser carries that id and ``org_id``, both
        # of which are correct.
        result = await db.execute(select(User).where(User.email == email))
        existing = result.scalar_one_or_none()
        if existing is not None:
            return existing

        # Genuinely could not find or create — bubble up.
        raise RuntimeError(
            f"identity_sync: could not provision User for sub={user_id} "
            f"email={email!r} (IntegrityError on insert + no matching row)"
        )

    # User exists — keep role and org in sync with User Master.
    changed = False
    if user.role != role:
        user.role = role
        changed = True
    if user.org_id != org_id:
        user.org_id = org_id
        changed = True
    if not user.is_active:
        user.is_active = True
        changed = True
    if changed:
        await db.flush()

    return user
