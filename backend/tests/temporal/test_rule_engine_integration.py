"""
Integration-style tests for api.services.rule_engine.process_event.

All database and Redis I/O is mocked — no live infrastructure required.
The rule cache (get_cached_rules) is patched to return in-memory rule dicts.
"""

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from api.constants import (
    ACTION_SET_FIELD,
    RULE_STATUS_PUBLISHED,
    RULE_TYPE_CONDITION_TREE,
)
from api.services.rule_engine import process_event

# ─── Helper ───────────────────────────────────────────────────────────────────


def make_rule_dict(
    *,
    name: str = "Test Rule",
    status: str = RULE_STATUS_PUBLISHED,
    rule_type: str = RULE_TYPE_CONDITION_TREE,
    priority: int = 100,
    stop_on_match: bool = False,
    trigger_events: list | None = None,
    trigger_filter: dict | None = None,
    conditions: dict | None = None,
    actions: list | None = None,
    else_actions: list | None = None,
    approval_required: bool = False,
    required_approvers: list | None = None,
) -> dict:
    """Return a rule dict in the format returned by rule_cache.get_cached_rules."""
    return {
        "id": str(uuid.uuid4()),
        "name": name,
        "status": status,
        "rule_type": rule_type,
        "priority": priority,
        "stop_on_match": stop_on_match,
        "trigger_events": trigger_events
        if trigger_events is not None
        else ["form_submit"],
        "trigger_filter": trigger_filter or {},
        "conditions": conditions
        if conditions is not None
        else {
            "combinator": "and",
            "rules": [],
        },
        "actions": actions if actions is not None else [],
        "else_actions": else_actions if else_actions is not None else [],
        "approval_required": approval_required,
        "required_approvers": required_approvers
        if required_approvers is not None
        else [],
    }


def _make_db_mock() -> AsyncMock:
    """Return a minimal async DB session mock."""
    db = AsyncMock()
    db.add = MagicMock()
    return db


# ─── Tests ────────────────────────────────────────────────────────────────────

ORG_ID = str(uuid.uuid4())
EVENT_TYPE = "form_submit"


@pytest.mark.asyncio
async def test_process_event_no_rules():
    """With no rules in the cache, process_event returns an empty list."""
    db = _make_db_mock()
    with patch(
        "api.services.rule_cache.get_cached_rules", new=AsyncMock(return_value=[])
    ):
        results = await process_event(EVENT_TYPE, {"email": "a@b.com"}, ORG_ID, db)
    assert results == []


@pytest.mark.asyncio
async def test_process_event_simple_match():
    """A rule whose condition always passes returns a result with matched=True."""
    rule = make_rule_dict(
        name="Always Match",
        conditions={
            "combinator": "and",
            "rules": [
                {"field": "data.email", "operator": "is_not_empty", "value": ""},
            ],
        },
        actions=[
            {ACTION_SET_FIELD: "dummy"}
        ],  # at least one action so the rule appears in results
    )
    # Use a flat event_data dict so data.email resolves correctly
    event_data = {"data": {"email": "user@example.com"}}
    db = _make_db_mock()
    with patch(
        "api.services.rule_cache.get_cached_rules", new=AsyncMock(return_value=[rule])
    ):
        results = await process_event(EVENT_TYPE, event_data, ORG_ID, db)

    assert len(results) == 1
    assert results[0]["matched"] is True
    assert results[0]["rule_name"] == "Always Match"


@pytest.mark.asyncio
async def test_process_event_no_match():
    """A rule whose condition fails takes the else_actions path."""
    else_action = {"type": ACTION_SET_FIELD, "field": "status", "value": "rejected"}
    rule = make_rule_dict(
        name="Never Match",
        conditions={
            "combinator": "and",
            "rules": [
                # Condition that will never be satisfied by our event_data
                {
                    "field": "data.email",
                    "operator": "eq",
                    "value": "no-match@example.com",
                },
            ],
        },
        else_actions=[else_action],
    )
    event_data = {"data": {"email": "user@example.com"}}
    db = _make_db_mock()
    with patch(
        "api.services.rule_cache.get_cached_rules", new=AsyncMock(return_value=[rule])
    ):
        results = await process_event(EVENT_TYPE, event_data, ORG_ID, db)

    # The rule has else_actions so it should appear in results
    assert len(results) == 1
    assert results[0]["matched"] is False
    assert results[0]["path"] == "else"


