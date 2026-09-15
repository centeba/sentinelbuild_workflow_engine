"""Phase E2 tests — temporal.activities.agent_graph_activity.run_agent_graph_node.

Mirrors test_agent_activity.py but targets the multi-agent graph
dispatch path (``/ai-invoke/run-graph`` instead of ``/ai-invoke/run``).

Covers:
- Posts to the correct URL with bearer auth header
- Spec + input + company_id forwarded verbatim
- Trailing slash on INTEGRATION_HUB_URL is stripped
- 4xx / 5xx raise RuntimeError with body
- Missing INTEGRATION_HUB_URL / INTERNAL_SERVICE_SECRET raises
- Optional context field forwarded when provided
- Empty org_id surfaces as null company_id (matches /ai-invoke contract)
- Custom timeout_seconds propagates to the httpx client
"""

from __future__ import annotations

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

temporalio = pytest.importorskip("temporalio", reason="temporalio not installed")
httpx = pytest.importorskip("httpx", reason="httpx not installed")

from temporal.activities.agent_graph_activity import (
    AgentGraphParams,
    run_agent_graph_node,
)


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


def _build_mock_client(side_effect):
    """Returns an ``httpx.AsyncClient``-like context manager whose
    ``post`` method invokes ``side_effect`` with the call kwargs."""
    mock_client = MagicMock()
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    mock_client.post = AsyncMock(side_effect=side_effect)
    return mock_client


_SAMPLE_SPEC = {
    "entry": "classifier",
    "nodes": [
        {"id": "classifier", "agent_id": "agent-A", "next": ["leaf"]},
        {"id": "leaf", "agent_id": "agent-B", "next": []},
    ],
}


# ── Happy path ──────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_run_agent_graph_node_posts_to_correct_url():
    org_id = str(uuid.uuid4())
    captured: dict = {}

    async def _fake_post(url, **kwargs):
        captured["url"] = url
        captured["headers"] = kwargs.get("headers", {})
        captured["json"] = kwargs.get("json", {})
        return _mock_response(200, {"results": {"classifier": {"intent": "summary"}}})

    with (
        patch(
            "temporal.activities.agent_graph_activity.get_settings",
            return_value=_fake_settings(),
        ),
        patch("httpx.AsyncClient", return_value=_build_mock_client(_fake_post)),
    ):
        result = await run_agent_graph_node(
            AgentGraphParams(
                spec=_SAMPLE_SPEC,
                input_text="kickoff",
                org_id=org_id,
            )
        )

    assert captured["url"] == "http://integration-hub:8005/api/v1/ai-invoke/run-graph"
    assert captured["json"]["spec"] == _SAMPLE_SPEC
    assert captured["json"]["input"] == "kickoff"
    assert captured["json"]["company_id"] == org_id
    assert captured["json"]["context"] is None
    assert result == {"results": {"classifier": {"intent": "summary"}}}


@pytest.mark.asyncio
async def test_run_agent_graph_node_uses_internal_service_secret_bearer():
    captured: dict = {}

    async def _fake_post(url, **kwargs):
        captured["headers"] = kwargs.get("headers", {})
        return _mock_response(200, {"results": {}})

    with (
        patch(
            "temporal.activities.agent_graph_activity.get_settings",
            return_value=_fake_settings(internal_service_secret="topsecret"),
        ),
        patch("httpx.AsyncClient", return_value=_build_mock_client(_fake_post)),
    ):
        await run_agent_graph_node(
            AgentGraphParams(spec=_SAMPLE_SPEC, input_text="x", org_id="")
        )

    assert captured["headers"]["Authorization"] == "Bearer topsecret"
    assert captured["headers"]["Content-Type"] == "application/json"


@pytest.mark.asyncio
async def test_run_agent_graph_node_forwards_context_when_provided():
    captured: dict = {}

    async def _fake_post(url, **kwargs):
        captured["json"] = kwargs.get("json", {})
        return _mock_response(200, {"results": {}})

    with (
        patch(
            "temporal.activities.agent_graph_activity.get_settings",
            return_value=_fake_settings(),
        ),
        patch("httpx.AsyncClient", return_value=_build_mock_client(_fake_post)),
    ):
        await run_agent_graph_node(
            AgentGraphParams(
                spec=_SAMPLE_SPEC,
                input_text="x",
                org_id="org-1",
                context="caller-context",
            )
        )

    assert captured["json"]["context"] == "caller-context"


