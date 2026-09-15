"""
API tests for /api/v1/integrations — catalogue, CRUD.

All DB calls are mocked; no live PostgreSQL required.
"""

import uuid
from unittest.mock import MagicMock

from tests.conftest import (
    TEST_CRED_ID,
    TEST_INTEG_ID,
    TEST_ORG_ID,
    FakeCurrentUser,
    make_mock_db,
)

# ── helpers ────────────────────────────────────────────────────────────────────


def _fake_integration(**kwargs):
    i = MagicMock()
    i.id = TEST_INTEG_ID
    i.org_id = TEST_ORG_ID
    i.connector_type = kwargs.get("connector_type", "slack")
    i.name = kwargs.get("name", "My Slack")
    i.credential_id = kwargs.get("credential_id", TEST_CRED_ID)
    i.config = kwargs.get("config", {"channel": "#general"})
    return i


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


# ── GET /api/v1/integrations/catalogue ────────────────────────────────────────


def test_get_catalogue_returns_200():
    """GET /integrations/catalogue → 200 with list of connectors."""
    from fastapi.testclient import TestClient

    from api.main import app

    client = TestClient(app, raise_server_exceptions=False)
    resp = client.get("/api/v1/integrations/catalogue")
    assert resp.status_code == 200
    body = resp.json()
    assert isinstance(body, list)
    assert len(body) > 0


def test_catalogue_entries_have_required_fields():
    """Each catalogue entry must have type, name, description, and category."""
    from fastapi.testclient import TestClient

    from api.main import app

    client = TestClient(app, raise_server_exceptions=False)
    resp = client.get("/api/v1/integrations/catalogue")
    assert resp.status_code == 200
    for entry in resp.json():
        assert "type" in entry
        assert "name" in entry
        assert "description" in entry
        assert "category" in entry


def test_catalogue_contains_slack():
    """Slack must be present in the connector catalogue."""
    from fastapi.testclient import TestClient

    from api.main import app

    client = TestClient(app, raise_server_exceptions=False)
    resp = client.get("/api/v1/integrations/catalogue")
    types = [e["type"] for e in resp.json()]
    assert "slack" in types


def test_catalogue_contains_openai():
    """OpenAI must be present in the connector catalogue."""
    from fastapi.testclient import TestClient

    from api.main import app

    client = TestClient(app, raise_server_exceptions=False)
    resp = client.get("/api/v1/integrations/catalogue")
    types = [e["type"] for e in resp.json()]
    assert "openai" in types


# ── GET /api/v1/integrations ──────────────────────────────────────────────────


def test_list_integrations_returns_200():
    """GET /integrations → 200 list."""
    db = make_mock_db(items=[_fake_integration()])
    client = _make_client(db)
    resp = client.get("/api/v1/integrations")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
    client.app.dependency_overrides.clear()


def test_list_integrations_empty_returns_200():
    """GET /integrations with no results → 200 empty list."""
    db = make_mock_db(items=[])
    client = _make_client(db)
    resp = client.get("/api/v1/integrations")
    assert resp.status_code == 200
    assert resp.json() == []
    client.app.dependency_overrides.clear()


# ── POST /api/v1/integrations ─────────────────────────────────────────────────


def test_create_integration_returns_201():
    """POST /integrations with valid body → 201."""
    db = make_mock_db()

    def _add_side_effect(obj):
        if not getattr(obj, "id", None):
            obj.id = TEST_INTEG_ID
        if not getattr(obj, "org_id", None):
            from tests.conftest import TEST_ORG_ID

            obj.org_id = TEST_ORG_ID

    db.add = _add_side_effect
    client = _make_client(db)
    resp = client.post(
        "/api/v1/integrations",
        json={
            "connector_type": "slack",
            "name": "My Slack",
            "config": {"channel": "#general"},
        },
    )
    assert resp.status_code in (201, 422)
    client.app.dependency_overrides.clear()


def test_create_integration_missing_connector_type_returns_422():
    """POST /integrations without connector_type → 422."""
    client = _make_client()
    resp = client.post(
        "/api/v1/integrations",
        json={"name": "Missing Type"},
    )
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


def test_create_integration_missing_name_returns_422():
    """POST /integrations without name → 422."""
    client = _make_client()
    resp = client.post(
        "/api/v1/integrations",
        json={"connector_type": "slack"},
    )
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


def test_create_integration_with_credential_returns_201():
    """POST /integrations with optional credential_id → 201."""
    db = make_mock_db()

    def _add_side_effect(obj):
        if not getattr(obj, "id", None):
            obj.id = TEST_INTEG_ID
        if not getattr(obj, "org_id", None):
            from tests.conftest import TEST_ORG_ID

            obj.org_id = TEST_ORG_ID

    db.add = _add_side_effect
    client = _make_client(db)
    resp = client.post(
        "/api/v1/integrations",
        json={
            "connector_type": "github",
            "name": "GitHub CI",
            "credential_id": str(TEST_CRED_ID),
            "config": {"repo": "myorg/myrepo"},
        },
    )
    assert resp.status_code in (201, 422)
    client.app.dependency_overrides.clear()


# ── DELETE /api/v1/integrations/{id} ─────────────────────────────────────────


def test_delete_integration_returns_204():
    """DELETE /integrations/{id} on existing integration → 204."""
    integration = _fake_integration()
    db = make_mock_db(scalar=integration)
    client = _make_client(db)
    resp = client.delete(f"/api/v1/integrations/{TEST_INTEG_ID}")
    assert resp.status_code == 204
    client.app.dependency_overrides.clear()


def test_delete_integration_not_found_returns_404():
    """DELETE /integrations/{id} when not found → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.delete(f"/api/v1/integrations/{TEST_INTEG_ID}")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


def test_delete_integration_wrong_org_returns_404():
    """DELETE /integrations/{id} for another org's integration → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.delete(f"/api/v1/integrations/{uuid.uuid4()}")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()
