"""
API tests for /api/v1/executions — list, get, nodes, approve/reject, approval link.

All DB calls are mocked; no live PostgreSQL required.
"""

import uuid
from datetime import UTC
from unittest.mock import AsyncMock, MagicMock

from tests.conftest import (
    TEST_EXEC_ID,
    TEST_ORG_ID,
    TEST_WF_ID,
    FakeCurrentUser,
    make_db_result,
    make_mock_db,
)

# ── helpers ────────────────────────────────────────────────────────────────────


def _fake_execution(**kwargs):
    from datetime import datetime

    e = MagicMock()
    e.id = TEST_EXEC_ID
    e.workflow_id = TEST_WF_ID
    e.org_id = TEST_ORG_ID
    e.status = kwargs.get("status", "completed")
    e.trigger_type = kwargs.get("trigger_type", "manual")
    e.input_data = kwargs.get("input_data", {})
    e.output_data = kwargs.get("output_data", {})
    e.error_message = None
    e.temporal_workflow_id = None
    e.started_at = None
    e.completed_at = None
    e.approval_status = kwargs.get("approval_status", None)
    e.approval_node_id = None
    e.approved_by = None
    e.approval_note = None
    e.approval_token = kwargs.get("approval_token", None)
    e.approval_expires_at = None
    e.version_id = kwargs.get("version_id", None)  # added by versioning migration
    e.workflow_name = None
    e.workflow = MagicMock()
    e.workflow.name = "My Workflow"
    _ts = datetime(2024, 1, 1, tzinfo=UTC)
    e.created_at = _ts
    e.updated_at = _ts
    return e


def _fake_node_execution():
    n = MagicMock()
    n.id = uuid.uuid4()
    n.execution_id = TEST_EXEC_ID
    n.node_id = "node_1"
    n.node_type = "http_request"
    n.status = "completed"
    n.input_data = {}
    n.output_data = {"response": "ok"}
    n.error_message = None
    n.started_at = "2024-01-01T00:00:00Z"
    n.finished_at = "2024-01-01T00:00:01Z"
    n.duration_ms = 1000
    n.created_at = "2024-01-01T00:00:00Z"
    return n


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


# ── GET /api/v1/executions ────────────────────────────────────────────────────


def test_list_executions_returns_200():
    """GET /executions → 200 list."""
    exe = _fake_execution()
    db = make_mock_db()
    result = make_db_result(items=[exe])
    # list endpoint uses .unique().scalars().all()
    result.unique.return_value.scalars.return_value.all.return_value = [exe]
    db.execute = AsyncMock(return_value=result)

    client = _make_client(db)
    resp = client.get("/api/v1/executions")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
    client.app.dependency_overrides.clear()


def test_list_executions_empty_returns_200():
    """GET /executions with no results → 200 empty list."""
    db = make_mock_db()
    result = make_db_result(items=[])
    result.unique.return_value.scalars.return_value.all.return_value = []
    db.execute = AsyncMock(return_value=result)

    client = _make_client(db)
    resp = client.get("/api/v1/executions")
    assert resp.status_code == 200
    assert resp.json() == []
    client.app.dependency_overrides.clear()


def test_list_executions_filter_by_workflow_id():
    """GET /executions?workflow_id=... uses the filter (no crash)."""
    db = make_mock_db()
    result = make_db_result(items=[])
    result.unique.return_value.scalars.return_value.all.return_value = []
    db.execute = AsyncMock(return_value=result)

    client = _make_client(db)
    resp = client.get(f"/api/v1/executions?workflow_id={TEST_WF_ID}")
    assert resp.status_code == 200
    client.app.dependency_overrides.clear()


def test_list_executions_filter_approval_pending():
    """GET /executions?approval_pending=true uses the filter (no crash)."""
    db = make_mock_db()
    result = make_db_result(items=[])
    result.unique.return_value.scalars.return_value.all.return_value = []
    db.execute = AsyncMock(return_value=result)

    client = _make_client(db)
    resp = client.get("/api/v1/executions?approval_pending=true")
    assert resp.status_code == 200
    client.app.dependency_overrides.clear()


