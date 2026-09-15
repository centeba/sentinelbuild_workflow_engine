"""Mit-Stack read-only view of the shared AI agent tables.

The canonical owner of ``ai_skills`` / ``ai_agent_configs`` /
``ai_agent_skill_links`` is integration-hub (it runs the alembic
migrations that create + seed them, in the ``notifications`` schema).
Mit-Stack binds the same column shapes against its own SQLAlchemy
``Base`` so it can SELECT — and, for the ``agentify_workflows.py``
maintenance script, INSERT — agent rows at runtime.

To resolve the cross-schema reference at query time the database
connection's ``search_path`` must include ``notifications``. In
docker-compose deployments this is set on the postgres role; for
ad-hoc scripts run via ``python -m migrations.agentify_workflows``
remember to ``SET search_path TO workflow, notifications, public;``
on the session.
"""

from __future__ import annotations

from smart_llm.db.models import make_ai_models

from shared.db import Base

_models = make_ai_models(Base)

AISkill = _models["AISkill"]
AIAgentConfig = _models["AIAgentConfig"]
AIAgentSkillLink = _models["AIAgentSkillLink"]

__all__ = ["AIAgentConfig", "AIAgentSkillLink", "AISkill"]
