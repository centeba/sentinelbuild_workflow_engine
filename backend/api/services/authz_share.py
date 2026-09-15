"""Cross-company workflow sharing → OpenFGA grants (Phase 2c).

mit-stack keeps writing the legacy ``workflows.shared_with`` JSONB list (so the
existing list/enforcement keeps working) AND mirrors each share into the authz
service as an OpenFGA tuple. Best-effort: authz failures are logged but don't
fail the share, because the legacy list is the fallback during the dual-read
window.
"""

import uuid

import httpx
import structlog

from shared._platform.authz import authz_check as _sdk_authz_check
from shared._platform.config import SentinelBuildSettings
from shared.config import get_settings

log = structlog.get_logger(__name__)


def _settings() -> SentinelBuildSettings:
    return SentinelBuildSettings(
        internal_api_key=(get_settings().internal_api_key or "")
    )


async def _grants(method: str, body: dict[str, str]) -> None:
    s = _settings()
    url = f"{s.authz_url.rstrip('/')}/api/v1/grants"
    try:
        async with httpx.AsyncClient(timeout=s.request_timeout_seconds) as c:
            r = await c.request(
                method, url, json=body, headers={"X-Internal-Key": s.internal_api_key}
            )
        if r.status_code not in (200, 201, 404, 409):
            log.warning(
                "authz_workflow_grant_failed",
                method=method,
                status=r.status_code,
                body=r.text[:200],
            )
    except Exception:  # noqa: BLE001
        log.warning("authz_workflow_grant_error", method=method, exc_info=True)


async def write_workflow_share(
    workflow_id: uuid.UUID | str,
    *,
    owner_org_id: uuid.UUID | str,
    grantee_company_id: uuid.UUID | str,
) -> None:
    """Ensure the workflow's owner tuple + a viewer grant for the grantee company."""
    obj = f"workflow:{workflow_id}"
    await _grants(
        "POST", {"user": f"company:{owner_org_id}", "relation": "owner", "object": obj}
    )
    await _grants(
        "POST",
        {
            "user": f"company:{grantee_company_id}#member",
            "relation": "viewer",
            "object": obj,
        },
    )


async def delete_workflow_share(
    workflow_id: uuid.UUID | str, *, grantee_company_id: uuid.UUID | str
) -> None:
    await _grants(
        "DELETE",
        {
            "user": f"company:{grantee_company_id}#member",
            "relation": "viewer",
            "object": f"workflow:{workflow_id}",
        },
    )


async def authz_can_view_workflow(
    *, user_id: uuid.UUID | str, workflow_id: uuid.UUID | str
) -> bool:
    """Dual-read probe (fail-closed). Resolves once user→company membership
    tuples exist in OpenFGA; until then the legacy shared_with list is the
    authoritative cross-company path."""
    allowed: bool = await _sdk_authz_check(
        f"user:{user_id}",
        "viewer",
        f"workflow:{workflow_id}",
        settings=_settings(),
    )
    return allowed
