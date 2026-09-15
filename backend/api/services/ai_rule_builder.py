"""AI Rule Builder (Phase D / Gap 10).

Converts a plain-English description into a valid Mit Stack rule JSON
using the seeded ``rule_builder`` :class:`AIAgentConfig`.

The agent row holds the system prompt, provider, and model. API keys are
resolved through :class:`KeyManager` keyed on the organisation — no
``ANTHROPIC_API_KEY`` env var required.

If the seeded agent is not found or has no key, the function raises a
descriptive ``ValueError`` so the route returns a 503 instead of a 500.

The legacy AgentManager / env-var fallback path is intentionally removed:
if you need the AI rule builder, seed the ``rule_builder`` agent via the
AI Admin UI and register an LLM key for the organisation.
"""

import logging
import os
import uuid
from typing import TYPE_CHECKING, Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

if TYPE_CHECKING:
    # Type-only import. At runtime this module intentionally imports
    # AIAgentConfig locally inside _load_agent_config, because it pulls in
    # smart_llm.db.models (make_ai_models) — a heavy dependency this module
    # keeps off its import path (smart_llm is deferred everywhere here).
    from api.models.ai_agent import AIAgentConfig

log = logging.getLogger(__name__)

RULE_BUILDER_AGENT_NAME = "rule_builder"

# Kept as a module-level fallback for cases where the seeded agent has no
# system_prompt set yet (empty string in DB). Callers can rely on the
# agent row's prompt once the seed migration runs.
_FALLBACK_SYSTEM_PROMPT = """\
You are a rule-engine configuration assistant for the Mit Stack platform.
The user will describe a business rule in plain English. Your job is to
output ONLY a valid JSON object (no markdown, no explanation) that conforms
to the Mit Stack RuleCreate schema.

Schema:
{
  "name": string,
  "description": string | null,
  "priority": integer (1–999, lower = evaluated first, default 100),
  "is_active": true,
  "status": "draft",           // always draft for AI-generated rules
  "stop_on_match": boolean,
  "rule_type": "condition_tree" | "decision_table",
  "trigger_events": array of one or more: ["form_submit","workflow_complete","workflow_fail","webhook","schedule","manual"],
  "trigger_filter": object (key/value pairs that must exist in event data, or {}),
  "conditions": {
    "combinator": "and" | "or" | "not",
    "rules": [
      { "field": "dot.path", "operator": "<op>", "value": "<val>" },
      ...nested groups allowed...
    ]
  },
  "actions": [
    { "type": "trigger_workflow", "workflow_id": "uuid" },
    { "type": "send_email", "to": "{{field}}", "subject": "...", "body": "..." },
    { "type": "send_webhook", "url": "https://...", "method": "POST" },
    { "type": "set_field", "field": "dot.path", "value": "..." },
    { "type": "add_tag", "tag": "..." },
    { "type": "stop_processing" }
  ],
  "else_actions": []  // actions when conditions do NOT match
}

Available condition operators:
  eq, neq, contains, not_contains, starts_with, ends_with,
  gt, gte, lt, lte, in (value="a,b,c"), not_in, between (value="min,max"),
  is_empty, is_not_empty, matches_regex, is_true, is_false,
  date_before, date_after, date_equals, within_last_n_days (value=N), older_than_n_days (value=N)

For decision_table rule_type, use this structure in "conditions":
{
  "input_columns":  [{"field": "dot.path", "label": "Human label"}],
  "output_columns": [{"field": "dot.path", "label": "Human label"}],
  "rows": [
    {"id": "r1", "conditions": [{"operator": "eq", "value": "gold"}],
                 "outputs":    [{"value": "20"}], "annotation": "Gold tier"},
    {"id": "r2", "conditions": [{"operator": "ANY"}],
                 "outputs":    [{"value": "0"}],  "annotation": "Default"}
  ]
}
In this case "actions" and "else_actions" should be [].

Rules:
- Output ONLY the JSON object, no markdown fences, no extra text.
- Use "draft" status always.
- Field paths use dot notation: data.email, data.score, etc.
- Use {{field.path}} or {{field * 0.9}} in action values for interpolation.
- If the description mentions a decision table / matrix / grid, use rule_type=decision_table.
- If uncertain about specifics, make a sensible default and leave a note in description.
"""


