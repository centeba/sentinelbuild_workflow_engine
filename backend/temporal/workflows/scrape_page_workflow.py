"""Ad-hoc scrape workflow.

A thin durable wrapper that runs the ``scrape_page`` activity once and returns
its ``{url, data}`` result. Backs the synchronous ``POST /internal/scraper/run``
endpoint, which is in turn what the agent-callable ``scrape_url`` tool invokes —
so scrapes always execute on the worker (where headless Chromium is installed),
never in the API or integration-hub process.
"""

from __future__ import annotations

from datetime import timedelta
from typing import Any

from temporalio import workflow
from temporalio.common import RetryPolicy

with workflow.unsafe.imports_passed_through():
    from temporal.activities.scraper_activity import ScrapeParams, scrape_page


NO_RETRY = RetryPolicy(maximum_attempts=1)


@workflow.defn
class ScrapePageWorkflow:
    @workflow.run
    async def run(self, params: dict[str, Any]) -> dict[str, Any]:
        return await workflow.execute_activity(
            scrape_page,
            ScrapeParams(
                url=params["url"],
                selectors=params.get("selectors", []),
                actions=params.get("actions", []),
                session_id=params.get("session_id"),
                org_id=params.get("org_id"),
                screenshot=params.get("screenshot", False),
                wait_for_selector=params.get("wait_for_selector"),
                timeout_ms=int(params.get("timeout_ms", 30000)),
            ),
            start_to_close_timeout=timedelta(minutes=10),
            retry_policy=NO_RETRY,
        )
