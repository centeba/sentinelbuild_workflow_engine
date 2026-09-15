"""Shared test fixtures for the Mit Stack backend test suite."""

import uuid
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi.testclient import TestClient

# ── Canonical test IDs ────────────────────────────────────────────────────────
TEST_ORG_ID = uuid.UUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
TEST_USER_ID = uuid.UUID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
TEST_RULE_ID = uuid.UUID("cccccccc-cccc-cccc-cccc-cccccccccccc")
TEST_FLOW_ID = uuid.UUID("dddddddd-dddd-dddd-dddd-dddddddddddd")
TEST_WF_ID = uuid.UUID("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")
TEST_FORM_ID = uuid.UUID("ffffffff-ffff-ffff-ffff-ffffffffffff")
TEST_CRED_ID = uuid.UUID("11111111-1111-1111-1111-111111111111")
TEST_EXEC_ID = uuid.UUID("22222222-2222-2222-2222-222222222222")
TEST_APPR_ID = uuid.UUID("33333333-3333-3333-3333-333333333333")
TEST_INTEG_ID = uuid.UUID("44444444-4444-4444-4444-444444444444")


def _scalars(items):
    m = MagicMock()
    m.all.return_value = list(items)
    m.first.return_value = items[0] if items else None
    return m


def make_db_result(scalar=None, items=None):
    """Build a mock result from db.execute(...)."""
    r = MagicMock()
    r.scalar_one_or_none.return_value = scalar
    r.scalar.return_value = scalar
    r.scalars.return_value = _scalars(items or [])
    r.fetchone.return_value = scalar
    # Support unique().scalars().all() pattern used in executions list
    unique_mock = MagicMock()
    unique_mock.scalars.return_value = _scalars(items or [])
    r.unique.return_value = unique_mock
    return r


def make_mock_db(scalar=None, items=None):
    """AsyncMock session pre-configured with a default result."""
    db = AsyncMock()
    db.execute = AsyncMock(return_value=make_db_result(scalar, items))
    db.add = MagicMock()
    db.flush = AsyncMock()
    db.delete = AsyncMock()
    db.rollback = AsyncMock()
    db.close = AsyncMock()
    db.commit = AsyncMock()
    return db


class _FakeUser:
    id = str(TEST_USER_ID)  # UserResponse expects str, not UUID
    org_id = str(TEST_ORG_ID)  # UserResponse expects str, not UUID
    email = "test@example.com"
    role = "admin"
    is_active = True


class FakeCurrentUser:
    user = _FakeUser()
    user_id = TEST_USER_ID
    org_id = TEST_ORG_ID
    role = "admin"
    email = "test@example.com"
    # Office scoping (added by the office-scope feature): model a company-wide
    # caller with no office filter. Handlers call office_where/office_scope/
    # office_id_value on CurrentUser.
    office_id = None
    office_scope = None
    office_id_value = None

    def office_clause(self, office_col):
        return None

    def office_where(self, office_col):
        return []


@pytest.fixture
def auth_client(request):
    """TestClient with DB and current user mocked. Use make_mock_db() for custom returns."""
    from api.deps import get_current_user
    from api.main import app
    from shared.db import get_db

    db = getattr(request, "param", None) or make_mock_db()

    async def override_db():
        yield db

    async def override_user():
        return FakeCurrentUser()

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = override_user

    with TestClient(app, raise_server_exceptions=False) as c:
        yield c

    app.dependency_overrides.clear()


@pytest.fixture
def anon_client():
    """TestClient without auth mock (public endpoints only)."""
    from api.main import app
    from shared.db import get_db

    db = make_mock_db()

    async def override_db():
        yield db

    app.dependency_overrides[get_db] = override_db

    with TestClient(app, raise_server_exceptions=False) as c:
        yield c

    app.dependency_overrides.clear()
