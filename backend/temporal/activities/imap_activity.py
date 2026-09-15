"""IMAP email polling activity.

Connects to an IMAP mailbox, fetches unseen messages since the last
seen UID (stored in Redis), parses them, and returns structured email data.
"""

import email
import email.header
import email.utils
from dataclasses import dataclass
from typing import Any, cast

from temporalio import activity


@dataclass
class ImapFetchParams:
    """Parameters for a single IMAP poll."""

    credential_id: str
    org_id: str
    workflow_id: str  # Used to namespace the Redis "last UID" key
    folder: str = "INBOX"
    mark_as_read: bool = False
    max_emails: int = 10  # Safety cap per poll cycle


@dataclass
class ParsedEmail:
    uid: str
    message_id: str
    from_: str
    to: list[str]
    cc: list[str]
    subject: str
    body_text: str
    body_html: str
    date: str
    attachments: list[dict[str, Any]]  # [{filename, content_type, size}]

    def to_dict(self) -> dict[str, Any]:
        return {
            "uid": self.uid,
            "message_id": self.message_id,
            "from": self.from_,
            "to": self.to,
            "cc": self.cc,
            "subject": self.subject,
            "body_text": self.body_text,
            "body_html": self.body_html,
            "date": self.date,
            "attachments": self.attachments,
        }


@activity.defn
async def fetch_new_emails(params: ImapFetchParams) -> list[dict[str, Any]]:
    """
    Poll IMAP for new emails since the last run.
    Returns a list of parsed email dicts (one per new email).
    Stores the highest seen UID in Redis so the next poll only
    fetches genuinely new messages.
    """
    import uuid

    from sqlalchemy import select

    from api.models.credential import Credential
    from api.services.credential_service import get_secret_data
    from shared.db import AsyncSessionLocal, set_current_org
    from shared.redis_client import get_redis

    # Worker path → stamp the RLS tenant GUC (see credentials RLS migration).
    set_current_org(params.org_id)
    # ── Load credential ──────────────────────────────────────────────────────
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Credential).where(
                Credential.id == uuid.UUID(params.credential_id),
                Credential.org_id == uuid.UUID(params.org_id),
            )
        )
        cred = result.scalar_one_or_none()
        if not cred:
            raise ValueError(f"IMAP credential {params.credential_id} not found")
        secret = get_secret_data(cred)

    host = secret["host"]
    port = int(secret.get("port", 993))
    username = secret["username"]
    password = secret["password"]
    use_ssl = secret.get("use_ssl", True)

    # ── Get last seen UID from Redis ─────────────────────────────────────────
    redis = await get_redis()
    redis_key = f"imap:last_uid:{params.org_id}:{params.workflow_id}"
    last_uid_raw = await redis.get(redis_key)
    last_uid = int(last_uid_raw) if last_uid_raw else 0

    # ── Connect and fetch ────────────────────────────────────────────────────
    import aioimaplib

    imap = aioimaplib.IMAP4_SSL(host, port) if use_ssl else aioimaplib.IMAP4(host, port)
    await imap.wait_hello_from_server()
    await imap.login(username, password)

    try:
        await imap.select(params.folder)

        # Search for unseen messages with UID > last_uid
        if last_uid > 0:
            _, uid_data = await imap.uid("search", None, f"UID {last_uid + 1}:*")
        else:
            _, uid_data = await imap.uid("search", None, "UNSEEN")

        uid_list_raw = uid_data[0].decode().strip()
        if not uid_list_raw:
            return []

        uid_list = [int(u) for u in uid_list_raw.split() if int(u) > last_uid]
        uid_list = uid_list[-params.max_emails :]  # cap

        if not uid_list:
            return []

        parsed_emails: list[dict[str, Any]] = []
        highest_uid = last_uid

        for uid in uid_list:
            _, msg_data = await imap.uid("fetch", str(uid), "(RFC822)")
            if not msg_data or msg_data[0] is None:
                continue

            raw_email = msg_data[1] if isinstance(msg_data[1], bytes) else msg_data[0]
            parsed = _parse_email(str(uid), raw_email)
            parsed_emails.append(parsed.to_dict())

            if params.mark_as_read:
                await imap.uid("store", str(uid), "+FLAGS", "\\Seen")

            if uid > highest_uid:
                highest_uid = uid

        # Persist new highest UID (no TTL — persistent marker)
        if highest_uid > last_uid:
            await redis.set(redis_key, str(highest_uid))

        return parsed_emails

    finally:
        await imap.logout()


def _parse_email(uid: str, raw: bytes) -> ParsedEmail:
    """Parse a raw RFC822 message into a structured ParsedEmail."""
    msg = email.message_from_bytes(raw)

    def _decode_header(value: str | None) -> str:
        if not value:
            return ""
        parts = email.header.decode_header(value)
        decoded = []
        for part, charset in parts:
            if isinstance(part, bytes):
                decoded.append(part.decode(charset or "utf-8", errors="replace"))
            else:
                decoded.append(part)
        return " ".join(decoded)

    def _parse_address_list(header: str | None) -> list[str]:
        if not header:
            return []
        return [addr.strip() for _, addr in email.utils.getaddresses([header]) if addr]

    body_text = ""
    body_html = ""
    attachments: list[dict[str, Any]] = []

    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            disposition = str(part.get("Content-Disposition", ""))

            if "attachment" in disposition:
                filename = part.get_filename() or "attachment"
                attachments.append(
                    {
                        "filename": _decode_header(filename),
                        "content_type": content_type,
                        "size": len(part.get_payload(decode=True) or b""),
                    }
                )
            elif content_type == "text/plain" and not body_text:
                payload = cast(bytes | None, part.get_payload(decode=True))
                charset = part.get_content_charset() or "utf-8"
                body_text = payload.decode(charset, errors="replace") if payload else ""
            elif content_type == "text/html" and not body_html:
                payload = cast(bytes | None, part.get_payload(decode=True))
                charset = part.get_content_charset() or "utf-8"
                body_html = payload.decode(charset, errors="replace") if payload else ""
    else:
        payload = cast(bytes | None, msg.get_payload(decode=True))
        charset = msg.get_content_charset() or "utf-8"
        body = payload.decode(charset, errors="replace") if payload else ""
        if msg.get_content_type() == "text/html":
            body_html = body
        else:
            body_text = body

    return ParsedEmail(
        uid=uid,
        message_id=msg.get("Message-ID", ""),
        from_=_decode_header(msg.get("From")),
        to=_parse_address_list(msg.get("To")),
        cc=_parse_address_list(msg.get("Cc")),
        subject=_decode_header(msg.get("Subject")),
        body_text=body_text,
        body_html=body_html,
        date=msg.get("Date", ""),
        attachments=attachments,
    )
