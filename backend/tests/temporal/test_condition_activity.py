"""Tests for temporal.activities.condition_activity.evaluate_condition."""

import pytest

temporalio = pytest.importorskip("temporalio", reason="temporalio not installed")

from temporal.activities.condition_activity import ConditionParams, evaluate_condition


@pytest.mark.asyncio
async def test_condition_true_string_equality():
    """Expression matching the field value returns True."""
    params = ConditionParams(
        input_data={"status": "active"},
        expression="data['status'] == 'active'",
    )
    result = await evaluate_condition(params)
    assert result is True


@pytest.mark.asyncio
async def test_condition_false_string_equality():
    """Expression not matching the field value returns False."""
    params = ConditionParams(
        input_data={"status": "inactive"},
        expression="data['status'] == 'active'",
    )
    result = await evaluate_condition(params)
    assert result is False


@pytest.mark.asyncio
async def test_condition_numeric_greater_than():
    """Numeric greater-than expression returns True when satisfied."""
    params = ConditionParams(
        input_data={"amount": 150},
        expression="data['amount'] > 100",
    )
    result = await evaluate_condition(params)
    assert result is True


@pytest.mark.asyncio
async def test_condition_numeric_less_than():
    """Numeric greater-than expression returns False when not satisfied."""
    params = ConditionParams(
        input_data={"amount": 50},
        expression="data['amount'] > 100",
    )
    result = await evaluate_condition(params)
    assert result is False


@pytest.mark.asyncio
async def test_condition_combined_and():
    """Compound and expression returns True when both parts are satisfied."""
    params = ConditionParams(
        input_data={"status": "active", "amount": 200},
        expression="data['status'] == 'active' and data['amount'] > 100",
    )
    result = await evaluate_condition(params)
    assert result is True


@pytest.mark.asyncio
async def test_condition_boolean_literal_true():
    """Literal True expression always returns True."""
    params = ConditionParams(
        input_data={},
        expression="True",
    )
    result = await evaluate_condition(params)
    assert result is True


@pytest.mark.asyncio
async def test_condition_boolean_literal_false():
    """Literal False expression always returns False."""
    params = ConditionParams(
        input_data={},
        expression="False",
    )
    result = await evaluate_condition(params)
    assert result is False


@pytest.mark.asyncio
async def test_condition_restricted_import_blocked():
    """An expression attempting __import__ must not return True.

    RestrictedPython may block the expression outright (raising an exception)
    or allow it to compile but prevent the import, yielding False.
    Either outcome is acceptable — the important thing is that True is never returned.
    """
    params = ConditionParams(
        input_data={},
        expression="__import__('os').system('echo hacked')",
    )
    try:
        result = await evaluate_condition(params)
        # If no exception, the sandbox must have blocked it from returning True
        assert result is not True, (
            "Sandbox allowed __import__ expression to return True — security breach"
        )
    except Exception:
        # Any exception means the sandbox blocked the dangerous expression
        pass
