"""Base async HTTP client shared by every service client.

Handles:
- httpx AsyncClient lifecycle (context manager + explicit close)
- Auth header injection (Bearer token or X-API-Key for internal calls)
- Trace ID propagation (X-Trace-Id, generated if not supplied)
- Idempotency-Key forwarding when set on the call
- Standard error mapping (4xx/5xx → typed exceptions)
- Retries with exponential backoff on connection errors and 5xx
"""

import asyncio
import logging
import uuid
from collections.abc import Mapping
from contextvars import ContextVar
from types import TracebackType
from typing import Any
from urllib.parse import urlsplit

import httpx
from smart_llm.resilience import CircuitOpenError, get_breaker

from shared._platform.config import SentinelBuildSettings
from shared._platform.errors import (
    AuthError,
    NotFoundError,
    RateLimitError,
    SentinelBuildError,
    ServerError,
    ServiceUnavailableError,
)

logger = logging.getLogger(__name__)

# Per-request trace context — set by the trace-id middleware (forthcoming) or the caller.
_trace_id_var: ContextVar[str | None] = ContextVar(
    "sentinelbuild_trace_id", default=None
)
_idempotency_key_var: ContextVar[str | None] = ContextVar(
    "sentinelbuild_idempotency_key", default=None
)

TRACE_ID_HEADER = "X-Trace-Id"
IDEMPOTENCY_KEY_HEADER = "Idempotency-Key"


def get_current_trace_id() -> str | None:
    """Return the trace ID for the current async context, if set."""
    return _trace_id_var.get()


def set_trace_id(trace_id: str | None) -> None:
    """Set the trace ID for the current async context. Use in middleware or tests."""
    _trace_id_var.set(trace_id)


def with_idempotency_key(key: str) -> None:
    """Mark the current async context to send an Idempotency-Key on the next request."""
    _idempotency_key_var.set(key)


