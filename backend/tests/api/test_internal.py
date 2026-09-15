"""
Tests for POST /api/v1/internal/events/{event_type}.

All DB calls are mocked — no live PostgreSQL or Temporal required.
Authentication is via X-API-Key; we override the dependency in most tests
to focus on dispatch logic, and use a real key-check test for auth coverage.
"""

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

from fastapi.testclient import TestClient

from tests.conftest import (
    TEST_EXEC_ID,
    TEST_ORG_ID,
    TEST_WF_ID,
    make_mock_db,
)

# ── Helpers ───────────────────────────────────────────────────────────────────


def _fake_workflow(**kwargs):
    wf = MagicMock()
    wf.id = TEST_WF_ID
    wf.org_id = TEST_ORG_ID
    wf.trigger_type = kwargs.get("trigger_type", "email_extracted")
    wf.is_active = True
    wf.scope = kwargs.get("scope", "personal")
    wf.is_mandated = kwargs.get("is_mandated", False)
    wf.active_version_id = None
    return wf


def _fake_execution():
    e = MagicMock()
    e.id = TEST_EXEC_ID
    return e


def _make_client(db=None, bypass_auth: bool = True):
    """
    Build a TestClient with the DB mocked.

    When bypass_auth=True (default) the _verify_internal_key dependency is
    overridden with a no-op so tests focus on dispatch logic.
    """
    from fastapi.testclient import TestClient

    from api.main import app
    from api.routers.internal import _verify_internal_key
    from shared.db import get_db

    _db = db or make_mock_db()

    async def override_db():
        yield _db

    app.dependency_overrides[get_db] = override_db

    if bypass_auth:
        # Replace the key check with a no-op so we don't need a real API key
        def noop_verify():
            return None

        app.dependency_overrides[_verify_internal_key] = noop_verify

    client = TestClient(app, raise_server_exceptions=False)
    return client


def _cleanup(client: TestClient) -> None:
    client.app.dependency_overrides.clear()


# ── No matching workflows ──────────────────────────────────────────────────────


def test_dispatch_no_matching_workflows():
    """Returns 200 with triggered=0 when no workflows match the event type."""
    db = make_mock_db(items=[])
    client = _make_client(db)

    resp = client.post(
        "/api/v1/internal/events/email_extracted",
        json={"org_id": str(TEST_ORG_ID), "event_data": {"foo": "bar"}},
    )

    assert resp.status_code == 200
    data = resp.json()
    assert data["triggered"] == 0
    assert data["execution_ids"] == []
    assert data["event_type"] == "email_extracted"
    _cleanup(client)


# ── Workflow triggered ─────────────────────────────────────────────────────────


def test_dispatch_triggers_matching_workflow():
    """Returns 200 with triggered=1 and the execution ID when a workflow matches."""
    wf = _fake_workflow()
    execution = _fake_execution()
    db = make_mock_db(items=[wf])
    client = _make_client(db)

    with patch(
        "api.routers.internal.trigger_workflow",
        new=AsyncMock(return_value=execution),
    ):
        resp = client.post(
            "/api/v1/internal/events/email_extracted",
            json={
                "org_id": str(TEST_ORG_ID),
                "event_data": {"extraction_id": "abc", "subject": "Invoice"},
            },
        )

    assert resp.status_code == 200
    data = resp.json()
    assert data["triggered"] == 1
    assert str(TEST_EXEC_ID) in data["execution_ids"]
    _cleanup(client)


# ── System-mandated workflow ───────────────────────────────────────────────────


def test_dispatch_includes_system_mandated_workflows():
    """System-scoped mandated workflows fire for any org."""
    system_wf = _fake_workflow(scope="system", is_mandated=True)
    execution = _fake_execution()
    db = make_mock_db(items=[system_wf])
    client = _make_client(db)

    with patch(
        "api.routers.internal.trigger_workflow",
        new=AsyncMock(return_value=execution),
    ):
        resp = client.post(
            "/api/v1/internal/events/email_extracted",
            json={"org_id": str(uuid.uuid4()), "event_data": {}},
        )

    assert resp.status_code == 200
    assert resp.json()["triggered"] == 1
    _cleanup(client)