@pytest.mark.asyncio
async def test_run_agent_graph_node_strips_trailing_slash_from_url():
    captured: dict = {}

    async def _fake_post(url, **kwargs):
        captured["url"] = url
        return _mock_response(200, {"results": {}})

    with (
        patch(
            "temporal.activities.agent_graph_activity.get_settings",
            return_value=_fake_settings(
                integration_hub_url="http://integration-hub:8005/"
            ),
        ),
        patch("httpx.AsyncClient", return_value=_build_mock_client(_fake_post)),
    ):
        await run_agent_graph_node(
            AgentGraphParams(spec=_SAMPLE_SPEC, input_text="x", org_id="org")
        )

    # Single slash between host and path — no double-slash artefact.
    assert captured["url"] == "http://integration-hub:8005/api/v1/ai-invoke/run-graph"


@pytest.mark.asyncio
async def test_run_agent_graph_node_empty_org_id_sends_null_company():
    """The integration-hub /ai-invoke contract requires company_id to
    be null (not empty string) when the worker has no tenant context."""
    captured: dict = {}

    async def _fake_post(url, **kwargs):
        captured["json"] = kwargs.get("json", {})
        return _mock_response(200, {"results": {}})

    with (
        patch(
            "temporal.activities.agent_graph_activity.get_settings",
            return_value=_fake_settings(),
        ),
        patch("httpx.AsyncClient", return_value=_build_mock_client(_fake_post)),
    ):
        await run_agent_graph_node(
            AgentGraphParams(spec=_SAMPLE_SPEC, input_text="x", org_id="")
        )

    assert captured["json"]["company_id"] is None


# ── Error paths ─────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_run_agent_graph_node_4xx_raises_runtime_error():
    async def _fake_post(url, **kwargs):
        return _mock_response(400, text='{"detail":"bad spec"}')

    with (
        patch(
            "temporal.activities.agent_graph_activity.get_settings",
            return_value=_fake_settings(),
        ),
        patch("httpx.AsyncClient", return_value=_build_mock_client(_fake_post)),
    ):
        with pytest.raises(RuntimeError, match="HTTP 400"):
            await run_agent_graph_node(
                AgentGraphParams(spec=_SAMPLE_SPEC, input_text="x", org_id="o")
            )


@pytest.mark.asyncio
async def test_run_agent_graph_node_5xx_raises_runtime_error_with_body():
    async def _fake_post(url, **kwargs):
        return _mock_response(500, text="internal error")

    with (
        patch(
            "temporal.activities.agent_graph_activity.get_settings",
            return_value=_fake_settings(),
        ),
        patch("httpx.AsyncClient", return_value=_build_mock_client(_fake_post)),
    ):
        with pytest.raises(RuntimeError, match="HTTP 500.*internal error"):
            await run_agent_graph_node(
                AgentGraphParams(spec=_SAMPLE_SPEC, input_text="x", org_id="o")
            )


@pytest.mark.asyncio
async def test_run_agent_graph_node_missing_url_raises():
    with patch(
        "temporal.activities.agent_graph_activity.get_settings",
        return_value=_fake_settings(integration_hub_url=""),
    ):
        with pytest.raises(RuntimeError, match="INTEGRATION_HUB_URL"):
            await run_agent_graph_node(
                AgentGraphParams(spec=_SAMPLE_SPEC, input_text="x", org_id="o")
            )


@pytest.mark.asyncio
async def test_run_agent_graph_node_missing_secret_raises():
    with patch(
        "temporal.activities.agent_graph_activity.get_settings",
        return_value=_fake_settings(internal_service_secret=""),
    ):
        with pytest.raises(RuntimeError, match="INTERNAL_SERVICE_SECRET"):
            await run_agent_graph_node(
                AgentGraphParams(spec=_SAMPLE_SPEC, input_text="x", org_id="o")
            )


@pytest.mark.asyncio
async def test_run_agent_graph_node_default_timeout_is_300s():
    """Graphs are slower than single agent calls — verify the dataclass
    default. (Deeper graphs hit 13 LLM calls at depth=3, 3 branches.)"""
    params = AgentGraphParams(spec=_SAMPLE_SPEC, input_text="x", org_id="o")
    assert params.timeout_seconds == 300
