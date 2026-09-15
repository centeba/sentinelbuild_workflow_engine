"""IMAP polling workflow.

This Temporal workflow runs on a configurable schedule (default: every minute).
On each tick it:
  1. Fetches new emails via the IMAP activity
  2. For each new email, kicks off a WorkflowExecutor run (fire-and-forget)

Lifecycle:
  - Started (via Temporal cron schedule) when a workflow with trigger_type="imap_trigger"
    is created or activated.
  - Cancelled when the workflow is deactivated or deleted.

The Temporal workflow ID is deterministic: "imap-poller-{workflow_id}" so there
is always at most one poller per user workflow.
"""

from dataclasses import dataclass
from datetime import timedelta
from typing import Any

from temporalio import workflow
from temporalio.common import RetryPolicy

with workflow.unsafe.imports_passed_through():
    from temporal.activities.imap_activity import ImapFetchParams, fetch_new_emails


@dataclass
class ImapPollingParams:
    workflow_id: str  # Mit Stack workflow ID (UUID string)
    org_id: str
    credential_id: str
    folder: str = "INBOX"
    mark_as_read: bool = False
    max_emails_per_poll: int = 10


NO_RETRY = RetryPolicy(maximum_attempts=1)
SOFT_RETRY = RetryPolicy(maximum_attempts=3, initial_interval=timedelta(seconds=5))


@workflow.defn
class ImapPollingWorkflow:
    """
    Temporal cron workflow — polls IMAP on every schedule tick.

    Start with a cron_schedule, e.g. "* * * * *" (every minute).
    Use continue_as_new semantics automatically via Temporal's cron support.
    """

    @workflow.run
    async def run(self, params: ImapPollingParams) -> dict[str, Any]:
        workflow.logger.info(
            f"IMAP poll tick for workflow {params.workflow_id} / folder {params.folder}"
        )

        # 1. Fetch new emails
        try:
            emails = await workflow.execute_activity(
                fetch_new_emails,
                ImapFetchParams(
                    credential_id=params.credential_id,
                    org_id=params.org_id,
                    workflow_id=params.workflow_id,
                    folder=params.folder,
                    mark_as_read=params.mark_as_read,
                    max_emails=params.max_emails_per_poll,
                ),
                start_to_close_timeout=timedelta(minutes=2),
                retry_policy=SOFT_RETRY,
            )
        except Exception as exc:
            workflow.logger.error(f"IMAP fetch failed: {exc}")
            return {"emails_processed": 0, "error": str(exc)}

        if not emails:
            return {"emails_processed": 0}

        # 2. For each new email, start a WorkflowExecutor run
        import uuid

        from temporal.workflows.workflow_executor import (
            WorkflowExecutor,
            WorkflowExecutorParams,
        )

        triggered = 0
        for email_data in emails:
            execution_id = str(uuid.uuid4())
            temporal_id = f"wf-{params.workflow_id}-imap-{email_data['uid']}"

            # Create execution record first (via activity so it's durable)
            await workflow.execute_activity(
                "create_execution_record",
                {
                    "execution_id": execution_id,
                    "workflow_id": params.workflow_id,
                    "org_id": params.org_id,
                    "temporal_workflow_id": temporal_id,
                    "trigger_type": "imap_trigger",
                    "input_data": email_data,
                },
                start_to_close_timeout=timedelta(seconds=10),
                retry_policy=SOFT_RETRY,
            )

            # Start the workflow executor as a child workflow (non-blocking)
            await workflow.start_child_workflow(
                WorkflowExecutor.run,
                WorkflowExecutorParams(
                    execution_id=execution_id,
                    workflow_id=params.workflow_id,
                    org_id=params.org_id,
                    input_data=email_data,
                ),
                id=temporal_id,
                task_queue=workflow.info().task_queue,
            )
            triggered += 1

        workflow.logger.info(f"Triggered {triggered} workflow runs from IMAP poll")
        return {"emails_processed": triggered}
