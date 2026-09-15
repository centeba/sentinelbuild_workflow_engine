"""Database query activity — execute SQL against configured DB credentials."""

import ipaddress
import socket
from dataclasses import dataclass, field
from typing import Any
from urllib.parse import urlparse

from temporalio import activity
from temporalio.exceptions import ApplicationError


@dataclass
class DbQueryParams:
    sql: str
    params: list[Any] = field(default_factory=list)
    credential_id: str | None = None
    org_id: str | None = None


_PLATFORM_DB_ALIASES = {"localhost", "127.0.0.1", "::1", "postgres"}


def _validate_db_dsn(dsn: str) -> None:
    """S5 — block a db_query credential from targeting the platform database.

    The DSN is author-supplied (stored in a credential), so without a check a
    workflow could point it at the shared platform DB. Block the platform DB
    host (from settings.database_url, by name and resolved IP) plus loopback /
    link-local targets. An optional ``DB_QUERY_ALLOWED_HOSTS`` env (comma list)
    turns this into a strict allow-list for locked-down deployments.
    """
    import os

    from shared.config import get_settings

    host = (urlparse(dsn).hostname or "").lower()
    if not host:
        raise ApplicationError("db_query credential has no host", non_retryable=True)

    allow = [
        h.strip().lower()
        for h in os.environ.get("DB_QUERY_ALLOWED_HOSTS", "").split(",")
        if h.strip()
    ]
    if allow:
        if host not in allow:
            raise ApplicationError(
                f"db_query host {host!r} not in DB_QUERY_ALLOWED_HOSTS",
                non_retryable=True,
            )
        return

    plat_host = (urlparse(get_settings().database_url).hostname or "").lower()
    if host in _PLATFORM_DB_ALIASES or (plat_host and host == plat_host):
        raise ApplicationError(
            "db_query may not target the platform database", non_retryable=True
        )

    # Resolve and reject loopback / link-local (also catches the platform DB
    # reached via an internal alias / its private IP).
    def _ips(h: str) -> list[ipaddress.IPv4Address | ipaddress.IPv6Address]:
        try:
            return [ipaddress.ip_address(h)]
        except ValueError:
            try:
                infos = socket.getaddrinfo(h, None, proto=socket.IPPROTO_TCP)
            except socket.gaierror:
                return []
            return [ipaddress.ip_address(str(i[4][0]).split("%")[0]) for i in infos]

    plat_ips = set(_ips(plat_host)) if plat_host else set()
    for ip in _ips(host):
        if ip.is_loopback or ip.is_link_local or ip in plat_ips:
            raise ApplicationError(
                f"db_query target host {host!r} is the platform DB or a "
                "loopback/internal address",
                non_retryable=True,
            )


@activity.defn
async def run_db_query(params: DbQueryParams) -> dict[str, Any]:
    if not params.credential_id or not params.org_id:
        raise ValueError("DB credential_id and org_id are required")

    # S5 — dynamic values must arrive as bound params, never substituted into
    # the SQL string. The executor no longer interpolates config["sql"]; reject
    # any templated SQL defensively in case another caller does.
    if "{{" in (params.sql or ""):
        raise ApplicationError(
            "db_query SQL must not contain {{...}} — pass dynamic values via "
            "bound params ($1, $2, …)",
            non_retryable=True,
        )

    import uuid

    from sqlalchemy import select

    from api.models.credential import Credential
    from api.services.credential_service import get_secret_data
    from shared.db import AsyncSessionLocal, set_current_org

    # Worker path → stamp the RLS tenant GUC (see credentials RLS migration).
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
            raise ValueError(f"DB credential {params.credential_id} not found")
        secret = get_secret_data(cred)

    # Connect to target database (S5 — never the platform DB / loopback)
    import asyncpg

    _validate_db_dsn(secret["connection_string"])
    conn = await asyncpg.connect(secret["connection_string"])
    try:
        rows = await conn.fetch(params.sql, *params.params)
        records = [dict(row) for row in rows]
    finally:
        await conn.close()

    return {"rows": records, "count": len(records)}
