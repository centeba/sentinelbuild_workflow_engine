"""SSRF guard for outbound requests from workflow nodes (S3).

The canonical implementation now lives in ``sentinelbuild_sdk.ssrf`` so every
platform service shares one guard (A3). This module re-exports it for existing
``from shared.ssrf import ...`` callers:

- ``validate_url`` / ``SsrfError`` — pre-flight validation (used by the
  Playwright-driven ``scraper_activity``, where the browser makes the request).
- ``guarded_send`` — connect-time IP-pinned send that closes the TOCTOU /
  DNS-rebind window (used by ``http_activity``).
"""

from __future__ import annotations

from shared._platform.ssrf import (
    SsrfError,
    guarded_send,
    resolve_pinned_ip,
    validate_url,
)

__all__ = ["SsrfError", "guarded_send", "resolve_pinned_ip", "validate_url"]
