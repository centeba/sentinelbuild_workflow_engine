import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, LargeBinary, String, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from shared.db import Base


class Credential(Base):
    """Stores encrypted credentials (API keys, OAuth tokens, passwords, session cookies)."""

    __tablename__ = "credentials"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    org_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    # api_key | oauth2 | basic_auth | cookie_session | smtp | custom
    type: Mapped[str] = mapped_column(String(50), nullable=False)
    # AES-256-GCM encrypted JSON blob containing the actual secrets
    encrypted_data: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    # Non-sensitive config visible without decryption (e.g. base_url, scopes)
    metadata_: Mapped[dict[str, Any]] = mapped_column(
        "metadata", JSONB, default=dict, server_default="{}"
    )
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    organization: Mapped["Organization"] = relationship(  # type: ignore[name-defined]  # SQLAlchemy cross-module relationship forward-ref; top-level import would cycle, TYPE_CHECKING disallowed
        "Organization", back_populates="credentials", lazy="noload"
    )
