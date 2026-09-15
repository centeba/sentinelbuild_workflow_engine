"""workflow federation — participants + per-node cross-company authz rules (A5)

Revision ID: 0014
Revises: 0013
Create Date: 2026-06-28

Adds two JSONB columns to ``workflows`` so a workflow triggered by one company
can run actions on another's behalf with governance: ``participants`` declares
the federation members + roles; ``action_authz_rules`` gates per-node
cross-company action dispatch. Both default empty (single-company workflows
unaffected).
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

from alembic import op

revision = "0014"
down_revision = "0013"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "workflows",
        sa.Column("participants", JSONB, nullable=False, server_default="[]"),
    )
    op.add_column(
        "workflows",
        sa.Column("action_authz_rules", JSONB, nullable=False, server_default="{}"),
    )


def downgrade() -> None:
    op.drop_column("workflows", "action_authz_rules")
    op.drop_column("workflows", "participants")
