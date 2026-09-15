"""Postgres Row-Level Security tenant isolation for mit-stack (A2).

Proves the exact predicate migration 0016 installs on the org-private integration
tables (``credentials`` / ``integrations`` / ``scraper_sessions``):
``org_id = NULLIF(current_setting('app.current_org', true), '')::uuid``.

RLS only applies on real Postgres and only a NON-superuser role feels FORCE RLS,
so this builds a throwaway schema + non-superuser role and checks, as that role:
a query with no org_id predicate sees only the current tenant's rows; switching
the GUC switches rows; an unset tenant sees ZERO rows (fail-closed); and WITH
CHECK blocks writing another tenant's row.

Set ``RLS_TEST_DATABASE_URL`` to a superuser DSN (``postgresql://…``) to run.
"""

import os
import uuid

import pytest

DSN = os.environ.get("RLS_TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not DSN, reason="RLS_TEST_DATABASE_URL not set")

_PRED = "org_id = NULLIF(current_setting('app.current_org', true), '')::uuid"


async def _setup(admin) -> tuple[uuid.UUID, uuid.UUID]:
    await admin.execute("DROP SCHEMA IF EXISTS rls_poc CASCADE")
    await admin.execute("DROP ROLE IF EXISTS rls_app")
    await admin.execute("CREATE SCHEMA rls_poc")
    # Shaped like ``credentials``: an org-scoped secret store.
    await admin.execute(
        "CREATE TABLE rls_poc.credentials ("
        "id uuid PRIMARY KEY DEFAULT gen_random_uuid(), "
        "org_id uuid NOT NULL, name text)"
    )
    await admin.execute("ALTER TABLE rls_poc.credentials ENABLE ROW LEVEL SECURITY")
    await admin.execute("ALTER TABLE rls_poc.credentials FORCE ROW LEVEL SECURITY")
    await admin.execute(
        f"CREATE POLICY tenant_isolation ON rls_poc.credentials "
        f"USING ({_PRED}) WITH CHECK ({_PRED})"
    )
    await admin.execute(
        "CREATE ROLE rls_app LOGIN PASSWORD 'apppw' NOSUPERUSER NOBYPASSRLS"
    )
    await admin.execute("GRANT USAGE ON SCHEMA rls_poc TO rls_app")
    await admin.execute(
        "GRANT SELECT, INSERT, UPDATE, DELETE ON rls_poc.credentials TO rls_app"
    )
    org_a, org_b = uuid.uuid4(), uuid.uuid4()
    await admin.execute(
        "INSERT INTO rls_poc.credentials (org_id, name) "
        "VALUES ($1,'a-1'),($1,'a-2'),($2,'b-1')",
        org_a,
        org_b,
    )
    return org_a, org_b


@pytest.mark.asyncio
async def test_rls_isolation_failclosed_and_with_check():
    import asyncpg

    admin = await asyncpg.connect(DSN)
    try:
        org_a, org_b = await _setup(admin)
    finally:
        await admin.close()

    app = await asyncpg.connect(dsn=DSN, user="rls_app", password="apppw")
    try:

        async def visible():
            return {
                r["name"]
                for r in await app.fetch("SELECT name FROM rls_poc.credentials")
            }

        await app.execute("SELECT set_config('app.current_org', $1, false)", str(org_a))
        assert await visible() == {"a-1", "a-2"}

        await app.execute("SELECT set_config('app.current_org', $1, false)", str(org_b))
        assert await visible() == {"b-1"}

        await app.execute("SELECT set_config('app.current_org', '', false)")
        assert await visible() == set()  # fail-closed

        await app.execute("SELECT set_config('app.current_org', $1, false)", str(org_a))
        with pytest.raises(asyncpg.exceptions.InsufficientPrivilegeError):
            await app.execute(
                "INSERT INTO rls_poc.credentials (org_id, name) VALUES ($1,'evil')",
                org_b,
            )
    finally:
        await app.close()
        admin = await asyncpg.connect(DSN)
        try:
            await admin.execute("DROP SCHEMA IF EXISTS rls_poc CASCADE")
            await admin.execute("DROP ROLE IF EXISTS rls_app")
        finally:
            await admin.close()
