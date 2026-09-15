"""
Unit tests for api.services.identity_sync — User Master identity provisioning.

All DB interactions are mocked with AsyncMock; no live database required.
"""

import uuid
from unittest.mock import AsyncMock, MagicMock

import pytest

from api.services.identity_sync import (
    _EXTERNAL_HASH,
    _PLATFORM_ORG_NAME,
    _PLATFORM_ORG_SLUG,
    _ROLE_MAP,
    sync_identity,
)

# ── helpers ────────────────────────────────────────────────────────────────────

TEST_USER_ID = uuid.uuid4()
TEST_COMPANY_ID = uuid.uuid4()
TEST_ORG_ID = uuid.uuid4()

FULL_PAYLOAD = {
    "sub": str(TEST_USER_ID),
    "scope": "full",
    "company_id": str(TEST_COMPANY_ID),
    "company_name": "Acme Corp",
    "company_slug": "acme-corp",
    "role": "company_admin",
    "email": "alice@acme.com",
}


def _make_org(**kwargs):
    org = MagicMock()
    org.id = kwargs.get("id", TEST_ORG_ID)
    org.name = kwargs.get("name", "Acme Corp")
    org.slug = kwargs.get("slug", "acme-corp")
    return org


def _make_user(**kwargs):
    user = MagicMock()
    user.id = kwargs.get("id", TEST_USER_ID)
    user.org_id = kwargs.get("org_id", TEST_ORG_ID)
    user.email = kwargs.get("email", "alice@acme.com")
    user.role = kwargs.get("role", "admin")
    user.is_active = kwargs.get("is_active", True)
    user.password_hash = kwargs.get("password_hash", _EXTERNAL_HASH)
    return user


def _make_db(org=None, user=None):
    """Build a mock AsyncSession that returns `org` on first execute and `user` on second."""
    db = MagicMock()

    from tests.conftest import make_db_result

    org_result = make_db_result(scalar=org)
    user_result = make_db_result(scalar=user)

    call_count = [0]

    async def execute_side_effect(*a, **kw):
        call_count[0] += 1
        return org_result if call_count[0] == 1 else user_result

    db.execute = AsyncMock(side_effect=execute_side_effect)
    db.add = MagicMock()
    db.flush = AsyncMock()
    db.rollback = AsyncMock()
    return db


# ── Role mapping ───────────────────────────────────────────────────────────────


def test_role_map_platform_admin_becomes_admin():
    assert _ROLE_MAP["platform_admin"] == "admin"


def test_role_map_system_admin_becomes_admin():
    # SentinelBuild's canonical top-level role alongside the legacy platform_admin.
    assert _ROLE_MAP["system_admin"] == "admin"


def test_role_map_company_admin_becomes_admin():
    assert _ROLE_MAP["company_admin"] == "admin"


def test_role_map_user_becomes_member():
    assert _ROLE_MAP["user"] == "member"


def test_role_map_member_and_viewer_become_member():
    # Explicit entries added when we unified on the SentinelBuild role vocabulary.
    assert _ROLE_MAP["member"] == "member"
    assert _ROLE_MAP["viewer"] == "member"


def test_role_map_unknown_defaults_to_member():
    assert _ROLE_MAP.get("superuser", "member") == "member"


# ── Missing company_id raises ──────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_missing_company_id_raises_value_error():
    db = MagicMock()
    payload = {**FULL_PAYLOAD, "company_id": None}
    with pytest.raises(ValueError, match="company_id"):
        await sync_identity(db, payload)


@pytest.mark.asyncio
async def test_empty_company_id_raises_value_error():
    db = MagicMock()
    payload = {k: v for k, v in FULL_PAYLOAD.items() if k != "company_id"}
    with pytest.raises(ValueError, match="company_id"):
        await sync_identity(db, payload)


# ── Happy path: org and user both exist ───────────────────────────────────────


@pytest.mark.asyncio
async def test_existing_org_and_user_returned_unchanged():
    org = _make_org()
    user = _make_user(role="admin", org_id=TEST_ORG_ID)
    db = _make_db(org=org, user=user)

    result = await sync_identity(db, FULL_PAYLOAD)

    assert result is user
    db.add.assert_not_called()
    db.flush.assert_not_called()


# ── New org is created when not found ─────────────────────────────────────────


@pytest.mark.asyncio
async def test_new_org_created_when_not_found():
    user = _make_user()
    db = _make_db(org=None, user=user)

    await sync_identity(db, FULL_PAYLOAD)

    # db.add should have been called with a new Organization
    assert db.add.called
    added = db.add.call_args_list[0][0][0]
    assert added.name == "Acme Corp"
    assert added.slug == "acme-corp"


# ── New user is created when not found ────────────────────────────────────────


@pytest.mark.asyncio
async def test_new_user_created_when_not_found():
    org = _make_org()
    db = _make_db(org=org, user=None)

    await sync_identity(db, FULL_PAYLOAD)

    assert db.add.called
    added = db.add.call_args_list[0][0][0]
    assert str(added.id) == str(TEST_USER_ID)
    assert added.email == "alice@acme.com"
    assert added.role == "admin"  # company_admin maps to admin
    assert added.is_active is True
    assert added.password_hash == _EXTERNAL_HASH


