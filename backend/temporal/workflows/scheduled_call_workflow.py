"""Generic scheduled-call cron workflow (framework primitive).

Started with a ``cron_schedule`` (Temporal re-invokes it each tick), so each run
performs exactly one call. Mirrors ``ImapPollingWorkflow``. Domain-agnostic —
the target URL + auth headers are passed in, so this stays a pure framework
capability (first user: restoration SLA sweep).
"""

from datetime import timedelta
from typing import Any

from temporalio import workflow
from temporalio.common import RetryPolicy

with workflow.unsafe.imports_passed_through():
    from temporal.activities.scheduled_call_activity import (
        ScheduledCallParams,
        perform_scheduled_call,
    )

SOFT_RETRY = RetryPolicy(maximum_attempts=3, initial_interval=timedelta(seconds=5))


@workflow.defn
class ScheduledCallWorkflow:
    @workflow.run
    async def run(self, params: ScheduledCallParams) -> dict[str, Any]:
        return await workflow.execute_activity(
            perform_scheduled_call,
            params,
            start_to_close_timeout=timedelta(
                seconds=max(params.timeout_seconds + 15, 30)
            ),
            retry_policy=SOFT_RETRY,
        )
