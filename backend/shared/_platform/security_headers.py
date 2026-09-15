"""Security response-header middleware.

Sets a baseline of defensive HTTP response headers on every response so all
platform services (and vertical apps consuming the SDK) share one hardening
posture instead of each hand-rolling its own — previously only integration-hub
set these. Purely additive: it only writes response headers and never touches
request handling, so it cannot break a route.

Usage::

    from shared._platform.security_headers import SecurityHeadersMiddleware

    app.add_middleware(SecurityHeadersMiddleware, hsts=settings.ENVIRONMENT == "production")

``hsts`` controls the ``Strict-Transport-Security`` header (only meaningful over
HTTPS — never send it on plain-HTTP local dev, or a browser will pin the dev
origin to HTTPS). Pass an explicit bool; when left ``None`` it auto-enables from
the environment (``ENVIRONMENT=production`` or a truthy ``SEND_HSTS``).

Headers use ``setdefault`` semantics — a service or route that already set a
header (e.g. a custom ``Content-Security-Policy``) is never clobbered.
"""

import os

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response
from starlette.types import ASGIApp

# Conservative, broadly-safe defaults for a JSON API. Note: X-XSS-Protection is
# intentionally omitted — it is deprecated and can introduce vulnerabilities in
# some legacy browsers; nosniff + a real CSP are the modern controls.
_DEFAULT_HEADERS: dict[str, str] = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Permissions-Policy": "geolocation=(), microphone=(), camera=()",
}


def _hsts_from_env() -> bool:
    if os.environ.get("SEND_HSTS", "").strip().lower() in {"1", "true", "yes"}:
        return True
    return os.environ.get("ENVIRONMENT", "").strip().lower() == "production"


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Attach baseline security headers to every response.

    Args:
        app: the ASGI app to wrap.
        hsts: enable ``Strict-Transport-Security``. ``None`` (default) derives it
            from the environment (see module docstring); pass an explicit bool to
            force it — e.g. ``hsts=settings.ENVIRONMENT == "production"``.
        hsts_max_age: max-age seconds for HSTS when enabled (default 1 year).
        extra_headers: optional additional ``{name: value}`` headers to set
            (also via setdefault), e.g. a service-specific CSP.
    """

    def __init__(
        self,
        app: ASGIApp,
        *,
        hsts: bool | None = None,
        hsts_max_age: int = 31_536_000,
        extra_headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(app)
        self._hsts = _hsts_from_env() if hsts is None else hsts
        self._hsts_max_age = hsts_max_age
        self._headers = {**_DEFAULT_HEADERS, **(extra_headers or {})}

    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        response = await call_next(request)
        for name, value in self._headers.items():
            response.headers.setdefault(name, value)
        if self._hsts:
            response.headers.setdefault(
                "Strict-Transport-Security",
                f"max-age={self._hsts_max_age}; includeSubDomains",
            )
        return response
