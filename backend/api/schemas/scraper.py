import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel


class ScraperSessionCreate(BaseModel):
    name: str
    base_url: str
    login_url: str | None = None
    credential_id: uuid.UUID | None = None
    login_config: dict[str, Any] = {}


class ScraperSessionResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    name: str
    base_url: str
    login_url: str | None
    credential_id: uuid.UUID | None
    login_config: dict[str, Any]
    last_used_at: datetime | None
    last_refreshed_at: datetime | None
    created_at: datetime

    model_config = {"from_attributes": True}


class ScrapeRequest(BaseModel):
    """Ad-hoc scrape request for testing."""

    url: str
    selectors: list[dict[str, str]] = []  # [{"name": "price", "css": ".price"}]
    actions: list[dict[str, Any]] = []  # [{"type": "click", "selector": "#btn"}]
    session_id: uuid.UUID | None = None


class ConnectorConnectRequest(BaseModel):
    """Per-tenant onboarding for a pack-contributed scraper connector.

    ``secrets`` provides the values the connector's ``secret_fields`` declares
    (e.g. company_id, username, password, totp_secret). Tenant-identifier
    secrets mapped by the template's ``tenant_field`` (e.g. company_id) are
    written into the session's login fields; the rest are encrypted in a new
    credential. No template/site knowledge is sent by the client.
    """

    secrets: dict[str, Any]
    name: str | None = None
    # Auto-create a manual web_scraper workflow per connector target (source_app
    # = the pack), so the tenant can run each scrape without building it by hand.
    materialize_targets: bool = True