class BaseHttpClient:
    """Async HTTP client base. Subclassed by each service client.

    Use as an async context manager::

        async with MitStackClient(settings) as client:
            await client.trigger_workflow(...)

    Or explicitly::

        client = MitStackClient(settings)
        try:
            await client.trigger_workflow(...)
        finally:
            await client.aclose()
    """

    base_url: str = ""

    def __init__(
        self,
        settings: SentinelBuildSettings,
        *,
        base_url: str | None = None,
        bearer_token: str | None = None,
        use_internal_key: bool = False,
        extra_headers: Mapping[str, str] | None = None,
    ) -> None:
        self.settings = settings
        self.base_url = (base_url or self.base_url).rstrip("/")
        self._bearer_token = bearer_token
        self._use_internal_key = use_internal_key
        self._extra_headers = dict(extra_headers or {})
        self._client: httpx.AsyncClient | None = None

    async def __aenter__(self) -> "BaseHttpClient":
        self._client = httpx.AsyncClient(
            base_url=self.base_url,
            timeout=self.settings.request_timeout_seconds,
        )
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        await self.aclose()

    async def aclose(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    def _build_headers(self, extra: Mapping[str, str] | None = None) -> dict[str, str]:
        headers: dict[str, str] = {"Accept": "application/json", **self._extra_headers}
        if self._bearer_token:
            headers["Authorization"] = f"Bearer {self._bearer_token}"
        if self._use_internal_key and self.settings.internal_api_key:
            headers["X-API-Key"] = self.settings.internal_api_key

        # Trace ID — propagate if set, else generate one
        trace_id = _trace_id_var.get() or str(uuid.uuid4())
        headers[TRACE_ID_HEADER] = trace_id

        # Idempotency key — forward if set on this request's context
        idempotency_key = _idempotency_key_var.get()
        if idempotency_key:
            headers[IDEMPOTENCY_KEY_HEADER] = idempotency_key
            # Consume the key — only applies to the next request
            _idempotency_key_var.set(None)

        if extra:
            headers.update(extra)
        return headers

    def _breaker_name(self) -> str:
        """Per-host breaker key. Two clients pointed at the same host share one
        breaker, so a downed dependency is discovered once per replica."""
        host = urlsplit(self.base_url).netloc or self.__class__.__name__
        return f"sdk:{host}"

    async def _request(
        self,
        method: str,
        path: str,
        *,
        params: Mapping[str, Any] | None = None,
        json: Any = None,
        data: Any = None,
        files: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> httpx.Response:
        """Issue a request with retries on 5xx and connection errors, guarded by
        a per-host circuit breaker.

        The breaker fails fast with a typed ``ServiceUnavailableError`` (503)
        while a downstream host is OPEN, rather than letting every caller re-run
        the full retry ladder against a service that is already down. Only
        5xx-after-retries and network errors count as breaker failures — a 4xx is
        a healthy response and records a *success*, since the host is clearly up.
        """
        if self._client is None:
            # Lazy-create — supports clients used without `async with`
            self._client = httpx.AsyncClient(
                base_url=self.base_url,
                timeout=self.settings.request_timeout_seconds,
            )

        breaker = None
        if self.settings.circuit_breaker_enabled:
            breaker = get_breaker(
                self._breaker_name(),
                failure_threshold=self.settings.circuit_breaker_failure_threshold,
                recovery_timeout=self.settings.circuit_breaker_recovery_timeout,
            )
            try:
                await breaker.before_call()
            except CircuitOpenError as exc:
                raise ServiceUnavailableError(
                    f"{self._breaker_name()} unavailable (circuit open); "
                    f"retry after {exc.retry_after:.1f}s",
                    status_code=503,
                    retry_after=exc.retry_after,
                ) from exc

        try:
            response = await self._send_with_retries(
                method,
                path,
                params=params,
                json=json,
                data=data,
                files=files,
                headers=headers,
            )
        except SentinelBuildError:
            # Only raised here on network-error-after-retries — a host-health
            # failure. (4xx/5xx come back as a response below, not as a raise.)
            if breaker is not None:
                await breaker.record_failure()
            raise

        if breaker is not None:
            if response.status_code >= 500:
                await breaker.record_failure()
            else:
                await breaker.record_success()

        self._raise_for_status(response)
        return response

    async def _send_with_retries(
        self,
        method: str,
        path: str,
        *,
        params: Mapping[str, Any] | None = None,
        json: Any = None,
        data: Any = None,
        files: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> httpx.Response:
        """Send with retries on 5xx and connection errors. Returns the final
        response (including a 5xx once retries are exhausted); raises
        ``SentinelBuildError`` only when the network never yielded a response.
        Breaker accounting and status→exception mapping are the caller's job."""
        assert self._client is not None  # set by _request before calling
        last_exc: Exception | None = None
        for attempt in range(self.settings.request_max_retries + 1):
            try:
                response = await self._client.request(
                    method,
                    path,
                    params=params,
                    json=json,
                    data=data,
                    files=files,
                    headers=self._build_headers(headers),
                )
            except (httpx.ConnectError, httpx.ReadTimeout) as exc:
                last_exc = exc
                if attempt >= self.settings.request_max_retries:
                    raise SentinelBuildError(
                        f"Network error after retries: {exc}"
                    ) from exc
                await asyncio.sleep(self.settings.request_backoff_factor * (2**attempt))
                continue

            if (
                response.status_code >= 500
                and attempt < self.settings.request_max_retries
            ):
                logger.warning(
                    "5xx from %s %s (status=%s, attempt=%s) — retrying",
                    method,
                    path,
                    response.status_code,
                    attempt + 1,
                )
                await asyncio.sleep(self.settings.request_backoff_factor * (2**attempt))
                continue

            return response

        raise SentinelBuildError(f"Request failed without response: {last_exc}")

    @staticmethod
    def _raise_for_status(response: httpx.Response) -> None:
        if response.status_code < 400:
            return
        body = response.text
        if response.status_code in (401, 403):
            raise AuthError(
                f"{response.status_code} {response.reason_phrase}",
                status_code=response.status_code,
                response_body=body,
            )
        if response.status_code == 404:
            raise NotFoundError(
                f"Not found: {response.request.url}",
                status_code=404,
                response_body=body,
            )
        if response.status_code == 429:
            raise RateLimitError(
                "Rate limit exceeded", status_code=429, response_body=body
            )
        if response.status_code >= 500:
            raise ServerError(
                f"{response.status_code} {response.reason_phrase}",
                status_code=response.status_code,
                response_body=body,
            )
        raise SentinelBuildError(
            f"{response.status_code} {response.reason_phrase}",
            status_code=response.status_code,
            response_body=body,
        )

    async def get(self, path: str, **kw: Any) -> Any:
        r = await self._request("GET", path, **kw)
        return r.json() if r.content else None

    async def post(self, path: str, **kw: Any) -> Any:
        r = await self._request("POST", path, **kw)
        return r.json() if r.content else None

    async def put(self, path: str, **kw: Any) -> Any:
        r = await self._request("PUT", path, **kw)
        return r.json() if r.content else None

    async def patch(self, path: str, **kw: Any) -> Any:
        r = await self._request("PATCH", path, **kw)
        return r.json() if r.content else None

    async def delete(self, path: str, **kw: Any) -> Any:
        r = await self._request("DELETE", path, **kw)
        return r.json() if r.content else None
