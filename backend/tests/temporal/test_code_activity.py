"""Tests for temporal.activities.code_activity.run_code."""

import pytest

temporalio = pytest.importorskip("temporalio", reason="temporalio not installed")

from temporal.activities.code_activity import CodeParams, run_code


@pytest.mark.asyncio
async def test_basic_code_sets_result():
    """Simple assignment to result variable is returned as a dict."""
    params = CodeParams(
        code="result = {'message': 'hello world'}",
        input_data={},
    )
    result = await run_code(params)
    assert result == {"message": "hello world"}


@pytest.mark.asyncio
async def test_code_uses_input_data():
    """Code can read from the pre-loaded 'data' variable."""
    params = CodeParams(
        code="result = {'doubled': data['value'] * 2}",
        input_data={"value": 21},
    )
    result = await run_code(params)
    assert result == {"doubled": 42}


@pytest.mark.asyncio
async def test_code_uses_json_module():
    """The json module is pre-loaded and available in the sandbox without import."""
    params = CodeParams(
        code="result = {'data': json.dumps({'key': 'value'})}",
        input_data={},
    )
    result = await run_code(params)
    assert "data" in result


@pytest.mark.asyncio
async def test_code_uses_math_module():
    """The math module is pre-loaded and available in the sandbox without import."""
    params = CodeParams(
        code="result = {'pi': round(math.pi, 4)}",
        input_data={},
    )
    result = await run_code(params)
    assert result == {"pi": 3.1416}


@pytest.mark.asyncio
async def test_code_result_not_dict_is_wrapped():
    """A non-dict result value is wrapped in {'result': value}."""
    params = CodeParams(
        code="result = 42",
        input_data={},
    )
    result = await run_code(params)
    assert result == {"result": 42}


@pytest.mark.asyncio
async def test_code_exception_raises_runtime_error():
    """An exception inside the sandboxed code is re-raised as RuntimeError."""
    params = CodeParams(
        code="result = 1 / 0",
        input_data={},
    )
    with pytest.raises(RuntimeError):
        await run_code(params)


@pytest.mark.asyncio
async def test_unsupported_language_raises():
    """A non-Python language raises ValueError before any code is executed."""
    params = CodeParams(
        code="console.log('hi')",
        input_data={},
        language="javascript",
    )
    with pytest.raises(ValueError):
        await run_code(params)
