"""Add ``workflows.source_app`` — the framework/domain ownership tag.

NULL          → generic platform workflow (chassis /workflows builder)
"restoration" → restoration domain workflow (restoration admin surface)

``list_workflows`` filters authoritatively on this column so a vertical
app's workflows never leak into the generic chassis builder, and
vice-versa. Existing rows stay NULL → remain platform workflows.

Idempotent — uses information_schema like the surrounding migrations so
re-running against an already-upgraded DB is a no-op.

Revision ID: 0010
Revises: 0009
"""

from alembic import op

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'workflows'
                   AND column_name = 'source_app'
            ) THEN
                ALTER TABLE workflows ADD COLUMN source_app VARCHAR(64) NULL;
                CREATE INDEX IF NOT EXISTS ix_workflows_source_app
                  ON workflows (source_app);
            END IF;
        END$$;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX IF EXISTS ix_workflows_source_app;
        ALTER TABLE workflows DROP COLUMN IF EXISTS source_app;
        """
    )