@pytest.mark.asyncio
async def test_process_event_stop_on_match():
    """When the first rule has stop_on_match=True, the second rule is not evaluated."""
    rule1 = make_rule_dict(
        name="First Rule",
        priority=10,
        stop_on_match=True,
        # Empty conditions group → always True
        conditions={"combinator": "and", "rules": []},
        actions=[{"type": ACTION_SET_FIELD, "field": "processed", "value": "true"}],
    )
    rule2 = make_rule_dict(
        name="Second Rule",
        priority=20,
        conditions={"combinator": "and", "rules": []},
        actions=[{"type": ACTION_SET_FIELD, "field": "second", "value": "true"}],
    )
    event_data = {"data": {"email": "user@example.com"}}
    db = _make_db_mock()
    with patch(
        "api.services.rule_cache.get_cached_rules",
        new=AsyncMock(return_value=[rule1, rule2]),
    ):
        results = await process_event(EVENT_TYPE, event_data, ORG_ID, db)

    # Only the first rule should appear — processing halted after it
    rule_names = [r["rule_name"] for r in results]
    assert "First Rule" in rule_names
    assert "Second Rule" not in rule_names


@pytest.mark.asyncio
async def test_process_event_dry_run_no_audit():
    """In dry_run mode, db.add is never called (no audit rows written)."""
    rule = make_rule_dict(
        conditions={"combinator": "and", "rules": []},
        actions=[{"type": ACTION_SET_FIELD, "field": "x", "value": "1"}],
    )
    event_data = {"data": {}}
    db = _make_db_mock()
    with patch(
        "api.services.rule_cache.get_cached_rules", new=AsyncMock(return_value=[rule])
    ):
        await process_event(EVENT_TYPE, event_data, ORG_ID, db, dry_run=True)

    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_process_event_set_field_action():
    """The set_field action mutates event_data so the field is visible afterwards."""
    rule = make_rule_dict(
        conditions={"combinator": "and", "rules": []},
        actions=[{"type": ACTION_SET_FIELD, "field": "processed", "value": "yes"}],
    )
    event_data: dict = {}
    db = _make_db_mock()
    with patch(
        "api.services.rule_cache.get_cached_rules", new=AsyncMock(return_value=[rule])
    ):
        results = await process_event(EVENT_TYPE, event_data, ORG_ID, db)

    # set_field should have mutated event_data in-place
    assert event_data.get("processed") == "yes"
    # And the action result should be recorded
    assert len(results) == 1
    executed = results[0]["actions_executed"]
    assert any(a.get("type") == ACTION_SET_FIELD for a in executed)


@pytest.mark.asyncio
async def test_process_event_priority_order():
    """Rules are evaluated in ascending priority order (lower number = first)."""
    execution_order: list[str] = []

    rule_low_priority = make_rule_dict(
        name="Low Priority",
        priority=200,
        conditions={"combinator": "and", "rules": []},
        actions=[{"type": ACTION_SET_FIELD, "field": "order_low", "value": "1"}],
    )
    rule_high_priority = make_rule_dict(
        name="High Priority",
        priority=10,
        conditions={"combinator": "and", "rules": []},
        actions=[{"type": ACTION_SET_FIELD, "field": "order_high", "value": "1"}],
    )
    # Deliberately pass in reverse order so that the sort is what fixes it
    rules = [rule_low_priority, rule_high_priority]
    event_data: dict = {}
    db = _make_db_mock()
    with patch(
        "api.services.rule_cache.get_cached_rules", new=AsyncMock(return_value=rules)
    ):
        results = await process_event(EVENT_TYPE, event_data, ORG_ID, db)

    # The high-priority (priority=10) rule should appear first in results
    assert len(results) == 2
    assert results[0]["rule_name"] == "High Priority"
    assert results[1]["rule_name"] == "Low Priority"
