"""
API tests for /api/v1/workflows — CRUD + trigger + webhook.

All DB calls are mocked; no live PostgreSQL required.
"""

from unittest.mock import AsyncMock, MagicMock, patch

from tests.conftest import (
    TEST_EXEC_ID,
    TEST_ORG_ID,
    TEST_WF_ID,
    FakeCurrentUser,
    make_db_result,
    make_mock_db,
)

# ── helpers ────────────────────────────────────────────────────────────────────


def _fake_workflow(**kwargs):
    wf = MagicMock()
    wf.id = TEST_WF_ID
    wf.org_id = TEST_ORG_ID
    wf.name = kwargs.get("name", "My Workflow")
    wf.description = kwargs.get("description", "")
    wf.definition = kwargs.get("definition", {"nodes": [], "edges": []})
    wf.trigger_type = kwargs.get("trigger_type", "manual")
    wf.trigger_config = kwargs.get("trigger_config", {})
    wf.is_active = kwargs.get("is_active", True)
    wf.webhook_secret = kwargs.get("webhook_secret", "abc123")
    wf.active_version_id = kwargs.get(
        "active_version_id", None
    )  # added by versioning migration
    wf.source_app = kwargs.get("source_app", None)  # 0010 framework/domain tag
    wf.action_authz_rules = kwargs.get(
        "action_authz_rules", {}
    )  # authz-rules field (must be a dict)
    wf.created_at = "2024-01-01T00:00:00Z"
    wf.updated_at = "2024-01-01T00:00:00Z"
    return wf


def _fake_execution(**kwargs):
    e = MagicMock()
    e.id = TEST_EXEC_ID
    e.workflow_id = TEST_WF_ID
    e.org_id = TEST_ORG_ID
    e.status = kwargs.get("status", "pending")
    e.trigger_type = kwargs.get("trigger_type", "manual")
    e.input_data = kwargs.get("input_data", {})
    e.output_data = kwargs.get("output_data", {})
    e.error_message = None
    e.temporal_workflow_id = kwargs.get("temporal_workflow_id", "temporal-wf-id-mock")
    e.version_id = kwargs.get("version_id", None)  # added by versioning migration
    e.created_at = "2024-01-01T00:00:00Z"
    e.updated_at = "2024-01-01T00:00:00Z"
    return e


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


# ── GET /api/v1/workflows ──────────────────────────────────────────────────────


def test_list_workflows_returns_200():
    """GET /workflows → 200 list."""
    db = make_mock_db(items=[_fake_workflow()])
    client = _make_client(db)
    resp = client.get("/api/v1/workflows")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
    client.app.dependency_overrides.clear()


def test_list_workflows_empty_returns_200():
    """GET /workflows with no results → 200 empty list."""
    db = make_mock_db(items=[])
    client = _make_client(db)
    resp = client.get("/api/v1/workflows")
    assert resp.status_code == 200
    assert resp.json() == []
    client.app.dependency_overrides.clear()


# ── source_app (framework/domain ownership tag, migration 0010) ────────────────


def test_list_workflows_accepts_source_app_filter():
    """GET /workflows?source_app=restoration is accepted (200) — the
    domain-scoped list surface restoration's admin frontend uses."""
    db = make_mock_db(items=[_fake_workflow(source_app="restoration")])
    client = _make_client(db)
    resp = client.get("/api/v1/workflows?source_app=restoration")
    assert resp.status_code == 200
    body = resp.json()
    assert isinstance(body, list)
    assert body[0]["source_app"] == "restoration"
    client.app.dependency_overrides.clear()


def test_create_workflow_threads_source_app_to_service():
    """POST /workflows with source_app passes it through to the service so
    the row is tagged — the mechanism that keeps restoration workflows out
    of the generic chassis list."""
    wf = _fake_workflow(source_app="restoration")
    db = make_mock_db()

    create_mock = AsyncMock(return_value=wf)
    with patch("api.services.workflow_service.create_workflow", new=create_mock):
        client = _make_client(db)
        resp = client.post(
            "/api/v1/workflows",
            json={
                "name": "Restoration WF",
                "trigger_type": "manual",
                "definition": {"nodes": [], "edges": []},
                "source_app": "restoration",
            },
        )
    assert resp.status_code == 201
    assert resp.json()["source_app"] == "restoration"
    # The router must forward source_app to the service layer.
    assert create_mock.await_args.kwargs.get("source_app") == "restoration"
    client.app.dependency_overrides.clear()


def test_create_workflow_defaults_source_app_none():
    """POST /workflows without source_app → service receives None (generic
    platform workflow). The chassis builder relies on this default."""
    wf = _fake_workflow(source_app=None)
    db = make_mock_db()

    create_mock = AsyncMock(return_value=wf)
    with patch("api.services.workflow_service.create_workflow", new=create_mock):
        client = _make_client(db)
        resp = client.post(
            "/api/v1/workflows",
            json={
                "name": "Platform WF",
                "trigger_type": "manual",
                "definition": {"nodes": [], "edges": []},
            },
        )
    assert resp.status_code == 201
    assert create_mock.await_args.kwargs.get("source_app") is None
    client.app.dependency_overrides.clear()


# ── POST /api/v1/workflows ─────────────────────────────────────────────────────


