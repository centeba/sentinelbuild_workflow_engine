#!/bin/sh
# Container entrypoint for mit-stack's API. Runs ``alembic upgrade head`` on
# every start so the mit-stack tables (workflows, executions, rules, ...)
# exist before uvicorn binds — mirrors the pack_crm/authz/doc-vault pattern.
# Idempotent. Only used by Dockerfile.api — Dockerfile.worker runs the
# Temporal worker loop and doesn't need to migrate (the API replica does it).
set -e

# Boot-time DB retry: on some platforms (e.g. Railway private networking) the
# database host isn't resolvable/connectable the instant the container starts,
# so a migration that connects immediately fails with "could not translate host
# name" / connection refused and the container crashes. Retry so it self-heals.
_retry_migrate() {
  n=0; max=40
  until "$@"; do
    n=$((n + 1))
    if [ "$n" -ge "$max" ]; then
      echo "[entrypoint] migrate failed after $max attempts" >&2
      exit 1
    fi
    echo "[entrypoint] migrate attempt $n failed (DB not ready?); retry in 3s..."
    sleep 3
  done
}

cd /app
echo "[entrypoint] alembic upgrade head"
_retry_migrate alembic upgrade head
echo "[entrypoint] starting: $*"
exec "$@"
