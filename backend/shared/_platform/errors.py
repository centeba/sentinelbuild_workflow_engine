"""Exception hierarchy for the SDK."""

from __future__ import annotations


class SentinelBuildError(Exception):
    """Base class for all SDK errors."""

    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        response_body: str | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.response_body = response_body


class AuthError(SentinelBuildError):
    """401/403 from a SentinelBuild service, or local JWT validation failure."""


class NotFoundError(SentinelBuildError):
    """404 from a SentinelBuild service."""


class RateLimitError(SentinelBuildError):
    """429 from a SentinelBuild service."""


class ServerError(SentinelBuildError):
    """5xx from a SentinelBuild service."""


class ServiceUnavailableError(SentinelBuildError):
    """A downstream service is being skipped because its circuit breaker is OPEN.

    Raised locally (no request left the process) when repeated failures have
    tripped the per-host breaker in :class:`~sentinelbuild_sdk.http.BaseHttpClient`.
    Carries ``status_code=503`` and a ``retry_after`` hint (seconds) so a caller
    can surface a clean 503 to its own client or fail over, instead of piling
    more load onto a downstream that is already down.
    """

    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = 503,
        response_body: str | None = None,
        retry_after: float | None = None,
    ) -> None:
        super().__init__(message, status_code=status_code, response_body=response_body)
        self.retry_after = retry_after


class WebhookVerificationError(SentinelBuildError):
    """HMAC signature missing, malformed, or doesn't match the body."""