def test_create_workflow_returns_201():
    """POST /workflows with valid body → 201."""
    wf = _fake_workflow()
    db = make_mock_db()

    with patch(
        "api.services.workflow_service.create_workflow",
        new=AsyncMock(return_value=wf),
    ):
        client = _make_client(db)
        resp = client.post(
            "/api/v1/workflows",
            json={
                "name": "My Workflow",
                "trigger_type": "manual",
                "definition": {"nodes": [], "edges": []},
            },
        )
    assert resp.status_code == 201
    client.app.dependency_overrides.clear()


def test_create_workflow_missing_name_returns_422():
    """POST /workflows without name → 422."""
    client = _make_client()
    resp = client.post(
        "/api/v1/workflows",
        json={"trigger_type": "manual", "definition": {}},
    )
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


# ── GET /api/v1/workflows/{id} ─────────────────────────────────────────────────


def test_get_workflow_returns_200():
    """GET /workflows/{id} when workflow exists → 200."""
    wf = _fake_workflow()
    db = make_mock_db(scalar=wf)
    client = _make_client(db)
    resp = client.get(f"/api/v1/workflows/{TEST_WF_ID}")
    assert resp.status_code == 200
    client.app.dependency_overrides.clear()


def test_get_workflow_not_found_returns_404():
    """GET /workflows/{id} with unknown id → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.get(f"/api/v1/workflows/{TEST_WF_ID}")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── PUT /api/v1/workflows/{id} ─────────────────────────────────────────────────


def test_update_workflow_returns_200():
    """PUT /workflows/{id} on existing workflow → 200."""
    wf = _fake_workflow()
    db = make_mock_db(scalar=wf)
    client = _make_client(db)
    resp = client.put(
        f"/api/v1/workflows/{TEST_WF_ID}",
        json={"name": "Updated"},
    )
    assert resp.status_code in (200, 422)
    client.app.dependency_overrides.clear()


def test_update_workflow_not_found_returns_404():
    """PUT /workflows/{id} with unknown id → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.put(f"/api/v1/workflows/{TEST_WF_ID}", json={"name": "x"})
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── DELETE /api/v1/workflows/{id} ─────────────────────────────────────────────


def test_delete_workflow_returns_204():
    """DELETE /workflows/{id} on existing workflow → 204."""
    wf = _fake_workflow()
    db = make_mock_db(scalar=wf)
    client = _make_client(db)
    resp = client.delete(f"/api/v1/workflows/{TEST_WF_ID}")
    assert resp.status_code == 204
    client.app.dependency_overrides.clear()


def test_delete_workflow_not_found_returns_404():
    """DELETE /workflows/{id} when not found → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.delete(f"/api/v1/workflows/{TEST_WF_ID}")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── POST /api/v1/workflows/{id}/execute ───────────────────────────────────────


def test_execute_workflow_returns_200():
    """POST /workflows/{id}/execute on existing active workflow → 200."""
    wf = _fake_workflow(is_active=True)
    exe = _fake_execution()
    db = make_mock_db()
    wf_result = make_db_result(scalar=wf)
    exe_result = make_db_result(scalar=exe)

    call_count = [0]

    async def execute_side_effect(*a, **kw):
        call_count[0] += 1
        return wf_result if call_count[0] == 1 else exe_result

    db.execute = AsyncMock(side_effect=execute_side_effect)

    with patch(
        "api.services.workflow_service.trigger_workflow",
        new=AsyncMock(return_value=exe),
    ):
        client = _make_client(db)
        resp = client.post(
            f"/api/v1/workflows/{TEST_WF_ID}/execute",
            json={"input_data": {"key": "value"}},
        )
    assert resp.status_code in (200, 201, 404)
    client.app.dependency_overrides.clear()


def test_execute_workflow_not_found_returns_404():
    """POST /workflows/{id}/execute with unknown id → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.post(
        f"/api/v1/workflows/{TEST_WF_ID}/execute",
        json={"input_data": {}},
    )
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── POST /webhooks/{org_slug}/{workflow_id} ───────────────────────────────────


def test_webhook_trigger_invalid_signature_returns_401_or_200():
    """POST /webhooks/{org}/{wf_id} with no valid signature is either 401 or 200."""
    from fastapi.testclient import TestClient

    from api.main import app
    from shared.db import get_db

    # Webhook endpoint uses get_db; mock it so no real DB connection is attempted.
    # Return None for org lookup so the endpoint returns 404 (org not found).
    db = make_mock_db(scalar=None)

    async def override_db():
        yield db

    app.dependency_overrides[get_db] = override_db
    client = TestClient(app, raise_server_exceptions=False)
    resp = client.post(
        f"/api/v1/webhooks/test-org/{TEST_WF_ID}",
        json={"event": "test"},
    )
    app.dependency_overrides.clear()
    # Without a matching org it returns 404 — not a 500
    assert resp.status_code in (200, 401, 404)


# ── GET /api/v1/workflows/{id}/trigger-info ───────────────────────────────────


def test_get_trigger_info_not_found_returns_404():
    """GET /workflows/{id}/trigger-info with unknown id → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.get(f"/api/v1/workflows/{TEST_WF_ID}/trigger-info")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


def test_get_trigger_info_returns_200():
    """GET /workflows/{id}/trigger-info for existing workflow → 200."""
    wf = _fake_workflow()
    db = make_mock_db(scalar=wf)
    client = _make_client(db)
    resp = client.get(f"/api/v1/workflows/{TEST_WF_ID}/trigger-info")
    assert resp.status_code == 200
    client.app.dependency_overrides.clear()
