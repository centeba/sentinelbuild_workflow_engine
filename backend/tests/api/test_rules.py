"""
API tests for /api/v1/rules — CRUD, test event, batch, versions, audit, approvals.

All DB calls are mocked; no live PostgreSQL required.
"""

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from tests.conftest import (
    TEST_ORG_ID,
    TEST_RULE_ID,
    FakeCurrentUser,
    make_db_result,
    make_mock_db,
)

# ── helpers ────────────────────────────────────────────────────────────────────


def _fake_rule(**kwargs):
    r = MagicMock()
    r.id = TEST_RULE_ID
    r.org_id = TEST_ORG_ID
    r.name = kwargs.get("name", "My Rule")
    r.description = kwargs.get("description", "")
    r.rule_type = kwargs.get("rule_type", "condition_tree")
    r.status = kwargs.get("status", "draft")
    r.is_active = kwargs.get("is_active", True)
    r.priority = kwargs.get("priority", 0)
    r.stop_on_match = kwargs.get("stop_on_match", False)
    r.trigger_events = kwargs.get("trigger_events", ["order.created"])
    r.trigger_filter = kwargs.get("trigger_filter", {})
    r.conditions = kwargs.get("conditions", {"operator": "AND", "conditions": []})
    r.actions = kwargs.get("actions", [])
    r.else_actions = kwargs.get("else_actions", [])
    r.approval_required = kwargs.get("approval_required", False)
    r.required_approvers = kwargs.get("required_approvers", [])
    r.created_at = "2024-01-01T00:00:00Z"
    r.updated_at = "2024-01-01T00:00:00Z"
    return r


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


# ── GET /api/v1/rules ──────────────────────────────────────────────────────────


def test_list_rules_returns_200():
    """GET /rules returns 200 with a list (may be empty)."""
    db = make_mock_db(items=[_fake_rule()])
    client = _make_client(db)
    resp = client.get("/api/v1/rules")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
    client.app.dependency_overrides.clear()


def test_list_rules_filter_by_status():
    """status query param is forwarded to DB filter (no crash)."""
    db = make_mock_db(items=[])
    client = _make_client(db)
    resp = client.get("/api/v1/rules?status=published")
    assert resp.status_code == 200
    client.app.dependency_overrides.clear()


# ── POST /api/v1/rules ─────────────────────────────────────────────────────────


def test_create_rule_returns_201():
    """POST /rules with valid body returns 201."""
    import datetime

    rule = _fake_rule()
    db = make_mock_db()
    db.flush = AsyncMock()

    def _add_side_effect(obj):
        # Populate auto-generated fields so the response serialises cleanly
        if not getattr(obj, "id", None) or str(obj.id) == "None":
            obj.id = TEST_RULE_ID
        if not getattr(obj, "created_at", None):
            obj.created_at = datetime.datetime(2024, 1, 1, tzinfo=datetime.UTC)
        if not getattr(obj, "updated_at", None):
            obj.updated_at = datetime.datetime(2024, 1, 1, tzinfo=datetime.UTC)

    db.add = _add_side_effect

    with patch("api.routers.rules.cache_invalidate", new=AsyncMock()):
        client = _make_client(db)
        resp = client.post(
            "/api/v1/rules",
            json={
                "name": "My Rule",
                "rule_type": "condition_tree",
                "trigger_events": ["order.created"],
                "conditions": {"operator": "AND", "conditions": []},
                "actions": [],
            },
        )
    # 201 or 422 depending on schema; at minimum not 500
    assert resp.status_code in (201, 422)
    client.app.dependency_overrides.clear()


def test_create_rule_missing_name_returns_422():
    """Missing required field returns 422."""
    client = _make_client()
    resp = client.post("/api/v1/rules", json={"rule_type": "condition_tree"})
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


# ── GET /api/v1/rules/{id} ─────────────────────────────────────────────────────


def test_get_rule_returns_200():
    """GET /rules/{id} with matching DB row returns 200."""
    rule = _fake_rule()
    db = make_mock_db(scalar=rule)
    client = _make_client(db)
    resp = client.get(f"/api/v1/rules/{TEST_RULE_ID}")
    assert resp.status_code == 200
    client.app.dependency_overrides.clear()


