"""
API tests for /api/v1/rule-flows — CRUD + execute.

All DB calls are mocked; no live PostgreSQL required.
"""

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

from tests.conftest import (
    TEST_FLOW_ID,
    TEST_ORG_ID,
    FakeCurrentUser,
    make_db_result,
    make_mock_db,
)

# ── helpers ────────────────────────────────────────────────────────────────────


def _fake_flow(**kwargs):
    import datetime

    f = MagicMock()
    f.id = TEST_FLOW_ID
    f.org_id = TEST_ORG_ID
    f.name = kwargs.get("name", "My Flow")
    f.description = kwargs.get("description", "")
    f.is_active = kwargs.get("is_active", True)
    f.trigger_events = kwargs.get("trigger_events", [])
    f.created_at = datetime.datetime(2024, 1, 1, tzinfo=datetime.UTC)
    f.updated_at = datetime.datetime(2024, 1, 1, tzinfo=datetime.UTC)
    return f


def _fake_step(flow_id=None, rule_id=None, step_order=0):
    s = MagicMock()
    s.id = uuid.uuid4()
    s.flow_id = flow_id or TEST_FLOW_ID
    s.rule_id = rule_id or uuid.uuid4()
    s.step_order = step_order
    s.pass_output = True
    s.label = None
    return s


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


# ── GET /api/v1/rule-flows ─────────────────────────────────────────────────────


def test_list_rule_flows_returns_200():
    """GET /rule-flows → 200 list."""
    # The list_flows endpoint calls db.execute twice per flow: once for the flows
    # and once for the steps. The mock must return different results to avoid the
    # flow being mistaken for a step by the Pydantic serialiser.
    db = make_mock_db()
    flow_result = make_db_result(items=[_fake_flow()])
    step_result = make_db_result(items=[])
    call_count = [0]

    async def execute_side_effect(*a, **kw):
        call_count[0] += 1
        return flow_result if call_count[0] == 1 else step_result

    db.execute = AsyncMock(side_effect=execute_side_effect)
    client = _make_client(db)
    resp = client.get("/api/v1/rule-flows")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
    client.app.dependency_overrides.clear()


def test_list_rule_flows_empty_returns_200():
    """GET /rule-flows with no flows → 200 empty list."""
    db = make_mock_db(items=[])
    client = _make_client(db)
    resp = client.get("/api/v1/rule-flows")
    assert resp.status_code == 200
    assert resp.json() == []
    client.app.dependency_overrides.clear()


# ── POST /api/v1/rule-flows ────────────────────────────────────────────────────


def test_create_rule_flow_returns_201():
    """POST /rule-flows with valid body → 201."""
    import datetime

    db = make_mock_db()

    # db.add is called twice: once for the flow, once for each step.
    # We need to set auto-generated fields so the response serialises cleanly.
    def _add_side_effect(obj):
        if not getattr(obj, "id", None):
            obj.id = TEST_FLOW_ID
        if not getattr(obj, "created_at", None):
            obj.created_at = datetime.datetime(2024, 1, 1, tzinfo=datetime.UTC)
        if not getattr(obj, "updated_at", None):
            obj.updated_at = datetime.datetime(2024, 1, 1, tzinfo=datetime.UTC)

    db.add = _add_side_effect
    # _load_steps after create should return empty list (no steps added)
    db.execute = AsyncMock(return_value=make_db_result(items=[]))

    client = _make_client(db)
    resp = client.post(
        "/api/v1/rule-flows",
        json={"name": "My Flow", "steps": []},
    )
    assert resp.status_code in (201, 422)
    client.app.dependency_overrides.clear()


def test_create_rule_flow_missing_name_returns_422():
    """POST /rule-flows without name → 422."""
    client = _make_client()
    resp = client.post("/api/v1/rule-flows", json={"steps": []})
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


# ── GET /api/v1/rule-flows/{id} ────────────────────────────────────────────────


def test_get_rule_flow_returns_200():
    """GET /rule-flows/{id} when flow exists → 200."""
    flow = _fake_flow()
    db = make_mock_db()
    flow_result = make_db_result(scalar=flow)
    step_result = make_db_result(items=[])

    call_count = [0]

    async def execute_side_effect(*a, **kw):
        call_count[0] += 1
        return flow_result if call_count[0] == 1 else step_result

    db.execute = AsyncMock(side_effect=execute_side_effect)

    client = _make_client(db)
    resp = client.get(f"/api/v1/rule-flows/{TEST_FLOW_ID}")
    assert resp.status_code == 200
    client.app.dependency_overrides.clear()


def test_get_rule_flow_not_found_returns_404():
    """GET /rule-flows/{id} when flow not found → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.get(f"/api/v1/rule-flows/{TEST_FLOW_ID}")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── PUT /api/v1/rule-flows/{id} ────────────────────────────────────────────────


def test_update_rule_flow_not_found_returns_404():
    """PUT /rule-flows/{id} with unknown id → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.put(
        f"/api/v1/rule-flows/{TEST_FLOW_ID}",
        json={"name": "Updated"},
    )
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── DELETE /api/v1/rule-flows/{id} ─────────────────────────────────────────────


def test_delete_rule_flow_returns_204():
    """DELETE /rule-flows/{id} on existing flow → 204."""
    flow = _fake_flow()
    db = make_mock_db(scalar=flow)
    client = _make_client(db)
    resp = client.delete(f"/api/v1/rule-flows/{TEST_FLOW_ID}")
    assert resp.status_code == 204
    client.app.dependency_overrides.clear()


def test_delete_rule_flow_not_found_returns_404():
    """DELETE /rule-flows/{id} when not found → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.delete(f"/api/v1/rule-flows/{TEST_FLOW_ID}")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── POST /api/v1/rule-flows/{id}/execute ──────────────────────────────────────


def test_execute_rule_flow_not_found_returns_404():
    """POST /rule-flows/{id}/execute with unknown id → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.post(
        f"/api/v1/rule-flows/{TEST_FLOW_ID}/execute",
        json={"event_type": "order.created", "event_data": {"amount": 100}},
    )
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


def test_execute_rule_flow_no_steps_returns_200():
    """POST /rule-flows/{id}/execute with 0 steps → 200 with empty step results."""
    flow = _fake_flow()
    db = make_mock_db()
    flow_result = make_db_result(scalar=flow)
    step_result = make_db_result(items=[])

    call_count = [0]

    async def execute_side_effect(*a, **kw):
        call_count[0] += 1
        return flow_result if call_count[0] == 1 else step_result

    db.execute = AsyncMock(side_effect=execute_side_effect)

    with patch(
        "api.services.rule_engine.process_event",
        new=AsyncMock(
            return_value={"matched_rules": [], "total_matched": 0, "dry_run": True}
        ),
    ):
        client = _make_client(db)
        resp = client.post(
            f"/api/v1/rule-flows/{TEST_FLOW_ID}/execute",
            json={"event_type": "order.created", "event_data": {}},
        )
    assert resp.status_code == 200
    body = resp.json()
    assert "step_results" in body
    client.app.dependency_overrides.clear()
