"""Tests for temporal.activities.transform_activity.transform_data."""

import pytest

temporalio = pytest.importorskip("temporalio", reason="temporalio not installed")

from temporal.activities.transform_activity import TransformParams, transform_data


@pytest.mark.asyncio
async def test_jmespath_simple_field():
    """JMESPath extracts a simple nested scalar and wraps it in a result dict."""
    params = TransformParams(
        input_data={"user": {"name": "Alice", "email": "alice@example.com"}},
        expression="user.name",
        engine="jmespath",
    )
    result = await transform_data(params)
    assert result == {"result": "Alice"}


@pytest.mark.asyncio
async def test_jmespath_nested_object():
    """JMESPath wildcard projection returns a list of values wrapped in result."""
    params = TransformParams(
        input_data={"orders": [{"id": 1, "amount": 100}, {"id": 2, "amount": 200}]},
        expression="orders[*].amount",
        engine="jmespath",
    )
    result = await transform_data(params)
    assert result == {"result": [100, 200]}


@pytest.mark.asyncio
async def test_jmespath_returns_dict_directly():
    """JMESPath result that is already a dict is returned without the result wrapper."""
    params = TransformParams(
        input_data={"user": {"id": 1, "name": "Bob"}},
        expression="user",
        engine="jmespath",
    )
    result = await transform_data(params)
    assert result == {"id": 1, "name": "Bob"}


@pytest.mark.asyncio
async def test_jsonpath_simple():
    """JSONPath expression extracts a scalar from a nested structure."""
    params = TransformParams(
        input_data={"store": {"book": [{"title": "Foo"}, {"title": "Bar"}]}},
        expression="$.store.book[0].title",
        engine="jsonpath",
    )
    result = await transform_data(params)
    assert result == {"result": "Foo"}


@pytest.mark.asyncio
async def test_python_expression():
    """Python engine evaluates an inline dict expression against the input data."""
    params = TransformParams(
        input_data={"price": 100, "quantity": 3},
        expression="{'total': data['price'] * data['quantity']}",
        engine="python",
    )
    result = await transform_data(params)
    assert result == {"total": 300}


@pytest.mark.asyncio
async def test_python_string_concat():
    """Python engine concatenates two string fields from the input data."""
    params = TransformParams(
        input_data={"first": "John", "last": "Doe"},
        expression="{'full_name': data['first'] + ' ' + data['last']}",
        engine="python",
    )
    result = await transform_data(params)
    assert result == {"full_name": "John Doe"}


@pytest.mark.asyncio
async def test_unknown_engine_raises():
    """An unrecognised engine name raises ValueError."""
    params = TransformParams(
        input_data={},
        expression="anything",
        engine="graphql",
    )
    with pytest.raises(ValueError):
        await transform_data(params)
