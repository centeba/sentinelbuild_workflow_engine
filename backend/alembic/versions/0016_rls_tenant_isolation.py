"""RLS tenant isolation for mit-stack integration secrets (HARDENING-PLAN A2)

Enable FORCE RLS + a ``tenant_isolation`` policy on mit-stack's tenant-private
integration tables, keyed on the per-transaction GUC ``app.current_org`` (stamped
by ``shared/db.py``'s engine ``begin`` listener from the verified JWT ``org_id``,
and by the Temporal worker activities that read these tables). Fail-closed: an
unstamped session sees zero rows.

Scope — the clearly org-PRIVATE tables (default ``public`` schema, ``org_id``
NOT NULL, no sharing):
``credentials`` (encrypted integration secrets — the crown jewels),
``integrations``, ``scraper_sessions``.

Deliberately EXCLUDED this pass (each needs its own design, mirroring
user-master's decision to keep sharing/bootstrap working):
- ``workflows`` / ``workflow_executions`` / ``workflow_versions`` /
  ``node_executions`` — designed cross-company **federation** (scope=system,
  visibility=public, ``shared_with``, ``participants``, ``action_authz_rules``);
  a naive ``org_id`` row policy would break legitimate cross-company access.
  App-level authz is the control there.
- ``users`` — the **auth bootstrap** queries it (login-by-email, identity-sync,
  ``get_current_user``) BEFORE any org is known; RLS would need a bypass GUC.
- ``rules`` / rule_* — a **global rule cache** (``api/services/rule_cache.py``)
  loads every org's rules; RLS would starve it. Needs a per-org cache or bypass.
- ``organizations`` (tenant root), ``pack_node_types`` (global catalog), and the
  shared AI tables (owned by integration-hub).

Operator: the app runtime must connect as a NON-superuser role without BYPASSRLS
(``sentinel_app``); migrations run as the owner via ``migration_db_url``
(``MIGRATION_DB_USER``). Dark until that role is deployed.

Revision ID: 0016_rls_tenant_isolation
Revises: 0015_drop_forms
Create Date: 2026-08-24
"""

from alembic import op

revision = "0016_rls_tenant_isolation"
down_revision = "0015_drop_forms"
branch_labels = None
depends_on = None

# Org-private tables (default ``public`` schema — mit-stack does not schema-qualify;
# all carry NOT NULL ``org_id`` and no sharing/federation fields).
_TABLES = ["credentials", "integrations", "scraper_sessions"]

# Empty GUC → NULL → no row matches (fail-closed, no bad-uuid cast error).
_PRED = "org_id = NULLIF(current_setting('app.current_org', true), '')::uuid"


def upgrade() -> None:
    for t in _TABLES:
        op.execute(f"ALTER TABLE {t} ENABLE ROW LEVEL SECURITY")
        op.execute(f"ALTER TABLE {t} FORCE ROW LEVEL SECURITY")
        op.execute(
            f"CREATE POLICY tenant_isolation ON {t} "
            f"USING ({_PRED}) WITH CHECK ({_PRED})"
        )


def downgrade() -> None:
    for t in _TABLES:
        op.execute(f"DROP POLICY IF EXISTS tenant_isolation ON {t}")
        op.execute(f"ALTER TABLE {t} NO FORCE ROW LEVEL SECURITY")
        op.execute(f"ALTER TABLE {t} DISABLE ROW LEVEL SECURITY")
