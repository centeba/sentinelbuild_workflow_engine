"""
API tests for /api/v1/auth — register, login, refresh, /me.

All database calls are mocked; no live PostgreSQL required.
"""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from tests.conftest import TEST_ORG_ID, TEST_USER_ID, FakeCurrentUser, make_mock_db


@pytest.fixture(autouse=True)
def _enable_standalone_auth(monkeypatch):
    """The register/login routes are gated behind ``settings.standalone_auth``
    (off by default — auth is delegated to User Master, so the routes return
    501). These tests exercise the standalone flow, so enable the flag for the
    duration of the module. ``get_settings`` is cached, so the route sees the
    same instance we patch here."""
    from shared.config import get_settings

    monkeypatch.setattr(get_settings(), "standalone_auth", True, raising=False)
    yield


# ── helpers ───────────────────────────────────────────────────────────────────


def _fake_org():
    org = MagicMock()
    org.id = TEST_ORG_ID
    org.name = "Test Org"
    org.slug = "test-org"
    return org


def _fake_user():
    u = MagicMock()
    u.id = TEST_USER_ID
    u.org_id = TEST_ORG_ID
    u.email = "test@example.com"
    u.role = "admin"
    u.is_active = True
    u.password_hash = "hashed"
    return u


def _make_client(db=None):
    """Return a TestClient with DB mocked and NO auth override (auth tests need real auth flow)."""
    from api.main import app
    from shared.db import get_db

    _db = db or make_mock_db()

    async def override_db():
        yield _db

    app.dependency_overrides[get_db] = override_db

    return TestClient(app, raise_server_exceptions=False)


def _make_authed_client():
    """Return a TestClient with both DB and current_user mocked."""
    from api.deps import get_current_user
    from api.main import app
    from shared.db import get_db

    async def override_db():
        yield make_mock_db()

    async def override_user():
        return FakeCurrentUser()

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = override_user

    return TestClient(app, raise_server_exceptions=False)


# ── POST /api/v1/auth/register ────────────────────────────────────────────────


def test_register_success():
    """Successful registration returns 201 with access_token and refresh_token."""
    org = _fake_org()
    user = _fake_user()

    with patch(
        "api.services.auth_service.register", new=AsyncMock(return_value=(org, user))
    ):
        client = _make_client()
        resp = client.post(
            "/api/v1/auth/register",
            json={
                "org_name": "Test Org",
                "org_slug": "test-org",
                "email": "test@example.com",
                "password": "secret123",
            },
        )
    assert resp.status_code == 201
    body = resp.json()
    assert "access_token" in body
    assert "refresh_token" in body
    assert len(body["access_token"]) > 20
    client.app.dependency_overrides.clear()


def test_register_missing_email_returns_422():
    """Missing required field returns 422 Unprocessable Entity."""
    client = _make_client()
    resp = client.post(
        "/api/v1/auth/register",
        json={"org_name": "Test Org", "org_slug": "test-org", "password": "secret123"},
    )
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


def test_register_duplicate_raises_400():
    """If auth_service.register raises (e.g. duplicate email), endpoint returns 400."""
    with patch(
        "api.services.auth_service.register",
        new=AsyncMock(side_effect=Exception("duplicate key")),
    ):
        client = _make_client()
        resp = client.post(
            "/api/v1/auth/register",
            json={
                "org_name": "Test Org",
                "org_slug": "test-org",
                "email": "existing@example.com",
                "password": "secret123",
            },
        )
    assert resp.status_code == 400
    client.app.dependency_overrides.clear()


# ── POST /api/v1/auth/login ───────────────────────────────────────────────────


def test_login_success():
    """Valid credentials return 200 with tokens."""
    user = _fake_user()

    with patch(
        "api.services.auth_service.authenticate", new=AsyncMock(return_value=user)
    ):
        client = _make_client()
        resp = client.post(
            "/api/v1/auth/login",
            json={"email": "test@example.com", "password": "secret123"},
        )
    assert resp.status_code == 200
    body = resp.json()
    assert "access_token" in body
    assert "refresh_token" in body
    client.app.dependency_overrides.clear()


def test_login_invalid_credentials_returns_401():
    """authenticate() returning None yields 401."""
    with patch(
        "api.services.auth_service.authenticate", new=AsyncMock(return_value=None)
    ):
        client = _make_client()
        resp = client.post(
            "/api/v1/auth/login",
            json={"email": "bad@example.com", "password": "wrong"},
        )
    assert resp.status_code == 401
    client.app.dependency_overrides.clear()


def test_login_missing_password_returns_422():
    """Missing password field → 422."""
    client = _make_client()
    resp = client.post("/api/v1/auth/login", json={"email": "test@example.com"})
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


# ── POST /api/v1/auth/refresh ─────────────────────────────────────────────────


def test_refresh_success():
    """A valid refresh token returns 200 with a new access_token."""
    from api.services.auth_service import create_refresh_token

    refresh = create_refresh_token(str(TEST_USER_ID), str(TEST_ORG_ID))
    client = _make_client()
    resp = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
    assert resp.status_code == 200
    assert "access_token" in resp.json()
    client.app.dependency_overrides.clear()


def test_refresh_garbage_token_returns_401():
    """A garbage string as refresh token returns 401."""
    client = _make_client()
    resp = client.post("/api/v1/auth/refresh", json={"refresh_token": "not.a.token"})
    assert resp.status_code == 401
    client.app.dependency_overrides.clear()


def test_refresh_access_token_as_refresh_returns_401():
    """Passing an access token where a refresh token is expected returns 401 (wrong type)."""
    from api.services.auth_service import create_access_token

    access = create_access_token(str(TEST_USER_ID), str(TEST_ORG_ID))
    client = _make_client()
    resp = client.post("/api/v1/auth/refresh", json={"refresh_token": access})
    assert resp.status_code == 401
    client.app.dependency_overrides.clear()


# ── GET /api/v1/auth/me ───────────────────────────────────────────────────────


def test_me_with_mocked_auth_returns_200():
    """GET /me with mocked current user returns 200 and user fields."""
    client = _make_authed_client()
    resp = client.get("/api/v1/auth/me")
    assert resp.status_code == 200
    body = resp.json()
    assert body["email"] == "test@example.com"
    client.app.dependency_overrides.clear()


def test_me_without_auth_header_returns_401_or_403():
    """GET /me with no Authorization header returns 401 or 403 (bearer scheme)."""
    from api.main import app

    # Clear all overrides to test true unauthenticated access
    app.dependency_overrides.clear()
    client = TestClient(app, raise_server_exceptions=False)
    resp = client.get("/api/v1/auth/me")
    assert resp.status_code in (401, 403)