# ── Multiple workflows ────────────────────────────────────────────────────────


def test_dispatch_triggers_multiple_workflows():
    """All matching workflows are triggered; triggered count equals number of successes."""
    wf1 = _fake_workflow()
    wf2 = _fake_workflow()
    exec1, exec2 = _fake_execution(), _fake_execution()
    exec2.id = uuid.UUID("33333333-3333-3333-3333-333333333333")

    db = make_mock_db(items=[wf1, wf2])
    client = _make_client(db)

    with patch(
        "api.routers.internal.trigger_workflow",
        new=AsyncMock(side_effect=[exec1, exec2]),
    ):
        resp = client.post(
            "/api/v1/internal/events/email_extracted",
            json={"org_id": str(TEST_ORG_ID), "event_data": {}},
        )

    assert resp.status_code == 200
    data = resp.json()
    assert data["triggered"] == 2
    assert len(data["execution_ids"]) == 2
    _cleanup(client)


# ── Validation ────────────────────────────────────────────────────────────────


def test_dispatch_invalid_org_id_returns_400():
    """Returns 400 when org_id is not a valid UUID."""
    client = _make_client()

    resp = client.post(
        "/api/v1/internal/events/email_extracted",
        json={"org_id": "not-a-uuid", "event_data": {}},
    )

    assert resp.status_code == 400
    assert "Invalid org_id" in resp.json()["detail"]
    _cleanup(client)


def test_dispatch_missing_body_returns_422():
    """Returns 422 when the request body is missing required fields."""
    client = _make_client()

    resp = client.post("/api/v1/internal/events/email_extracted", json={})

    assert resp.status_code == 422
    _cleanup(client)


# ── Resilience: trigger failure doesn't abort ─────────────────────────────────


def test_dispatch_continues_if_trigger_raises():
    """If trigger_workflow raises, the endpoint still returns 200 with triggered=0."""
    wf = _fake_workflow()
    db = make_mock_db(items=[wf])
    client = _make_client(db)

    with patch(
        "api.routers.internal.trigger_workflow",
        new=AsyncMock(side_effect=RuntimeError("Temporal unavailable")),
    ):
        resp = client.post(
            "/api/v1/internal/events/email_extracted",
            json={"org_id": str(TEST_ORG_ID), "event_data": {}},
        )

    # triggered=0 because the execution failed, but HTTP response is still 200
    assert resp.status_code == 200
    assert resp.json()["triggered"] == 0
    _cleanup(client)


def test_dispatch_partial_failure():
    """If second trigger raises, triggered=1 (first succeeded) is returned."""
    wf1, wf2 = _fake_workflow(), _fake_workflow()
    execution = _fake_execution()
    db = make_mock_db(items=[wf1, wf2])
    client = _make_client(db)

    with patch(
        "api.routers.internal.trigger_workflow",
        new=AsyncMock(side_effect=[execution, RuntimeError("boom")]),
    ):
        resp = client.post(
            "/api/v1/internal/events/email_extracted",
            json={"org_id": str(TEST_ORG_ID), "event_data": {}},
        )

    assert resp.status_code == 200
    assert resp.json()["triggered"] == 1
    _cleanup(client)


# ── Auth: real key verification ───────────────────────────────────────────────


def test_dispatch_rejects_wrong_api_key():
    """Returns 401 when the X-API-Key doesn't match the configured secret."""
    from api.main import app
    from shared.config import get_settings
    from shared.db import get_db

    db = make_mock_db(items=[])

    async def override_db():
        yield db

    # Do NOT bypass auth for this test — we want to exercise the real key check
    app.dependency_overrides[get_db] = override_db

    # Clear the lru_cache so our env-patched settings take effect
    get_settings.cache_clear()

    with patch.object(get_settings(), "internal_api_key", "correct-key"):
        # Patching the cached instance's attribute directly
        with TestClient(app, raise_server_exceptions=False) as c:
            resp = c.post(
                "/api/v1/internal/events/email_extracted",
                json={"org_id": str(TEST_ORG_ID), "event_data": {}},
                headers={"X-API-Key": "wrong-key"},
            )

    assert resp.status_code == 401
    app.dependency_overrides.clear()
