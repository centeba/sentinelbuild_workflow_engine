"""Tests for temporal.activities.agent_activity.run_agent_node.

Covers:
  - Successful POST to integration-hub /ai-invoke/run with correct payload
  - Bearer auth uses INTERNAL_SERVICE_SECRET (not a forged JWT)
  - HTTP 4xx/5xx responses raise RuntimeError with response body
  - Missing INTEGRATION_HUB_URL or INTERNAL_SERVICE_SECRET raises RuntimeError
  - Optional context field is forwarded when provided
"""

from __future__ import annotations

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

temporalio = pytest.importorskip("temporalio", reason="temporalio not installed")
httpx = pytest.importorskip("httpx", reason="httpx not installed")

from temporal.activities.agent_activity import AgentParams, run_agent_node


def _fake_settings(
    integration_hub_url: str = "http://integration-hub:8005",
    internal_service_secret: str = "shared-secret",
):
    s = MagicMock()
    s.integration_hub_url = integration_hub_url
    s.internal_service_secret = internal_service_secret
    return s


def _mock_response(
    status_code: int = 200, json_body: dict | None = None, text: str = ""
):
    resp = MagicMock()
    resp.status_code = status_code
    resp.json = MagicMock(return_value=json_body or {})
    resp.text = text
    return resp


@pytest.mark.asyncio
async def test_run_agent_node_posts_to_correct_url():
    agent_id = str(uuid.uuid4())
    org_id = str(uuid.uuid4())

    captured: dict = {}

    async def _fake_post(url, **kwargs):
        captured["url"] = url
        captured["headers"] = kwargs.get("headers", {})
        captured["json"] = kwargs.get("json", {})
        return _mock_response(200, {"data": {"content": "hi"}, "provider": "anthropic"})

    mock_client = MagicMock()
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    mock_client.post = AsyncMock(side_effect=_fake_post)

    with (
        patch(
            "temporal.activities.agent_activity.get_settings",
            return_value=_fake_settings(),
        ),
        patch("httpx.AsyncClient", return_value=mock_client),
    ):
        result = await run_agent_node(
            AgentParams(agent_id=agent_id, prompt="hello", org_id=org_id)
        )

    assert captured["url"] == "http://integration-hub:8005/api/v1/ai-invoke/run"
    assert captured["json"]["agent_id"] == agent_id
    assert captured["json"]["prompt"] == "hello"
    assert captured["json"]["company_id"] == org_id
    assert captured["json"]["context"] is None
    assert result == {"data": {"content": "hi"}, "provider": "anthropic"}


@pytest.mark.asyncio
async def test_run_agent_node_uses_internal_service_secret_bearer():
    """Auth header must carry INTERNAL_SERVICE_SECRET — never a JWT."""
    captured: dict = {}

    async def _fake_post(url, **kwargs):
        captured["headers"] = kwargs.get("headers", {})
        return _mock_response(200, {"data": "ok"})

    mock_client = MagicMock()
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    mock_client.post = AsyncMock(side_effect=_fake_post)

    with (
        patch(
            "temporal.activities.agent_activity.get_settings",
            return_value=_fake_settings(internal_service_secret="my-shared-secret"),
        ),
        patch("httpx.AsyncClient", return_value=mock_client),
    ):
        await run_agent_node(
            AgentParams(
                agent_id=str(uuid.uuid4()), prompt="x", org_id=str(uuid.uuid4())
            )
        )

    assert captured["headers"]["Authorization"] == "Bearer my-shared-secret"
    assert captured["headers"]["Content-Type"] == "application/json"


@pytest.mark.asyncio
async def test_run_agent_node_forwards_context_when_provided():
    captured: dict = {}

    async def _fake_post(url, **kwargs):
        captured["json"] = kwargs.get("json", {})
        return _mock_response(200, {"data": "ok"})

    mock_client = MagicMock()
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    mock_client.post = AsyncMock(side_effect=_fake_post)

    with (
        patch(
            "temporal.activities.agent_activity.get_settings",
            return_value=_fake_settings(),
        ),
        patch("httpx.AsyncClient", return_value=mock_client),
    ):
        await run_agent_node(
            AgentParams(
                agent_id=str(uuid.uuid4()),
                prompt="summarize",
                org_id=str(uuid.uuid4()),
                context="prior step output",
            )
        )

    assert captured["json"]["context"] == "prior step output"


