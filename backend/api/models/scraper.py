import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, LargeBinary, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from shared.db import Base


class ScraperSession(Base):
    """Stores browser sessions for authenticated scraping."""

    __tablename__ = "scraper_sessions"

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
    # Base URL of the site
    base_url: Mapped[str] = mapped_column(Text, nullable=False)
    # Login URL for auto-login with stored credentials
    login_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    # credential_id pointing to basic_auth or custom credentials for auto-login
    credential_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("credentials.id", ondelete="SET NULL"),
        nullable=True,
    )
    # AES-256-GCM encrypted Playwright storage_state JSON (cookies + localStorage)
    session_data: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    # Playwright login script config: {"username_selector": "...", "password_selector": "...", "submit_selector": "..."}
    login_config: Mapped[dict[str, Any]] = mapped_column(
        JSONB, default=dict, server_default="{}"
    )
    last_used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_refreshed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
