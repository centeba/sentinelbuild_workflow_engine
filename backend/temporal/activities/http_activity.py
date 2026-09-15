"""HTTP request activity — supports REST and GraphQL with credential injection."""

from dataclasses import dataclass, field
from typing import Any

import httpx
from temporalio import activity
from temporalio.exceptions import ApplicationError

from shared.ssrf import SsrfError, guarded_send

_MAX_REDIRECTS = 5


@dataclass
class HttpParams:
    url: str
    method: str = "GET"
    headers: dict[str, str] = field(default_factory=dict)
    body: Any = None
    credential_id: str | None = None
    org_id: str | None = None
    timeout_seconds: int = 30


@activity.defn
async def http_request(params: HttpParams) -> dict[str, Any]:
    headers = dict(params.headers)

    # Inject credential if specified
    if params.credential_id and params.org_id:
        headers = await _inject_credential(headers, params.credential_id, params.org_id)

    # SSRF guard (S3/A3): guarded_send validates the target, connects to the
    # pinned validated IP (closing the TOCTOU / DNS-rebind window), follows
    # redirects manually re-validating + re-pinning each hop, and drops the
    # (possibly credential-bearing) Authorization header on a cross-host hop.
    async with httpx.AsyncClient(
        timeout=params.timeout_seconds, follow_redirects=False
    ) as client:
        try:
            resp = await guarded_send(
                client,
                params.method,
                params.url,
                headers=headers,
                max_redirects=_MAX_REDIRECTS,
                json=params.body if isinstance(params.body, (dict, list)) else None,
                content=params.body if isinstance(params.body, (str, bytes)) else None,
            )
        except SsrfError as exc:
            raise ApplicationError(
                f"Blocked request to {params.url}: {exc}",
                non_retryable=True,
                type="SsrfBlocked",
            )

        # 4xx = caller / config error. Don't retry — surface to the
        # workflow immediately as a non-retryable failure so it can
        # branch or fail-fast. 5xx = remote-server transient; let
        # Temporal's default retry policy handle it.
        if 400 <= resp.status_code < 500:
            raise ApplicationError(
                f"HTTP {resp.status_code} from {params.method} {params.url}: {resp.text[:500]}",
                non_retryable=True,
                type="HttpClientError",
            )
        resp.raise_for_status()

        try:
            data = resp.json()
        except Exception:
            data = resp.text

        return {
            "status_code": resp.status_code,
            "headers": dict(resp.headers),
            "body": data,
        }


async def _inject_credential(
    headers: dict[str, Any], credential_id: str, org_id: str
) -> dict[str, Any]:
    """Load and inject credential into request headers."""
    import uuid

    from sqlalchemy import select

    from api.models.credential import Credential
    from api.services.credential_service import get_secret_data
    from shared.db import AsyncSessionLocal, set_current_org

    # Worker path → stamp the RLS tenant GUC (see credentials RLS migration).
    set_current_org(org_id)
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Credential).where(
                Credential.id == uuid.UUID(credential_id),
                Credential.org_id == uuid.UUID(org_id),
            )
        )
        cred = result.scalar_one_or_none()
        if not cred:
            raise ValueError(f"Credential {credential_id} not found")

        secret = get_secret_data(cred)

        match cred.type:
            case "api_key":
                header_name = cred.metadata_.get("header_name", "Authorization")
                prefix = cred.metadata_.get("prefix", "Bearer")
                headers[header_name] = (
                    f"{prefix} {secret['api_key']}" if prefix else secret["api_key"]
                )
            case "basic_auth":
                import base64

                token = base64.b64encode(
                    f"{secret['username']}:{secret['password']}".encode()
                ).decode()
                headers["Authorization"] = f"Basic {token}"
            case "oauth2":
                headers["Authorization"] = f"Bearer {secret['access_token']}"
            case "custom":
                headers.update(secret.get("headers", {}))

    return headers
