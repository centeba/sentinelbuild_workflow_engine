import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, String, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from shared.db import Base


class Organization(Base):
    __tablename__ = "organizations"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    slug: Mapped[str] = mapped_column(
        String(100), unique=True, nullable=False, index=True
    )
    settings: Mapped[dict[str, Any]] = mapped_column(
        JSONB, default=dict, server_default="{}"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    # Relationships
    users: Mapped[list["User"]] = relationship(  # type: ignore[name-defined]  # SQLAlchemy cross-module relationship forward-ref; top-level import would cycle, TYPE_CHECKING disallowed
        "User", back_populates="organization", lazy="noload"
    )
    workflows: Mapped[list["Workflow"]] = relationship(  # type: ignore[name-defined]  # SQLAlchemy cross-module relationship forward-ref; top-level import would cycle, TYPE_CHECKING disallowed
        "Workflow",
        foreign_keys="[Workflow.org_id]",
        back_populates="organization",
        lazy="noload",
    )
    credentials: Mapped[list["Credential"]] = relationship(  # type: ignore[name-defined]  # SQLAlchemy cross-module relationship forward-ref; top-level import would cycle, TYPE_CHECKING disallowed
        "Credential", back_populates="organization", lazy="noload"
    )
