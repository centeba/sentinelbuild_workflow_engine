"""Refresh-scraper-session workflow.

Thin durable wrapper dispatched by ``POST /scraper/sessions/{id}/refresh``
([api/routers/scraper.py]). It re-authenticates a stored scraper session by
running the ``refresh_scraper_session`` activity, which loads the session's
linked credential, logs in via headless Chromium, and saves a fresh encrypted
browser session (cookies + localStorage).

The workflow type name must stay ``RefreshScraperSessionWorkflow`` — the router
starts it by that string. It runs on the default task queue
(``settings.temporal_task_queue``), the same one the single worker polls.
"""

from datetime import timedelta
from typing import Any

from temporalio import workflow
from temporalio.common import RetryPolicy

with workflow.unsafe.imports_passed_through():
    from temporal.activities.scraper_activity import refresh_scraper_session


NO_RETRY = RetryPolicy(maximum_attempts=1)


@workflow.defn
class RefreshScraperSessionWorkflow:
    @workflow.run
    async def run(self, params: dict[str, Any]) -> dict[str, Any]:
        """params: {"session_id": str, "org_id": str}."""
        workflow.logger.info(f"Refreshing scraper session {params.get('session_id')}")
        return await workflow.execute_activity(
            refresh_scraper_session,
            params,
            start_to_close_timeout=timedelta(minutes=3),
            retry_policy=NO_RETRY,
        )
