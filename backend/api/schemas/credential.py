import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel


class CredentialCreate(BaseModel):
    name: str
    type: str  # api_key | oauth2 | basic_auth | cookie_session | smtp | custom
    # The sensitive data — never stored plain, encrypted on create
    secret_data: dict[str, Any]
    # Non-sensitive config (base_url, scopes, etc.)
    metadata: dict[str, Any] = {}


class CredentialResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    name: str
    type: str
    metadata_: dict[str, Any]
    created_at: datetime

    model_config = {"from_attributes": True, "populate_by_name": True}

    def model_post_init(self, __context: Any) -> None:
        # Expose as 'metadata' in JSON output
        pass