# ── External hash can never match a real bcrypt hash ──────────────────────────


def test_external_hash_not_valid_bcrypt():
    assert not _EXTERNAL_HASH.startswith("$2b$")
    assert not _EXTERNAL_HASH.startswith("$argon2")


# ── Role sync: user role is updated when it changes in User Master ─────────────


@pytest.mark.asyncio
async def test_role_updated_when_changed_in_user_master():
    org = _make_org()
    user = _make_user(role="member")  # old role
    db = _make_db(org=org, user=user)

    # payload says company_admin → should map to admin
    payload = {**FULL_PAYLOAD, "role": "company_admin"}
    await sync_identity(db, payload)

    assert user.role == "admin"
    db.flush.assert_awaited()


# ── Org sync: user org_id is updated when company changes ─────────────────────


@pytest.mark.asyncio
async def test_org_updated_when_user_moves_company():
    new_org_id = uuid.uuid4()
    org = _make_org(id=new_org_id, slug="new-company")
    user = _make_user(org_id=TEST_ORG_ID)  # old org
    db = _make_db(org=org, user=user)

    payload = {
        **FULL_PAYLOAD,
        "company_slug": "new-company",
        "company_name": "New Company",
    }
    await sync_identity(db, payload)

    assert user.org_id == new_org_id
    db.flush.assert_awaited()


# ── Reactivation: inactive user is re-activated ───────────────────────────────


@pytest.mark.asyncio
async def test_inactive_user_reactivated():
    org = _make_org()
    user = _make_user(is_active=False)
    db = _make_db(org=org, user=user)

    await sync_identity(db, FULL_PAYLOAD)

    assert user.is_active is True
    db.flush.assert_awaited()


# ── Platform admins without company_id get a synthetic "platform" org ─────────
#
# SentinelBuild policy: system_admin / platform_admin are cross-tenant accounts
# that don't belong to any real company. Mit Stack still needs an org context
# for every user, so identity_sync auto-provisions a single sentinel
# organisation with slug `__platform__` and assigns every platform admin to it.


@pytest.mark.asyncio
async def test_platform_admin_no_company_uses_synthetic_platform_org():
    org = _make_org(slug=_PLATFORM_ORG_SLUG, name=_PLATFORM_ORG_NAME)
    user = _make_user()
    db = _make_db(org=org, user=user)

    payload = {
        "sub": str(TEST_USER_ID),
        "scope": "full",
        "role": "platform_admin",
        "email": "superadmin@internal.com",
        # No company_id — platform_admin has no company
    }
    result = await sync_identity(db, payload)

    assert result is user


@pytest.mark.asyncio
async def test_system_admin_no_company_uses_synthetic_platform_org():
    # Same as above for the canonical "system_admin" role name.
    org = _make_org(slug=_PLATFORM_ORG_SLUG, name=_PLATFORM_ORG_NAME)
    user = _make_user()
    db = _make_db(org=org, user=user)

    payload = {
        "sub": str(TEST_USER_ID),
        "scope": "full",
        "role": "system_admin",
        "email": "admin@sentinelbuild.dev",
    }
    result = await sync_identity(db, payload)

    assert result is user


@pytest.mark.asyncio
async def test_platform_admin_creates_platform_org_on_first_login():
    # First time any platform admin logs in, the synthetic org doesn't exist
    # yet — sync_identity must create it.
    user = _make_user()
    db = _make_db(org=None, user=user)

    payload = {
        "sub": str(TEST_USER_ID),
        "scope": "full",
        "role": "system_admin",
        "email": "admin@sentinelbuild.dev",
    }
    await sync_identity(db, payload)

    assert db.add.called
    added = db.add.call_args_list[0][0][0]
    assert added.slug == _PLATFORM_ORG_SLUG
    assert added.name == _PLATFORM_ORG_NAME


@pytest.mark.asyncio
async def test_regular_user_without_company_still_rejected():
    # The platform-org fallback ONLY applies to system_admin / platform_admin.
    # A regular user with no company must still be rejected so we don't
    # silently dump them into the platform org.
    db = MagicMock()
    payload = {
        "sub": str(TEST_USER_ID),
        "scope": "full",
        "role": "user",
        "email": "alice@unknown.com",
        # No company_id
    }
    with pytest.raises(ValueError, match="company_id"):
        await sync_identity(db, payload)


# ── Slug/name fallback when claims are absent ─────────────────────────────────


@pytest.mark.asyncio
async def test_company_slug_falls_back_to_company_id():
    org = _make_org(slug=str(TEST_COMPANY_ID))
    user = _make_user()
    db = _make_db(org=org, user=user)

    # No company_slug or company_name in payload
    payload = {
        "sub": str(TEST_USER_ID),
        "scope": "full",
        "company_id": str(TEST_COMPANY_ID),
        "role": "user",
        "email": "bob@example.com",
    }
    result = await sync_identity(db, payload)
    assert result is user