def test_list_executions_respects_limit_param():
    """GET /executions?limit=5 is accepted (no crash)."""
    db = make_mock_db()
    result = make_db_result(items=[])
    result.unique.return_value.scalars.return_value.all.return_value = []
    db.execute = AsyncMock(return_value=result)

    client = _make_client(db)
    resp = client.get("/api/v1/executions?limit=5")
    assert resp.status_code == 200
    client.app.dependency_overrides.clear()


# ── GET /api/v1/executions/{id} ───────────────────────────────────────────────


def test_get_execution_returns_200():
    """GET /executions/{id} when execution exists → 200."""
    exe = _fake_execution()
    db = make_mock_db(scalar=exe)
    client = _make_client(db)
    resp = client.get(f"/api/v1/executions/{TEST_EXEC_ID}")
    assert resp.status_code == 200
    client.app.dependency_overrides.clear()


def test_get_execution_not_found_returns_404():
    """GET /executions/{id} with unknown id → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.get(f"/api/v1/executions/{TEST_EXEC_ID}")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── GET /api/v1/executions/{id}/nodes ─────────────────────────────────────────


def test_get_node_executions_returns_200():
    """GET /executions/{id}/nodes → 200 list of node runs."""
    exe = _fake_execution()
    node = _fake_node_execution()
    db = make_mock_db()

    call_count = [0]
    exe_result = make_db_result(scalar=exe)
    node_result = make_db_result(items=[node])

    async def execute_side_effect(*a, **kw):
        call_count[0] += 1
        return exe_result if call_count[0] == 1 else node_result

    db.execute = AsyncMock(side_effect=execute_side_effect)

    client = _make_client(db)
    resp = client.get(f"/api/v1/executions/{TEST_EXEC_ID}/nodes")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
    client.app.dependency_overrides.clear()


def test_get_node_executions_not_found_returns_404():
    """GET /executions/{id}/nodes with unknown execution → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.get(f"/api/v1/executions/{TEST_EXEC_ID}/nodes")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── POST /api/v1/executions/{id}/approve ──────────────────────────────────────


def test_approve_execution_not_found_returns_404():
    """POST /executions/{id}/approve with unknown execution → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.post(
        f"/api/v1/executions/{TEST_EXEC_ID}/approve",
        json={"action": "approve"},
    )
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


def test_approve_execution_missing_action_returns_422():
    """POST /executions/{id}/approve without action → 422."""
    client = _make_client()
    resp = client.post(
        f"/api/v1/executions/{TEST_EXEC_ID}/approve",
        json={},
    )
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


def test_reject_execution_missing_action_returns_422():
    """POST /executions/{id}/approve with invalid action value → 422."""
    client = _make_client()
    resp = client.post(
        f"/api/v1/executions/{TEST_EXEC_ID}/approve",
        json={"action": "maybe"},
    )
    # Pydantic should reject unknown enum values
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


# ── GET /api/v1/executions/approval-action ────────────────────────────────────


def test_approval_action_link_invalid_token_returns_html():
    """GET /executions/approval-action?token=bad&action=approve → HTML (no 500)."""
    db = make_mock_db(scalar=None)

    from fastapi.testclient import TestClient

    from api.main import app
    from shared.db import get_db

    async def override_db():
        yield db

    app.dependency_overrides[get_db] = override_db
    client = TestClient(app, raise_server_exceptions=False)
    resp = client.get(
        "/api/v1/executions/approval-action?token=badtoken&action=approve"
    )
    # Returns HTML page for invalid tokens
    assert resp.status_code in (200, 400, 404)
    app.dependency_overrides.clear()


def test_approval_action_link_already_approved_returns_html():
    """GET /executions/approval-action for already-processed execution → HTML."""
    exe = _fake_execution(approval_status="approved", approval_token="validtoken")
    db = make_mock_db(scalar=exe)

    from fastapi.testclient import TestClient

    from api.main import app
    from shared.db import get_db

    async def override_db():
        yield db

    app.dependency_overrides[get_db] = override_db
    client = TestClient(app, raise_server_exceptions=False)
    resp = client.get(
        "/api/v1/executions/approval-action?token=validtoken&action=approve"
    )
    assert resp.status_code in (200, 400)
    app.dependency_overrides.clear()
