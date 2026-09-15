"""Activity that sends workflow failure/completion notifications via Integration Hub."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

import httpx
import structlog
from temporalio import activity

from shared.config import get_settings

log = structlog.get_logger(__name__)


@dataclass
class NotifyWorkflowEventParams:
    execution_id: str
    workflow_id: str
    org_id: str
    workflow_name: str
    event: str  # "failed" | "completed" | "approval_required"
    error_message: str | None = None
    trigger_type: str = "manual"
    notify_channels: list[str] = field(default_factory=list)  # ["email", "webhook"]
    notify_recipients: list[str] = field(default_factory=list)  # email addresses
    notify_webhook_url: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)


@activity.defn
async def notify_workflow_event(params: NotifyWorkflowEventParams) -> None:
    """Post a notification to Integration Hub for a workflow lifecycle event.

    Only fires when Integration Hub is configured. Silently skips if unconfigured
    so workflows without notification config don't fail because of a missing env var.
    """
    settings = get_settings()
    if not settings.integration_hub_url or not settings.integration_hub_api_key:
        log.debug(
            "notify_skipped_no_hub_config",
            workflow_id=params.workflow_id,
            event=params.event,
        )
        return

    hub_base = settings.integration_hub_url.rstrip("/")
    headers = {
        "Authorization": f"Bearer {settings.integration_hub_api_key}",
        "Content-Type": "application/json",
    }

    ts = datetime.now(UTC).isoformat()
    body_context = {
        "workflow_id": params.workflow_id,
        "workflow_name": params.workflow_name,
        "execution_id": params.execution_id,
        "org_id": params.org_id,
        "event": params.event,
        "trigger_type": params.trigger_type,
        "timestamp": ts,
        **({"error": params.error_message} if params.error_message else {}),
        **params.extra,
    }

    async with httpx.AsyncClient(timeout=15) as client:
        # ── Email notification ────────────────────────────────────────────────
        if "email" in params.notify_channels and params.notify_recipients:
            subject = _email_subject(params.event, params.workflow_name)
            body_html = _email_body_html(params)
            try:
                resp = await client.post(
                    f"{hub_base}/api/v1/email/send",
                    headers=headers,
                    json={
                        "to": params.notify_recipients,
                        "subject": subject,
                        "html_body": body_html,
                        "context": body_context,
                    },
                )
                resp.raise_for_status()
                log.info(
                    "notify_email_sent",
                    workflow_id=params.workflow_id,
                    event=params.event,
                    recipients=params.notify_recipients,
                )
            except Exception:
                # Notification failure must not fail the workflow
                log.error(
                    "notify_email_failed",
                    workflow_id=params.workflow_id,
                    event=params.event,
                    exc_info=True,
                )

        # ── Webhook notification ──────────────────────────────────────────────
        if "webhook" in params.notify_channels and params.notify_webhook_url:
            try:
                resp = await client.post(
                    f"{hub_base}/api/v1/webhook/send",
                    headers=headers,
                    json={
                        "url": params.notify_webhook_url,
                        "method": "POST",
                        "payload": body_context,
                    },
                )
                resp.raise_for_status()
                log.info(
                    "notify_webhook_sent",
                    workflow_id=params.workflow_id,
                    event=params.event,
                    webhook_url=params.notify_webhook_url,
                )
            except Exception:
                log.error(
                    "notify_webhook_failed",
                    workflow_id=params.workflow_id,
                    event=params.event,
                    exc_info=True,
                )


def _email_subject(event: str, workflow_name: str) -> str:
    labels = {
        "failed": f"⚠ Workflow failed: {workflow_name}",
        "completed": f"✓ Workflow completed: {workflow_name}",
        "approval_required": f"Action required: approve {workflow_name}",
    }
    return labels.get(event, f"Workflow event [{event}]: {workflow_name}")


def _email_body_html(params: NotifyWorkflowEventParams) -> str:
    err_section = (
        f"<p><strong>Error:</strong> <code>{params.error_message}</code></p>"
        if params.error_message
        else ""
    )
    return f"""
<h2>Workflow {params.event.replace("_", " ").title()}</h2>
<p><strong>Workflow:</strong> {params.workflow_name}</p>
<p><strong>Execution ID:</strong> {params.execution_id}</p>
<p><strong>Trigger:</strong> {params.trigger_type}</p>
{err_section}
<p style="color:#888;font-size:12px;">SentinelBuild — Mit Stack</p>
"""
