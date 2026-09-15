"""Add scope/visibility/is_mandated/shared_with fields to workflows and forms.

SentinelBuild multi-tenant sharing model:
  scope:       system | company | personal
  visibility:  private | shared | public
  is_mandated: platform/company admin pushed this down to users
  shared_with: JSONB list of org_id/user_id UUIDs
  owner_org_id: NULL for system-scoped items

Revision ID: 0008
Revises: 0007
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB, UUID

from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── workflows ────────────────────────────────────────────────────────────
    op.add_column(
        "workflows",
        sa.Column("scope", sa.String(20), nullable=False, server_default="personal"),
    )
    op.add_column(
        "workflows",
        sa.Column(
            "visibility", sa.String(20), nullable=False, server_default="private"
        ),
    )
    op.add_column(
        "workflows",
        sa.Column("is_mandated", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "workflows",
        sa.Column("shared_with", JSONB(), nullable=False, server_default="[]"),
    )
    op.add_column(
        "workflows",
        sa.Column(
            "owner_org_id",
            UUID(as_uuid=True),
            sa.ForeignKey("organizations.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )

    op.create_index("ix_workflows_scope", "workflows", ["scope"])
    op.create_index("ix_workflows_is_mandated", "workflows", ["is_mandated"])
    op.create_index("ix_workflows_owner_org_id", "workflows", ["owner_org_id"])

    op.create_check_constraint(
        "ck_workflow_scope", "workflows", "scope IN ('system','company','personal')"
    )
    op.create_check_constraint(
        "ck_workflow_visibility",
        "workflows",
        "visibility IN ('private','shared','public')",
    )

    # ── forms ────────────────────────────────────────────────────────────────
    op.add_column(
        "forms",
        sa.Column("scope", sa.String(20), nullable=False, server_default="personal"),
    )
    op.add_column(
        "forms",
        sa.Column(
            "visibility", sa.String(20), nullable=False, server_default="private"
        ),
    )
    op.add_column(
        "forms",
        sa.Column("is_mandated", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "forms", sa.Column("shared_with", JSONB(), nullable=False, server_default="[]")
    )
    op.add_column(
        "forms",
        sa.Column(
            "owner_org_id",
            UUID(as_uuid=True),
            sa.ForeignKey("organizations.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.add_column(
        "forms",
        sa.Column(
            "created_by",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )

    op.create_index("ix_forms_scope", "forms", ["scope"])
    op.create_index("ix_forms_is_mandated", "forms", ["is_mandated"])
    op.create_index("ix_forms_owner_org_id", "forms", ["owner_org_id"])

    op.create_check_constraint(
        "ck_form_scope", "forms", "scope IN ('system','company','personal')"
    )
    op.create_check_constraint(
        "ck_form_visibility", "forms", "visibility IN ('private','shared','public')"
    )


def downgrade() -> None:
    op.drop_constraint("ck_form_visibility", "forms", type_="check")
    op.drop_constraint("ck_form_scope", "forms", type_="check")
    op.drop_index("ix_forms_owner_org_id", "forms")
    op.drop_index("ix_forms_is_mandated", "forms")
    op.drop_index("ix_forms_scope", "forms")
    op.drop_column("forms", "created_by")
    op.drop_column("forms", "owner_org_id")
    op.drop_column("forms", "shared_with")
    op.drop_column("forms", "is_mandated")
    op.drop_column("forms", "visibility")
    op.drop_column("forms", "scope")

    op.drop_constraint("ck_workflow_visibility", "workflows", type_="check")
    op.drop_constraint("ck_workflow_scope", "workflows", type_="check")
    op.drop_index("ix_workflows_owner_org_id", "workflows")
    op.drop_index("ix_workflows_is_mandated", "workflows")
    op.drop_index("ix_workflows_scope", "workflows")
    op.drop_column("workflows", "owner_org_id")
    op.drop_column("workflows", "shared_with")
    op.drop_column("workflows", "is_mandated")
    op.drop_column("workflows", "visibility")
    op.drop_column("workflows", "scope")
