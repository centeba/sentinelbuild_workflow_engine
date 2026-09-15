"""Shared Temporal client factory.

mit-stack previously called ``Client.connect()`` independently from half a
dozen call sites (worker.py, executions.py, workflow_service.py, scraper.py,
imap_poller_service.py, call_workflow_activity.py) — each duplicating the
same host/namespace wiring and each one a separate place that would need to
learn about Temporal Cloud auth. Centralising it here means that config is
set in exactly one place.
"""

from __future__ import annotations

from temporalio.client import Client

from shared.config import get_settings


async def get_temporal_client(namespace: str | None = None) -> Client:
    """Connect to Temporal using the platform's shared settings.

    ``temporal_api_key`` is unset by default (self-hosted Temporal, no auth
    — matches the platform's original behavior exactly). Setting it points
    this at Temporal Cloud instead: API-key auth requires TLS, so
    ``tls=True`` is implied whenever a key is present.
    """
    settings = get_settings()
    api_key = settings.temporal_api_key or None
    return await Client.connect(
        settings.temporal_address,
        namespace=namespace or settings.temporal_namespace,
        api_key=api_key,
        tls=bool(api_key),
    )