async def generate_rule(
    description: str,
    event_type: str,
    *,
    org_id: uuid.UUID | None = None,
    db: AsyncSession | None = None,
) -> dict[str, Any]:
    """Call the seeded ``rule_builder`` LLM agent and return a rule dict.

    Args:
        description: Plain-English description of the rule to generate.
        event_type:  Trigger event (e.g. ``"form_submit"``).
        org_id:      Organisation UUID — used to look up the seeded agent
                     and its API key.  Required; raises ``ValueError`` if
                     absent.
        db:          Active SQLAlchemy session for the agent-config lookup.

    Returns:
        A dict compatible with ``RuleCreate``.

    Raises:
        ``ValueError`` when the agent is not seeded, has no key, or the
        LLM does not return valid JSON.
    """
    from smart_llm import Agent

    if org_id is None or db is None:
        raise ValueError(
            "org_id and db are required to load the seeded rule_builder agent. "
            "Ensure the caller passes current.org_id and a DB session."
        )

    cfg = await _load_agent_config(db, org_id)
    if cfg is None:
        raise ValueError(
            f"No active '{RULE_BUILDER_AGENT_NAME}' AIAgentConfig seeded for org {org_id}. "
            "Create the agent via the AI Admin UI (Settings → Agents) and set it active."
        )

    api_key = await _resolve_key(cfg.provider_type, org_id)
    if not api_key:
        raise ValueError(
            f"No {cfg.provider_type} API key registered for org {org_id}. "
            "Add a key via Settings → LLM Keys."
        )

    user_message = (
        f"Create a Mit Stack rule for the following:\n\n"
        f"Event type: {event_type}\n\n"
        f"Description: {description}"
    )

    from smart_llm.provider_policy import resolve_agent_provider

    _ptype, _model = resolve_agent_provider(
        cfg.provider_type, cfg.model_name, cfg.model_configuration
    )
    agent = Agent(
        name=cfg.name,
        provider_type=_ptype,
        system_prompt=cfg.system_prompt or _FALLBACK_SYSTEM_PROMPT,
        api_key=api_key,
        model_name=_model,
    )
    response = await agent.analyze(user_message)
    rule_dict: dict[str, Any] = response.data  # already parsed JSON dict

    # Enforce safe defaults
    rule_dict.setdefault("status", "draft")
    rule_dict.setdefault("is_active", True)
    rule_dict.setdefault("trigger_events", [event_type])
    rule_dict.setdefault("trigger_filter", {})
    rule_dict.setdefault("conditions", {})
    rule_dict.setdefault("actions", [])
    rule_dict.setdefault("else_actions", [])
    rule_dict.setdefault("rule_type", "condition_tree")

    return rule_dict


async def _load_agent_config(
    db: AsyncSession, org_id: uuid.UUID
) -> "AIAgentConfig | None":
    """Load the active rule_builder AIAgentConfig for the given org."""
    # Local import — mit-stack has its own AI models module.
    from api.models.ai_agent import AIAgentConfig

    return (
        await db.execute(
            select(AIAgentConfig)
            .where(
                AIAgentConfig.company_id == org_id,
                AIAgentConfig.name == RULE_BUILDER_AGENT_NAME,
                AIAgentConfig.is_active.is_(True),
            )
            .limit(1)
        )
    ).scalar_one_or_none()


async def _resolve_key(provider: str, org_id: uuid.UUID) -> str | None:
    enc = os.getenv("LLM_KEY_ENCRYPTION_KEY")
    if not enc:
        return None
    from smart_llm.key_manager import KeyManager
    from smart_llm.key_store import DatabaseKeyStore

    from shared.db import engine as async_engine

    store = DatabaseKeyStore(engine=async_engine, encryption_key=enc)
    km = KeyManager(key_store=store)
    await km.load_from_store(provider, org_id)
    key: str | None = km.get_key(provider)
    return key
