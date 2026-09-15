"""
API tests for /api/v1/credentials — list, create, delete.

All DB calls are mocked; no live PostgreSQL required.
Credential encryption is mocked so no ENCRYPTION_KEY env var is needed.
"""

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

from tests.conftest import (
    TEST_CRED_ID,
    TEST_ORG_ID,
    TEST_USER_ID,
    FakeCurrentUser,
    make_mock_db,
)

# ── helpers ────────────────────────────────────────────────────────────────────


def _fake_credential(**kwargs):
    import datetime

    c = MagicMock()
    c.id = TEST_CRED_ID
    c.org_id = TEST_ORG_ID
    c.created_by = TEST_USER_ID
    c.name = kwargs.get("name", "Slack API Key")
    c.type = kwargs.get("type", "api_key")
    # The Credential model stores metadata in the column 'metadata_' (Python attr)
    c.metadata_ = kwargs.get("metadata", {})
    # encrypted_data intentionally omitted from responses
    c.created_at = datetime.datetime(2024, 1, 1, tzinfo=datetime.UTC)
    return c


def _make_client(db=None):
    from fastapi.testclient import TestClient

    from api.deps import get_current_user
    from api.main import app
    from shared.db import get_db

    _db = db or make_mock_db()

    async def override_db():
        yield _db

    async def override_user():
        return FakeCurrentUser()

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = override_user

    return TestClient(app, raise_server_exceptions=False)


# ── GET /api/v1/credentials ───────────────────────────────────────────────────


def test_list_credentials_returns_200():
    """GET /credentials → 200 list (encrypted_data not exposed)."""
    db = make_mock_db(items=[_fake_credential()])
    client = _make_client(db)
    resp = client.get("/api/v1/credentials")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)
    # Encrypted secret should never appear in list response
    for item in data:
        assert "encrypted_data" not in item
        assert "secret_data" not in item
    client.app.dependency_overrides.clear()


def test_list_credentials_empty_returns_200():
    """GET /credentials with no entries → 200 empty list."""
    db = make_mock_db(items=[])
    client = _make_client(db)
    resp = client.get("/api/v1/credentials")
    assert resp.status_code == 200
    assert resp.json() == []
    client.app.dependency_overrides.clear()


# ── POST /api/v1/credentials ──────────────────────────────────────────────────


def test_create_credential_returns_201():
    """POST /credentials with valid body → 201 (secret never returned)."""
    cred = _fake_credential()
    db = make_mock_db()

    with patch(
        "api.routers.credentials.create_credential",
        new=AsyncMock(return_value=cred),
    ):
        client = _make_client(db)
        resp = client.post(
            "/api/v1/credentials",
            json={
                "name": "Slack API Key",
                "type": "api_key",
                "secret_data": {"token": "xoxb-secret"},
                "metadata": {"workspace": "my-team"},
            },
        )
    assert resp.status_code == 201
    body = resp.json()
    # Secret must not be echoed back
    assert "secret_data" not in body
    assert "encrypted_data" not in body
    client.app.dependency_overrides.clear()


def test_create_credential_missing_name_returns_422():
    """POST /credentials without name → 422."""
    client = _make_client()
    resp = client.post(
        "/api/v1/credentials",
        json={"type": "api_key", "secret_data": {"token": "abc"}},
    )
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


def test_create_credential_missing_type_returns_422():
    """POST /credentials without type → 422."""
    client = _make_client()
    resp = client.post(
        "/api/v1/credentials",
        json={"name": "My Key", "secret_data": {"token": "abc"}},
    )
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


def test_create_credential_missing_secret_returns_422():
    """POST /credentials without secret_data → 422."""
    client = _make_client()
    resp = client.post(
        "/api/v1/credentials",
        json={"name": "My Key", "type": "api_key"},
    )
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


def test_create_credential_service_error_returns_non_201():
    """If credential service raises, endpoint should not return 201."""
    db = make_mock_db()

    with patch(
        "api.services.credential_service.create_credential",
        new=AsyncMock(side_effect=RuntimeError("Encryption key not set")),
    ):
        client = _make_client(db)
        resp = client.post(
            "/api/v1/credentials",
            json={
                "name": "Broken",
                "type": "api_key",
                "secret_data": {"token": "x"},
            },
        )
    assert resp.status_code != 201
    client.app.dependency_overrides.clear()


# ── DELETE /api/v1/credentials/{id} ──────────────────────────────────────────


def test_delete_credential_returns_204():
    """DELETE /credentials/{id} on existing credential → 204."""
    cred = _fake_credential()
    db = make_mock_db(scalar=cred)
    client = _make_client(db)
    resp = client.delete(f"/api/v1/credentials/{TEST_CRED_ID}")
    assert resp.status_code == 204
    client.app.dependency_overrides.clear()


def test_delete_credential_not_found_returns_404():
    """DELETE /credentials/{id} when not found → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.delete(f"/api/v1/credentials/{TEST_CRED_ID}")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


def test_delete_credential_wrong_org_returns_404():
    """DELETE /credentials/{id} for a credential belonging to another org → 404."""
    # DB returns None because org_id filter doesn't match
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.delete(f"/api/v1/credentials/{uuid.uuid4()}")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()