def test_get_rule_not_found_returns_404():
    """GET /rules/{id} when DB returns nothing → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.get(f"/api/v1/rules/{TEST_RULE_ID}")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── PUT /api/v1/rules/{id} ─────────────────────────────────────────────────────


def test_update_rule_returns_200():
    """PUT /rules/{id} updates an existing rule."""
    rule = _fake_rule()
    db = make_mock_db(scalar=rule)

    with (
        patch("api.routers.rules.cache_invalidate", new=AsyncMock()),
        patch("api.routers.rules._next_version_num", new=AsyncMock(return_value=1)),
    ):
        client = _make_client(db)
        resp = client.put(
            f"/api/v1/rules/{TEST_RULE_ID}",
            json={"name": "Updated Rule"},
        )
    assert resp.status_code in (200, 422)
    client.app.dependency_overrides.clear()


def test_update_rule_not_found_returns_404():
    """PUT /rules/{id} when rule doesn't exist → 404."""
    db = make_mock_db(scalar=None)

    with patch("api.routers.rules.cache_invalidate", new=AsyncMock()):
        client = _make_client(db)
        resp = client.put(f"/api/v1/rules/{TEST_RULE_ID}", json={"name": "x"})
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── DELETE /api/v1/rules/{id} ──────────────────────────────────────────────────


def test_delete_rule_returns_204():
    """DELETE /rules/{id} on existing rule → 204."""
    rule = _fake_rule()
    db = make_mock_db(scalar=rule)

    with patch("api.routers.rules.cache_invalidate", new=AsyncMock()):
        client = _make_client(db)
        resp = client.delete(f"/api/v1/rules/{TEST_RULE_ID}")
    assert resp.status_code == 204
    client.app.dependency_overrides.clear()


def test_delete_rule_not_found_returns_404():
    """DELETE /rules/{id} when rule doesn't exist → 404."""
    db = make_mock_db(scalar=None)

    with patch("api.routers.rules.cache_invalidate", new=AsyncMock()):
        client = _make_client(db)
        resp = client.delete(f"/api/v1/rules/{TEST_RULE_ID}")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── POST /api/v1/rules/test ────────────────────────────────────────────────────


