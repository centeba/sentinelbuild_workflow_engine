import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from shared.db import Base


class Workflow(Base):
    __tablename__ = "workflows"
    __table_args__ = (
        CheckConstraint(
            "scope IN ('system','company','personal')", name="ck_workflow_scope"
        ),
        CheckConstraint(
            "visibility IN ('private','shared','public')", name="ck_workflow_visibility"
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    org_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # Office scoping (NULL = company-shared). Office id lives in user-master;
    # no cross-service FK. NULL artifacts are visible to all offices.
    office_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True, index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    # DAG: {"nodes": [...], "edges": [...]}
    definition: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=dict
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    # webhook | cron | manual | form_submit
    trigger_type: Mapped[str] = mapped_column(
        String(50), nullable=False, default="manual"
    )
    trigger_config: Mapped[dict[str, Any]] = mapped_column(
        JSONB, default=dict, server_default="{}"
    )
    # HMAC secret for webhook verification
    webhook_secret: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    # Points to the currently published version; null means never published
    active_version_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workflow_versions.id", ondelete="SET NULL"),
        nullable=True,
    )

    # ── SentinelBuild scope/visibility fields ─────────────────────────────────
    # scope:      system   → set by system_admin, applies to all orgs
    #             company  → set by company_admin, applies to their org
    #             personal → set by member, private to that user
    scope: Mapped[str] = mapped_column(
        String(20), nullable=False, default="personal", index=True
    )
    # visibility: private  → only the owner/org can see it
    #             shared   → explicitly shared with listed orgs/users
    #             public   → all SentinelBuild users can see/clone it
    visibility: Mapped[str] = mapped_column(
        String(20), nullable=False, default="private"
    )
    # is_mandated: True means system_admin or company_admin has pushed this down
    is_mandated: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, index=True
    )
    # shared_with: list of org_ids (UUIDs) or user_ids that may use this workflow
    shared_with: Mapped[list[Any]] = mapped_column(
        JSONB, nullable=False, default=list, server_default="[]"
    )
    # owner_org_id: NULL for system-scoped workflows (belongs to the platform)
    owner_org_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    # source_app: which vertical app owns this workflow.
    #   NULL          → generic platform workflow (chassis /workflows builder)
    #   "restoration" → restoration domain workflow (restoration admin only)
    # The framework↔domain seam: list_workflows filters authoritatively on
    # this so a domain app's workflows never surface in the generic chassis
    # builder, and vice-versa. Execution is unaffected — this is an
    # ownership/UI tag, the event bus still fans out on trigger_type.
    source_app: Mapped[str | None] = mapped_column(
        String(64), nullable=True, index=True
    )

    # ── A5 cross-company workflow federation ──────────────────────────────────
    # participants: declared companies + their federation role, so a workflow
    # triggered by one company can run actions on another's behalf with
    # governance. Each entry: {"company_id": <uuid>, "role": "owner" |
    # "trigger" | "executor"}. Empty = single-company (legacy) workflow.
    participants: Mapped[list[Any]] = mapped_column(
        JSONB, nullable=False, default=list, server_default="[]"
    )
    # action_authz_rules: per-node cross-company gate. {node_id: {"target_company_id":
    # <uuid>, "authorized_companies": [<uuid>...], "min_relation": "editor"}}. A node
    # that targets another company only dispatches if the executing company is an
    # authorized participant; otherwise the executor denies (skips) it.
    action_authz_rules: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=dict, server_default="{}"
    )

    organization: Mapped["Organization"] = relationship(  # type: ignore[name-defined]  # SQLAlchemy cross-module relationship forward-ref; top-level import would cycle, TYPE_CHECKING disallowed
        "Organization", foreign_keys=[org_id], back_populates="workflows", lazy="noload"
    )
    executions: Mapped[list["WorkflowExecution"]] = relationship(  # type: ignore[name-defined]  # SQLAlchemy cross-module relationship forward-ref; top-level import would cycle, TYPE_CHECKING disallowed
        "WorkflowExecution", back_populates="workflow", lazy="noload"
    )
    active_version: Mapped["WorkflowVersion | None"] = relationship(  # type: ignore[name-defined]  # SQLAlchemy cross-module relationship forward-ref; top-level import would cycle, TYPE_CHECKING disallowed
        "WorkflowVersion", foreign_keys=[active_version_id], lazy="noload"
    )
