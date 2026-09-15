"""drop forms + form_submissions (form builder retired)

Revision ID: 0015_drop_forms
Revises: 0014
Create Date: 2026-06-29

The standalone form builder was retired — forms are authored as pages in the Web
Builder (pages-api), which owns form storage + submission. The mit-stack Form /
FormSubmission tables are dropped (verified empty at retirement — 0 rows). The
generic ``form_submit`` rule-trigger event constant is retained.
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB, UUID

from alembic import op

revision = "0015_drop_forms"
down_revision = "0014"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # form_submissions FKs into forms (CASCADE) — drop it first.
    op.drop_table("form_submissions")
    op.drop_table("forms")


def downgrade() -> None:
    op.create_table(
        "forms",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("org_id", UUID(as_uuid=True), nullable=False, index=True),
        sa.Column("office_id", UUID(as_uuid=True), nullable=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("slug", sa.String(255), nullable=True),
        sa.Column("definition", JSONB, nullable=False, server_default="{}"),
        sa.Column("is_public", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("scope", sa.String(20), nullable=True),
        sa.Column("visibility", sa.String(20), nullable=True),
        sa.Column("is_mandated", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("shared_with", JSONB, nullable=True),
        sa.Column("owner_org_id", UUID(as_uuid=True), nullable=True),
        sa.Column("created_by", UUID(as_uuid=True), nullable=True),
        sa.Column("workflow_id", UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now()
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()
        ),
    )
    op.create_table(
        "form_submissions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "form_id",
            UUID(as_uuid=True),
            sa.ForeignKey("forms.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("org_id", UUID(as_uuid=True), nullable=False),
        sa.Column("data", JSONB, nullable=False, server_default="{}"),
        sa.Column("execution_id", UUID(as_uuid=True), nullable=True),
        sa.Column("submitted_by_ip", sa.String(64), nullable=True),
        sa.Column(
            "submitted_at", sa.DateTime(timezone=True), server_default=sa.func.now()
        ),
    )
