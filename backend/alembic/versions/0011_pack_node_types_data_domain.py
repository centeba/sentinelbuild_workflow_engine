"""Widen pack_node_types.kind CHECK to allow 'data_domain'.

Packs now contribute a `data_domain` kind (the no-code condition builder's
domain-data schema) alongside trigger/action/group/theme. Drop and recreate the
CHECK constraint to include it.

Revision ID: 0011
Revises: 0010
"""

from alembic import op

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None

_OLD = "kind IN ('trigger','action','group','theme')"
_NEW = "kind IN ('trigger','action','group','theme','data_domain')"
_NAME = "ck_pack_node_types_kind"


def upgrade() -> None:
    op.drop_constraint(_NAME, "pack_node_types", type_="check")
    op.create_check_constraint(_NAME, "pack_node_types", _NEW)


def downgrade() -> None:
    op.drop_constraint(_NAME, "pack_node_types", type_="check")
    op.create_check_constraint(_NAME, "pack_node_types", _OLD)
