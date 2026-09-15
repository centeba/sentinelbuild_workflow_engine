import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import bcrypt
import jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from api.models.organization import Organization
from api.models.user import User
from shared.config import get_settings

settings = get_settings()

# bcrypt operates on at most 72 bytes and (since 4.x) raises rather than
# silently truncating. Truncate explicitly so long passwords don't error.
# Using the bcrypt library directly avoids passlib, which is unmaintained and
# breaks against bcrypt >= 4.1 (``module 'bcrypt' has no attribute '__about__'``).
# The output is the standard ``$2b$`` format, so hashes written by the previous
# passlib[bcrypt] path still verify.
_BCRYPT_MAX_BYTES = 72


def hash_password(password: str) -> str:
    pw = password.encode("utf-8")[:_BCRYPT_MAX_BYTES]
    return bcrypt.hashpw(pw, bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(
            plain.encode("utf-8")[:_BCRYPT_MAX_BYTES],
            hashed.encode("utf-8"),
        )
    except (ValueError, TypeError):
        return False


def create_access_token(user_id: str, org_id: str) -> str:
    expire = datetime.now(UTC) + timedelta(minutes=settings.access_token_expire_minutes)
    return jwt.encode(
        {
            "sub": user_id,
            "org": org_id,
            "type": "access",
            "exp": expire,
            "jti": str(uuid.uuid4()),
        },
        settings.secret_key,
        algorithm=settings.algorithm,
    )


def create_refresh_token(user_id: str, org_id: str) -> str:
    expire = datetime.now(UTC) + timedelta(days=settings.refresh_token_expire_days)
    return jwt.encode(
        {
            "sub": user_id,
            "org": org_id,
            "type": "refresh",
            "exp": expire,
            "jti": str(uuid.uuid4()),
        },
        settings.secret_key,
        algorithm=settings.algorithm,
    )


def decode_token(token: str) -> dict[str, Any]:
    decoded: dict[str, Any] = jwt.decode(
        token, settings.secret_key, algorithms=[settings.algorithm]
    )
    return decoded


async def register(
    db: AsyncSession, org_name: str, org_slug: str, email: str, password: str
) -> tuple[Organization, User]:
    org = Organization(name=org_name, slug=org_slug)
    db.add(org)
    await db.flush()

    user = User(
        org_id=org.id,
        email=email,
        password_hash=hash_password(password),
        role="admin",
    )
    db.add(user)
    await db.flush()
    return org, user


async def authenticate(db: AsyncSession, email: str, password: str) -> User | None:
    result = await db.execute(
        select(User).where(User.email == email, User.is_active == True)
    )
    user = result.scalar_one_or_none()
    if user and verify_password(password, user.password_hash):
        return user
    return None
