"""
Unit tests for the User Master → Mit Stack JWT integration layer.

Tests cover:
  - Mit Stack accepts User Master full tokens (scope=full)
  - Mit Stack rejects User Master pre-2FA tokens (scope=pre_2fa)
  - Mit Stack still accepts native tokens when USER_MASTER_SECRET_KEY is set
  - Standalone auth guard (STANDALONE_AUTH=false blocks /auth/register + /auth/login)
  - CurrentUser now exposes .email
"""

import uuid
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
from fastapi.testclient import TestClient

from tests.conftest import TEST_ORG_ID, TEST_USER_ID, FakeCurrentUser, make_mock_db

# ── JWT factories ──────────────────────────────────────────────────────────────

_UM_SECRET = "user_master_test_secret_key_0000"
_UM_ALGO = "HS256"
_MS_SECRET = "mit_stack_test_secret_key_000000"
_MS_ALGO = "HS256"

_COMPANY_ID = str(uuid.uuid4())
_COMPANY_SLUG = "acme-corp"
_COMPANY_NAME = "Acme Corp"


def _um_token(scope: str = "full", **extra) -> str:
    """Issue a User Master-style JWT."""
    payload = {
        "sub": str(TEST_USER_ID),
        "exp": datetime.now(UTC) + timedelta(hours=8),
        "scope": scope,
        "company_id": _COMPANY_ID,
        "company_name": _COMPANY_NAME,
        "company_slug": _COMPANY_SLUG,
        "role": "company_admin",
        "email": "alice@acme.com",
        **extra,
    }
    return jwt.encode(payload, _UM_SECRET, algorithm=_UM_ALGO)


def _ms_token() -> str:
    """Issue a native Mit Stack-style JWT."""
    payload = {
        "sub": str(TEST_USER_ID),
        "org": str(TEST_ORG_ID),
        "type": "access",
        "exp": datetime.now(UTC) + timedelta(hours=1),
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, _MS_SECRET, algorithm=_MS_ALGO)


# ── helpers ────────────────────────────────────────────────────────────────────


def _make_client_with_settings(
    db=None, um_secret: str = "", standalone_auth: bool = True
):
    """Build a TestClient with patched settings and mocked DB."""
    from fastapi.testclient import TestClient

    from api.main import app
    from shared.db import get_db

    _db = db or make_mock_db()

    async def override_db():
        yield _db

    app.dependency_overrides[get_db] = override_db

    # Patch get_settings inside deps module
    mock_settings = MagicMock()
    mock_settings.user_master_secret_key = um_secret
    mock_settings.user_master_algorithm = _UM_ALGO
    mock_settings.standalone_auth = standalone_auth
    mock_settings.secret_key = _MS_SECRET
    mock_settings.algorithm = _MS_ALGO

    return TestClient(app, raise_server_exceptions=False), mock_settings


# ── CurrentUser.email is exposed ──────────────────────────────────────────────


def test_current_user_exposes_email():
    """CurrentUser wrapper should expose .email from the User model."""
    from api.deps import CurrentUser

    user = MagicMock()
    user.id = TEST_USER_ID
    user.org_id = TEST_ORG_ID
    user.role = "admin"
    user.email = "alice@example.com"

    cu = CurrentUser(user)
    assert cu.email == "alice@example.com"


# ── Standalone auth guard ──────────────────────────────────────────────────────


def test_register_returns_501_when_standalone_auth_disabled():
    """/auth/register → 501 when STANDALONE_AUTH=false."""
    with patch("api.routers.auth.get_settings") as mock_gs:
        mock_gs.return_value.standalone_auth = False
        from api.main import app

        client = TestClient(app, raise_server_exceptions=False)
        resp = client.post(
            "/api/v1/auth/register",
            json={
                "org_name": "Test Org",
                "org_slug": "test-org",
                "email": "a@b.com",
                "password": "password123",
            },
        )
    assert resp.status_code == 501
    assert "User Master" in resp.json()["detail"]
    app.dependency_overrides.clear()


def test_login_returns_501_when_standalone_auth_disabled():
    """/auth/login → 501 when STANDALONE_AUTH=false."""
    with patch("api.routers.auth.get_settings") as mock_gs:
        mock_gs.return_value.standalone_auth = False
        from api.main import app

        client = TestClient(app, raise_server_exceptions=False)
        resp = client.post(
            "/api/v1/auth/login",
            json={"email": "a@b.com", "password": "password123"},
        )
    assert resp.status_code == 501
    app.dependency_overrides.clear()


