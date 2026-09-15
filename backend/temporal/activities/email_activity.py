"""Email sending activity via SMTP or SendGrid."""

from dataclasses import dataclass
from typing import Any

from temporalio import activity


@dataclass
class EmailParams:
    to: str
    subject: str
    body: str
    credential_id: str | None = None
    org_id: str | None = None
    html_body: str | None = None
    from_name: str = "Mit Stack"


@activity.defn
async def send_email(params: EmailParams) -> dict[str, Any]:
    if not params.credential_id or not params.org_id:
        raise ValueError("Email credential_id and org_id are required")

    import uuid

    from sqlalchemy import select

    from api.models.credential import Credential
    from api.services.credential_service import get_secret_data
    from shared.db import AsyncSessionLocal, set_current_org

    # Worker path (bypasses request auth) → stamp the RLS tenant GUC so FORCE RLS
    # on ``credentials`` admits this org's row once the non-superuser role is live.
    set_current_org(params.org_id)
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Credential).where(
                Credential.id == uuid.UUID(params.credential_id),
                Credential.org_id == uuid.UUID(params.org_id),
            )
        )
        cred = result.scalar_one_or_none()
        if not cred:
            raise ValueError(f"Email credential {params.credential_id} not found")
        secret = get_secret_data(cred)

    if cred.type == "smtp":
        await _send_via_smtp(secret, params)
    elif cred.type == "api_key" and "sendgrid" in cred.name.lower():
        await _send_via_sendgrid(secret, params)
    else:
        raise ValueError(f"Unsupported email credential type: {cred.type}")

    return {"status": "sent", "to": params.to, "subject": params.subject}


async def _send_via_smtp(secret: dict[str, Any], params: EmailParams) -> None:
    from email.mime.multipart import MIMEMultipart
    from email.mime.text import MIMEText

    import aiosmtplib

    msg = MIMEMultipart("alternative")
    msg["Subject"] = params.subject
    msg["From"] = f"{params.from_name} <{secret['from_email']}>"
    msg["To"] = params.to

    msg.attach(MIMEText(params.body, "plain"))
    if params.html_body:
        msg.attach(MIMEText(params.html_body, "html"))

    await aiosmtplib.send(
        msg,
        hostname=secret["host"],
        port=int(secret.get("port", 587)),
        username=secret.get("username"),
        password=secret.get("password"),
        use_tls=secret.get("use_tls", False),
        start_tls=secret.get("start_tls", True),
    )


async def _send_via_sendgrid(secret: dict[str, Any], params: EmailParams) -> None:
    import httpx

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            "https://api.sendgrid.com/v3/mail/send",
            headers={"Authorization": f"Bearer {secret['api_key']}"},
            json={
                "personalizations": [{"to": [{"email": params.to}]}],
                "from": {
                    "email": secret.get("from_email", "noreply@mitstack.io"),
                    "name": params.from_name,
                },
                "subject": params.subject,
                "content": [{"type": "text/plain", "value": params.body}],
            },
        )
        resp.raise_for_status()
