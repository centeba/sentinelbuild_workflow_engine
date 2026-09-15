"""Manage IMAP polling workflow lifecycle via Temporal.

When a workflow with trigger_type="imap_trigger" is activated, this service
starts a Temporal cron workflow. When deactivated or deleted, it cancels it.

Temporal workflow ID convention: "imap-poller-{mit_stack_workflow_id}"
This ensures only one poller exists per user workflow at any time.
"""

import uuid
from typing import Any

from temporalio.client import Client, WorkflowExecutionStatus
from temporalio.service import RPCError

from shared.config import get_settings

settings = get_settings()

POLLER_ID_PREFIX = "imap-poller-"


def _poller_id(workflow_id: str | uuid.UUID) -> str:
    return f"{POLLER_ID_PREFIX}{workflow_id}"


async def _get_client() -> Client:
    from shared.temporal_client import get_temporal_client

    return await get_temporal_client()


async def start_imap_poller(
    workflow_id: str,
    org_id: str,
    credential_id: str,
    folder: str = "INBOX",
    poll_interval_cron: str = "* * * * *",  # every minute by default
    mark_as_read: bool = False,
    max_emails_per_poll: int = 10,
) -> str:
    """
    Start (or replace) the IMAP cron poller for a given workflow.
    Returns the Temporal workflow ID.
    """
    from temporal.workflows.imap_polling_workflow import (
        ImapPollingParams,
        ImapPollingWorkflow,
    )

    temporal_id = _poller_id(workflow_id)

    # Cancel existing poller first (idempotent replacement)
    await stop_imap_poller(workflow_id, silent=True)

    client = await _get_client()
    await client.start_workflow(
        ImapPollingWorkflow.run,
        ImapPollingParams(
            workflow_id=workflow_id,
            org_id=org_id,
            credential_id=credential_id,
            folder=folder,
            mark_as_read=mark_as_read,
            max_emails_per_poll=max_emails_per_poll,
        ),
        id=temporal_id,
        task_queue=settings.temporal_task_queue,
        cron_schedule=poll_interval_cron,
    )
    return temporal_id


async def stop_imap_poller(workflow_id: str, silent: bool = False) -> bool:
    """
    Cancel the IMAP cron poller for a given workflow.
    Returns True if a running poller was cancelled, False if none existed.
    """
    temporal_id = _poller_id(workflow_id)
    try:
        client = await _get_client()
        handle = client.get_workflow_handle(temporal_id)
        desc = await handle.describe()
        if desc.status in (
            WorkflowExecutionStatus.RUNNING,
            WorkflowExecutionStatus.CONTINUED_AS_NEW,
        ):
            await handle.cancel()
            return True
    except RPCError:
        pass  # Workflow not found — that's fine
    except Exception:
        if not silent:
            raise
    return False


async def sync_imap_poller(
    workflow_id: str, org_id: str, trigger_config: dict[str, Any], is_active: bool
) -> None:
    """
    Called whenever a workflow is created, updated, or toggled.
    Starts the poller if active with imap_trigger, stops it otherwise.
    """
    if is_active and trigger_config.get("credential_id"):
        await start_imap_poller(
            workflow_id=workflow_id,
            org_id=org_id,
            credential_id=trigger_config["credential_id"],
            folder=trigger_config.get("folder", "INBOX"),
            poll_interval_cron=trigger_config.get("poll_cron", "* * * * *"),
            mark_as_read=trigger_config.get("mark_as_read", False),
            max_emails_per_poll=trigger_config.get("max_emails_per_poll", 10),
        )
    else:
        await stop_imap_poller(workflow_id, silent=True)