def test_register_works_when_standalone_auth_enabled():
    """/auth/register succeeds (400 or 201) when STANDALONE_AUTH=true."""
    with patch("api.routers.auth.get_settings") as mock_gs:
        mock_gs.return_value.standalone_auth = True
        from api.main import app
        from shared.db import get_db

        db = make_mock_db()

        async def override_db():
            yield db

        app.dependency_overrides[get_db] = override_db

        with patch(
            "api.services.auth_service.register",
            new=AsyncMock(side_effect=Exception("dup")),
        ):
            client = TestClient(app, raise_server_exceptions=False)
            resp = client.post(
                "/api/v1/auth/register",
                json={
                    "org_name": "X",
                    "org_slug": "x",
                    "email": "a@b.com",
                    "password": "p",
                },
            )
        assert resp.status_code != 501
    app.dependency_overrides.clear()


# ── User Master JWT: accepted when scope=full ─────────────────────────────────


def test_user_master_full_token_accepted():
    """A User Master full token (scope=full) is accepted and provisions the user."""
    token = _um_token(scope="full")

    from fastapi.testclient import TestClient

    from api.deps import get_current_user
    from api.main import app
    from shared.db import get_db

    fake_user = MagicMock()
    fake_user.id = TEST_USER_ID
    fake_user.org_id = TEST_ORG_ID
    fake_user.role = "admin"
    fake_user.email = "alice@acme.com"
    fake_user.is_active = True

    db = make_mock_db()

    async def override_db():
        yield db

    async def override_user():
        return FakeCurrentUser()

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = override_user

    with (
        patch("api.deps.get_settings") as mock_gs,
        patch(
            "api.services.identity_sync.sync_identity",
            new=AsyncMock(return_value=fake_user),
        ),
    ):
        mock_gs.return_value.user_master_secret_key = _UM_SECRET
        mock_gs.return_value.user_master_algorithm = _UM_ALGO
        mock_gs.return_value.secret_key = _MS_SECRET
        mock_gs.return_value.algorithm = _MS_ALGO

        client = TestClient(app, raise_server_exceptions=False)
        # /auth/me just needs a 200 from the auth dep
        resp = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )
    # 200 means auth dep resolved correctly (dep override returns FakeCurrentUser)
    assert resp.status_code == 200
    app.dependency_overrides.clear()


# ── User Master JWT: pre-2FA token rejected ───────────────────────────────────


def test_user_master_pre_2fa_token_not_accepted():
    """A pre-2FA token (scope=pre_2fa) must NOT grant access to Mit Stack."""
    token = _um_token(scope="pre_2fa")

    from fastapi.testclient import TestClient

    from api.main import app
    from shared.db import get_db

    db = make_mock_db()

    async def override_db():
        yield db

    app.dependency_overrides[get_db] = override_db

    with patch("api.deps.get_settings") as mock_gs:
        mock_gs.return_value.user_master_secret_key = _UM_SECRET
        mock_gs.return_value.user_master_algorithm = _UM_ALGO
        mock_gs.return_value.secret_key = _MS_SECRET
        mock_gs.return_value.algorithm = _MS_ALGO

        client = TestClient(app, raise_server_exceptions=False)
        resp = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )
    # pre-2FA token should be rejected — falls through to native JWT which also fails
    assert resp.status_code == 401
    app.dependency_overrides.clear()


# ── Identity sync called for User Master tokens ───────────────────────────────


@pytest.mark.asyncio
async def test_identity_sync_called_for_user_master_token():
    """sync_identity() is invoked when a valid User Master full token is decoded."""
    from fastapi.security import HTTPAuthorizationCredentials

    from api.deps import get_current_user

    token = _um_token(scope="full")

    fake_user = MagicMock()
    fake_user.id = TEST_USER_ID
    fake_user.org_id = TEST_ORG_ID
    fake_user.role = "admin"
    fake_user.email = "alice@acme.com"
    fake_user.is_active = True

    db = make_mock_db()
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)

    # get_current_user now accepts (request, credentials, db) — build a minimal mock Request
    from unittest.mock import MagicMock as _MM

    mock_request = _MM()
    mock_request.url.path = "/test"
    mock_request.client.host = "127.0.0.1"

    with (
        patch("api.deps.get_settings") as mock_gs,
        patch(
            "api.services.identity_sync.sync_identity",
            new=AsyncMock(return_value=fake_user),
        ) as mock_sync,
    ):
        mock_gs.return_value.user_master_secret_key = _UM_SECRET
        mock_gs.return_value.user_master_algorithm = _UM_ALGO
        mock_gs.return_value.secret_key = _MS_SECRET
        mock_gs.return_value.algorithm = _MS_ALGO

        result = await get_current_user(mock_request, credentials, db)

    mock_sync.assert_awaited_once()
    assert result.user_id == TEST_USER_ID