@pytest.mark.asyncio
async def test_run_agent_node_4xx_raises_runtime_error():
    async def _fake_post(url, **kwargs):
        return _mock_response(404, text="agent not found")

    mock_client = MagicMock()
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    mock_client.post = AsyncMock(side_effect=_fake_post)

    with (
        patch(
            "temporal.activities.agent_activity.get_settings",
            return_value=_fake_settings(),
        ),
        patch("httpx.AsyncClient", return_value=mock_client),
    ):
        with pytest.raises(RuntimeError, match="404"):
            await run_agent_node(
                AgentParams(
                    agent_id=str(uuid.uuid4()), prompt="x", org_id=str(uuid.uuid4())
                )
            )


@pytest.mark.asyncio
async def test_run_agent_node_5xx_raises_runtime_error_with_body():
    async def _fake_post(url, **kwargs):
        return _mock_response(500, text="LLM provider unreachable")

    mock_client = MagicMock()
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    mock_client.post = AsyncMock(side_effect=_fake_post)

    with (
        patch(
            "temporal.activities.agent_activity.get_settings",
            return_value=_fake_settings(),
        ),
        patch("httpx.AsyncClient", return_value=mock_client),
    ):
        with pytest.raises(RuntimeError) as exc_info:
            await run_agent_node(
                AgentParams(
                    agent_id=str(uuid.uuid4()), prompt="x", org_id=str(uuid.uuid4())
                )
            )
        # Response body should be echoed for debug visibility
        assert "LLM provider unreachable" in str(exc_info.value)


@pytest.mark.asyncio
async def test_run_agent_node_missing_url_raises():
    with patch(
        "temporal.activities.agent_activity.get_settings",
        return_value=_fake_settings(integration_hub_url=""),
    ):
        with pytest.raises(RuntimeError, match="INTEGRATION_HUB_URL"):
            await run_agent_node(
                AgentParams(agent_id=str(uuid.uuid4()), prompt="x", org_id="")
            )


@pytest.mark.asyncio
async def test_run_agent_node_missing_secret_raises():
    with patch(
        "temporal.activities.agent_activity.get_settings",
        return_value=_fake_settings(internal_service_secret=""),
    ):
        with pytest.raises(RuntimeError, match="INTERNAL_SERVICE_SECRET"):
            await run_agent_node(
                AgentParams(agent_id=str(uuid.uuid4()), prompt="x", org_id="")
            )


@pytest.mark.asyncio
async def test_run_agent_node_strips_trailing_slash_from_url():
    """integration_hub_url with trailing slash must not produce a double-slash URL."""
    captured: dict = {}

    async def _fake_post(url, **kwargs):
        captured["url"] = url
        return _mock_response(200, {"data": "ok"})

    mock_client = MagicMock()
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    mock_client.post = AsyncMock(side_effect=_fake_post)

    with (
        patch(
            "temporal.activities.agent_activity.get_settings",
            return_value=_fake_settings(
                integration_hub_url="http://integration-hub:8005/"
            ),
        ),
        patch("httpx.AsyncClient", return_value=mock_client),
    ):
        await run_agent_node(
            AgentParams(agent_id=str(uuid.uuid4()), prompt="x", org_id="")
        )

    # Single slash, not double
    assert captured["url"] == "http://integration-hub:8005/api/v1/ai-invoke/run"


@pytest.mark.asyncio
async def test_run_agent_node_empty_org_id_sends_null_company():
    """When the workflow run has no org_id, the request body sets company_id=None
    so integration-hub returns a 422 rather than silently leaking across tenants."""
    captured: dict = {}

    async def _fake_post(url, **kwargs):
        captured["json"] = kwargs.get("json", {})
        return _mock_response(200, {"data": "ok"})

    mock_client = MagicMock()
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    mock_client.post = AsyncMock(side_effect=_fake_post)

    with (
        patch(
            "temporal.activities.agent_activity.get_settings",
            return_value=_fake_settings(),
        ),
        patch("httpx.AsyncClient", return_value=mock_client),
    ):
        await run_agent_node(
            AgentParams(agent_id=str(uuid.uuid4()), prompt="x", org_id="")
        )

    assert captured["json"]["company_id"] is None
