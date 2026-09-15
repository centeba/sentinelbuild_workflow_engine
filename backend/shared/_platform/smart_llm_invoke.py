"""SmartLlmInvokeClient — runtime invocation of platform AI agents.

This module is also **the single entry point** for the cross-service
AI-budget gate. Vertical services that invoke ``smart_llm.Agent``
in-process — pages-api, esign, mit-stack, doc-vault — call
``assert_budget_allowed_or_raise_http`` (HTTP routes) or
``assert_budget_allowed`` (Temporal activities / non-HTTP contexts)
immediately before the completion. There is no per-service wrapper:
the SDK owns the call, the typed 429 translation, and the fail-open
policy in one place so behavior stays consistent across the platform.

This is the **inference** companion to ``SmartLlmAdminClient`` (provisioning).
Vertical apps use it when they want a platform-managed agent — with its
configured provider, model, system prompt, and attached skills — to produce
a completion, instead of running an in-process ``smart_llm.Agent`` themselves.

Use-case split (also see SDK README):

* **In-process** (``smart_llm.Agent`` directly, or via the SDK's
  ``skill_to_agent`` helper): lowest latency, no network hop, no platform
  observability. Right for high-volume bulk processing (video frame
  analysis, batch imports) where 100ms × N matters.

* **Platform-invoked** (this client): every call routes through
  integration-hub. Skills attached in the AI Admin UI take effect
  automatically (the agent's prompt is augmented). Cost/usage is tracked
  centrally; provider failover and key rotation are managed platform-side.
  Right for user-facing single-shot inference where audit + composability
  beat ~50–200ms of network latency.

Both paths can coexist — the choice is per call site.
"""

import logging
from typing import Any
from uuid import UUID

from shared._platform.config import SentinelBuildSettings
from shared._platform.errors import RateLimitError, SentinelBuildError
from shared._platform.http import BaseHttpClient

logger = logging.getLogger(__name__)

# Canonical user-facing copy for budget exhaustion. Defined once here so
# every service surfaces the same message — referenced by the
# web_builder AI dialog client too. Keep in sync if you change it.
LLM_BUDGET_EXHAUSTED_MESSAGE = "AI budget exhausted — contact your admin."


class SmartLlmInvokeClient(BaseHttpClient):
    """Client for ``POST /api/v1/ai-invoke/run``.

    Auth: M2M via ``Authorization: Bearer ${INTERNAL_SERVICE_SECRET}``
    (the SDK's ``internal_api_key`` setting). When called from a vertical
    app's backend (the typical case), pass ``company_id`` explicitly —
    integration-hub's ``AnyAuthDep`` requires it for internal-service
    callers since there's no JWT-derived company.
    """

    def __init__(self, settings: SentinelBuildSettings) -> None:
        super().__init__(
            settings,
            base_url=settings.integration_hub_url,
            use_internal_key=False,  # Bearer header, not X-API-Key
        )
        # InternalServiceDep wants `Authorization: Bearer <secret>`; carry
        # the shared secret as a synthetic bearer token.
        self._bearer_token = settings.internal_api_key

    async def run(
        self,
        *,
        agent_name: str,
        prompt: str,
        company_id: UUID | str,
        context: str | None = None,
    ) -> dict[str, Any]:
        """Run a configured agent on ``prompt`` and return the response.

        Args:
            agent_name: Name of an ``AIAgentConfig`` owned by ``company_id``.
                For agents synced via :class:`AgentBundle` from a vertical
                app, the qualified name is ``"<source_app>:<agent_name>"``
                (e.g. ``"restoration:photo_triage"``).
            prompt: The user/input prompt text.
            company_id: Tenant the agent runs against.
            context: Optional extra context string. The agent prepends it
                as ``"Context: <context>\\n\\nInput: <prompt>"``.

        Returns:
            ``{ "agent_name", "data", "provider", "model" }``. The shape of
            ``data`` depends on the agent's configured ``response_format``
            (typically a JSON object for ``response_format="json"``, else
            free-form text).
        """
        result: dict[str, Any] = await self.post(
            "/api/v1/ai-invoke/run",
            json={
                "agent_name": agent_name,
                "prompt": prompt,
                "context": context,
                "company_id": str(company_id),
            },
        )
        return result

    async def assert_budget_allowed(self, *, company_id: UUID | str) -> None:
        """Raise ``RateLimitError`` when the tenant has exhausted its monthly
        AI budget. Otherwise returns silently.

        Use this in **non-HTTP contexts** — Temporal activities, scripts,
        background workers — where you want to handle :class:`RateLimitError`
        yourself (e.g. doc-vault re-raises as ``AiBudgetExhausted`` so the
        workflow records ``SKIPPED_BUDGET`` instead of ``FAILED``).

        For FastAPI routes, prefer :meth:`assert_budget_allowed_or_raise_http`
        which translates the 429 into ``HTTPException`` with the canonical
        :data:`LLM_BUDGET_EXHAUSTED_MESSAGE` and fails open on transport / 5xx.

        The integration-hub endpoint fires the bell-icon alert + bus publish
        on first cap trip and throttles subsequent calls, so the side effects
        happen exactly once per (company, month) regardless of which service
        spotted the cap.
        """
        # In-cluster M2M call — base_url is integration-hub's container
        # origin (e.g. http://integration-hub-api:8001), so the path is
        # the bare service-relative ``/api/v1/...``, same convention as
        # ``run`` above (both go straight to the container, never through
        # an nginx ingress that would need the ``/api/integration-hub``
        # prefix stripped).
        await self.post(
            "/api/v1/ai-usage/assert-allowed",
            json={"company_id": str(company_id)},
        )

    async def assert_budget_allowed_or_raise_http(
        self, *, company_id: UUID | str
    ) -> None:
        """HTTP-route variant of :meth:`assert_budget_allowed`.

        Same semantics, but designed for use inside a FastAPI route::

            async with SmartLlmInvokeClient(settings) as gate:
                await gate.assert_budget_allowed_or_raise_http(
                    company_id=user.org_id
                )

        Behavior:
        - **429**: raise ``fastapi.HTTPException(429,
          LLM_BUDGET_EXHAUSTED_MESSAGE)``. The route's caller catches it as a
          normal HTTPException and surfaces the message to the client.
        - **Transport error / 5xx**: log a warning and return (fail open).
          A flaky integration-hub must not take down vertical-app
          authoring; the inner ``Agent._check_budget`` remains as
          defense-in-depth where local usage context is wired in.
        - **Auth misconfig (401/403)**: log error and return. Same
          rationale: don't black-hole the call because of a config drift.

        FastAPI is imported lazily so the SDK doesn't take a FastAPI
        dependency for services that only use the non-HTTP variant.
        """
        try:
            await self.assert_budget_allowed(company_id=company_id)
        except RateLimitError as exc:
            from fastapi import HTTPException, status  # lazy import

            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=LLM_BUDGET_EXHAUSTED_MESSAGE,
            ) from exc
        except SentinelBuildError as exc:
            # 4xx other than 429, 5xx, or transport — fail open so
            # integration-hub flakes don't break authoring.
            logger.warning(
                "ai_budget_gate_fail_open status=%s err=%s",
                exc.status_code,
                exc,
                exc_info=True,
            )
            return
        except Exception:  # noqa: BLE001
            # Truly unexpected (e.g. httpx ConnectError that escaped the
            # SDK's typed mapping). Same fail-open policy.
            logger.warning("ai_budget_gate_unreachable", exc_info=True)
            return
