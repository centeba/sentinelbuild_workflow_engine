"""
Approval Activity (Gap 6 — Wait / Approval node)

Sends an HTML email to the designated approver(s) containing
Approve / Reject links.  The links resolve to:
  GET /api/v1/executions/approval-action?token={token}&action=approve
  GET /api/v1/executions/approval-action?token={token}&action=reject

The token is a UUIDv4 stored in workflow_executions.approval_token.
"""

from __future__ import annotations

import smtplib
import ssl
from dataclasses import dataclass
from datetime import UTC
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from temporalio import activity

from shared.config import get_settings

_settings = get_settings()


@dataclass
class SendApprovalEmailParams:
    execution_id: str
    approval_token: str
    approver_email: str  # comma-separated for multiple approvers
    prompt: str  # the question / context shown in the email
    workflow_name: str
    node_label: str = "Approval Required"
    timeout_hours: int = 72


@activity.defn
async def send_approval_email(params: SendApprovalEmailParams) -> bool:
    """
    Send the approval request email.
    Returns True on success, False on failure (caller decides whether to raise).
    """
    base_url = _settings.public_base_url.rstrip("/")
    approve_url = f"{base_url}/api/v1/executions/approval-action?token={params.approval_token}&action=approve"
    reject_url = f"{base_url}/api/v1/executions/approval-action?token={params.approval_token}&action=reject"

    subject = f"[Mit Stack] {params.node_label} — {params.workflow_name}"
    html_body = f"""<!DOCTYPE html>
<html>
<body style="font-family: -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; background:#0F1117; color:#E2E8F0; padding:32px;">
  <div style="max-width:520px; margin:0 auto; background:#1A1D2E; border-radius:12px; border:1px solid #2D3148; padding:32px;">
    <h2 style="color:#818CF8; margin:0 0 8px;">{params.node_label}</h2>
    <p style="color:#94A3B8; margin:0 0 24px; font-size:13px;">Workflow: <strong style="color:#E2E8F0">{params.workflow_name}</strong></p>

    <div style="background:#0F1117; border-radius:8px; padding:16px; margin-bottom:24px; border-left:3px solid #6366F1;">
      <p style="margin:0; font-size:14px; color:#E2E8F0;">{params.prompt}</p>
    </div>

    <p style="color:#94A3B8; font-size:12px; margin-bottom:20px;">
      This approval request expires in <strong style="color:#E2E8F0">{params.timeout_hours} hours</strong>.
    </p>

    <div style="display:flex; gap:12px;">
      <a href="{approve_url}"
         style="display:inline-block; background:#22C55E; color:#fff; padding:12px 28px;
                border-radius:8px; text-decoration:none; font-weight:600; font-size:14px;">
        ✓ Approve
      </a>
      &nbsp;&nbsp;
      <a href="{reject_url}"
         style="display:inline-block; background:#EF4444; color:#fff; padding:12px 28px;
                border-radius:8px; text-decoration:none; font-weight:600; font-size:14px;">
        ✗ Reject
      </a>
    </div>

    <p style="color:#475569; font-size:11px; margin-top:24px;">
      Execution ID: {params.execution_id}
    </p>
  </div>
</body>
</html>"""

    # Use SMTP settings from environment
    smtp_host = _settings.smtp_host
    smtp_port = _settings.smtp_port
    smtp_user = _settings.smtp_user
    smtp_pass = _settings.smtp_pass
    smtp_from = _settings.smtp_from or smtp_user

    if not smtp_host:
        activity.logger.warning(
            "SMTP not configured — skipping approval email. Approve URL: %s",
            approve_url,
        )
        return False

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = smtp_from
    msg["To"] = params.approver_email
    msg.attach(MIMEText(html_body, "html"))

    try:
        context = ssl.create_default_context()
        with smtplib.SMTP(smtp_host, smtp_port) as server:
            server.ehlo()
            if smtp_port == 465:
                server.starttls(context=context)
            if smtp_user and smtp_pass:
                server.login(smtp_user, smtp_pass)
            server.sendmail(
                smtp_from, params.approver_email.split(","), msg.as_string()
            )
        return True
    except Exception as exc:
        activity.logger.error("Failed to send approval email: %s", exc)
        return False


@dataclass
class RegisterApprovalTokenParams:
    execution_id: str
    approval_token: str
    node_id: str
    approver_email: str
    timeout_hours: int


@activity.defn
async def register_approval_token(params: RegisterApprovalTokenParams) -> bool:
    """Persist the approval token and expiry on the WorkflowExecution row."""
    import uuid
    from datetime import datetime, timedelta

    from sqlalchemy import update

    from api.models.execution import WorkflowExecution
    from shared.db import AsyncSessionLocal

    expires_at = datetime.now(UTC) + timedelta(hours=params.timeout_hours)
    async with AsyncSessionLocal() as session:
        await session.execute(
            update(WorkflowExecution)
            .where(WorkflowExecution.id == uuid.UUID(params.execution_id))
            .values(
                approval_status="pending",
                approval_token=params.approval_token,
                approval_node_id=params.node_id,
                approval_expires_at=expires_at,
            )
        )
        await session.commit()
    return True