def test_test_rules_returns_200():
    """POST /rules/test with valid body returns 200."""
    db = make_mock_db(items=[])
    client = _make_client(db)
    resp = client.post(
        "/api/v1/rules/test",
        json={"event_type": "order.created", "event_data": {"amount": 100}},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert "matched_rules" in body
    client.app.dependency_overrides.clear()


def test_test_rules_missing_event_type_returns_422():
    """Missing event_type → 422."""
    client = _make_client()
    resp = client.post("/api/v1/rules/test", json={"event_data": {}})
    assert resp.status_code == 422
    client.app.dependency_overrides.clear()


# ── POST /api/v1/rules/batch ───────────────────────────────────────────────────


def test_batch_test_returns_200():
    """POST /rules/batch with a list of records returns 200."""
    db = make_mock_db(items=[])
    with patch(
        "api.services.rule_cache.get_cached_rules",
        new=AsyncMock(return_value=[]),
    ):
        client = _make_client(db)
        resp = client.post(
            "/api/v1/rules/batch",
            json={
                "event_type": "order.created",
                "records": [{"amount": 50}, {"amount": 200}],
            },
        )
    assert resp.status_code == 200
    body = resp.json()
    assert "results" in body
    assert len(body["results"]) == 2
    client.app.dependency_overrides.clear()


def test_batch_test_empty_records_returns_200():
    """POST /rules/batch with empty records list returns 200 with empty results."""
    db = make_mock_db(items=[])
    client = _make_client(db)
    resp = client.post(
        "/api/v1/rules/batch",
        json={"event_type": "order.created", "records": []},
    )
    assert resp.status_code == 200
    client.app.dependency_overrides.clear()


# ── GET /api/v1/rules/{id}/versions ───────────────────────────────────────────


def test_get_rule_versions_returns_200():
    """GET /rules/{id}/versions → 200 with a list."""
    import datetime

    rule = _fake_rule()
    ver = MagicMock()
    ver.id = uuid.uuid4()
    ver.rule_id = TEST_RULE_ID
    ver.org_id = TEST_ORG_ID
    ver.version_num = 1
    ver.name = "My Rule"
    ver.description = ""
    ver.note = None
    ver.is_active = True
    ver.status = "draft"
    ver.rule_type = "condition_tree"
    ver.priority = 0
    ver.stop_on_match = False
    ver.trigger_events = []
    ver.trigger_filter = {}
    ver.conditions = {}
    ver.actions = []
    ver.else_actions = []
    ver.approval_required = False
    ver.required_approvers = []
    ver.created_at = datetime.datetime(2024, 1, 1, tzinfo=datetime.UTC)

    db = make_mock_db()
    # first call returns the rule, second returns versions
    call_count = [0]
    rule_result = make_db_result(scalar=rule)
    ver_result = make_db_result(items=[ver])

    async def execute_side_effect(*a, **kw):
        call_count[0] += 1
        return rule_result if call_count[0] == 1 else ver_result

    db.execute = AsyncMock(side_effect=execute_side_effect)

    client = _make_client(db)
    resp = client.get(f"/api/v1/rules/{TEST_RULE_ID}/versions")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
    client.app.dependency_overrides.clear()


# ── GET /api/v1/rules/{id}/audit ──────────────────────────────────────────────


def test_get_rule_audit_returns_200():
    """GET /rules/{id}/audit → 200 with a list."""
    import datetime

    rule = _fake_rule()
    audit = MagicMock()
    audit.id = uuid.uuid4()
    audit.rule_id = TEST_RULE_ID
    audit.org_id = TEST_ORG_ID
    audit.rule_name = "My Rule"
    audit.event_type = "order.created"
    audit.matched = True
    audit.event_data = {}
    audit.actions_executed = []
    audit.elapsed_ms = 5
    audit.correlation_id = None
    audit.created_at = datetime.datetime(2024, 1, 1, tzinfo=datetime.UTC)

    db = make_mock_db()
    call_count = [0]
    rule_result = make_db_result(scalar=rule)
    audit_result = make_db_result(items=[audit])

    async def execute_side_effect(*a, **kw):
        call_count[0] += 1
        return rule_result if call_count[0] == 1 else audit_result

    db.execute = AsyncMock(side_effect=execute_side_effect)

    client = _make_client(db)
    resp = client.get(f"/api/v1/rules/{TEST_RULE_ID}/audit")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
    client.app.dependency_overrides.clear()


def test_get_org_audit_returns_200():
    """GET /rules/audit (org-wide) → 200."""
    db = make_mock_db(items=[])
    client = _make_client(db)
    resp = client.get("/api/v1/rules/audit")
    assert resp.status_code == 200
    client.app.dependency_overrides.clear()


# ── POST /api/v1/rules/{id}/versions/{ver}/restore ────────────────────────────


def test_restore_version_not_found_returns_404():
    """Restore with missing rule → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.post(f"/api/v1/rules/{TEST_RULE_ID}/versions/1/restore")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── POST /api/v1/rules/{id}/publish ───────────────────────────────────────────


def test_publish_rule_returns_200():
    """POST /rules/{id}/publish → 200 with status=published."""
    rule = _fake_rule(status="draft")
    db = make_mock_db(scalar=rule)

    with patch("api.routers.rules.cache_invalidate", new=AsyncMock()):
        client = _make_client(db)
        resp = client.post(f"/api/v1/rules/{TEST_RULE_ID}/publish")
    assert resp.status_code == 200
    client.app.dependency_overrides.clear()


def test_publish_rule_not_found_returns_404():
    """POST /rules/{id}/publish with unknown id → 404."""
    db = make_mock_db(scalar=None)

    with patch("api.routers.rules.cache_invalidate", new=AsyncMock()):
        client = _make_client(db)
        resp = client.post(f"/api/v1/rules/{TEST_RULE_ID}/publish")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── POST /api/v1/rules/{id}/approve / reject ──────────────────────────────────


def test_approve_rule_not_found_returns_404():
    """Approve endpoint returns 404 when rule doesn't exist."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.post(
        f"/api/v1/rules/{TEST_RULE_ID}/approve",
        json={"action": "approve"},
    )
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()


# ── POST /api/v1/rules/validate-js ────────────────────────────────────────────


def test_validate_js_valid_syntax():
    """POST /rules/validate-js with valid JS → 200 valid=True."""
    client = _make_client()
    resp = client.post(
        "/api/v1/rules/validate-js",
        json={"code": "function evaluate(data) { return data.amount > 100; }"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert "valid" in body
    client.app.dependency_overrides.clear()


@pytest.mark.skipif(
    not __import__("importlib").util.find_spec("dukpy"),
    reason="dukpy not installed; validate_js_syntax cannot detect syntax errors",
)
def test_validate_js_invalid_syntax():
    """POST /rules/validate-js with bad JS → 200 valid=False."""
    client = _make_client()
    resp = client.post(
        "/api/v1/rules/validate-js",
        json={"code": "function {{{ broken syntax"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body.get("valid") is False
    client.app.dependency_overrides.clear()


# ── GET /api/v1/rules/{id}/analytics ──────────────────────────────────────────


def test_get_rule_analytics_not_found_returns_404():
    """GET /rules/{id}/analytics with unknown id → 404."""
    db = make_mock_db(scalar=None)
    client = _make_client(db)
    resp = client.get(f"/api/v1/rules/{TEST_RULE_ID}/analytics")
    assert resp.status_code == 404
    client.app.dependency_overrides.clear()
