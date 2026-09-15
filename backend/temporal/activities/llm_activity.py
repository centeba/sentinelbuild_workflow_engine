"""LLM activity — runs LLM calls inside Temporal workflows via smart-llm.

Replaces the Integration Hub delegate for claude_llm workflow nodes.
Supports Anthropic (default), OpenAI, and Gemini providers.
The credential must be of type "api_key" with secret data {"api_key": "sk-..."}.
"""

import uuid
from dataclasses import dataclass
from typing import Any, cast

from smart_llm import Agent, AgentManager
from temporalio import activity

_DEFAULT_SYSTEM_PROMPT = (
    "You are a helpful AI assistant integrated into a workflow automation platform. "
    "Always respond with a valid JSON object. "
    'If your answer is plain text, wrap it as: {"content": "your text here"}. '
    "Never include any text outside the JSON object."
)


@dataclass
class LLMParams:
    credential_id: str  # Credential DB id containing the API key
    org_id: str  # Org scope for credential lookup
    prompt: str  # User prompt (interpolated by caller)
    system_prompt: str = ""  # Override system prompt; default enforces JSON output
    model: str = "claude-sonnet-4-6"
    provider_type: str = "anthropic"  # "anthropic" | "openai" | "gemini"
    max_tokens: int = 1024


@activity.defn
async def run_llm(params: LLMParams) -> dict[str, Any]:
    """Execute an LLM call using smart-llm and return the parsed JSON response."""
    api_key = await _get_api_key(params.credential_id, params.org_id)
    sys_prompt = params.system_prompt or _DEFAULT_SYSTEM_PROMPT

    agent = Agent(
        name="workflow_llm",
        provider_type=params.provider_type,
        system_prompt=sys_prompt,
        api_key=api_key,
        model_name=params.model,
    )
    manager = AgentManager()
    manager.register_agent(agent)

    response = await manager.analyze(params.prompt)
    return cast(dict[str, Any], response.data)


async def _get_api_key(credential_id: str, org_id: str) -> str:
    """Look up and decrypt the API key from the credentials table."""
    from sqlalchemy import select

    from api.models.credential import Credential
    from api.services.credential_service import get_secret_data
    from shared.db import AsyncSessionLocal, set_current_org

    # Worker path → stamp the RLS tenant GUC (see credentials RLS migration).
    set_current_org(org_id)
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Credential).where(
                Credential.id == uuid.UUID(credential_id),
                Credential.org_id == uuid.UUID(org_id),
            )
        )
        cred = result.scalar_one_or_none()
        if not cred:
            raise ValueError(f"Credential {credential_id} not found for org {org_id}")

        secret = get_secret_data(cred)
        api_key = secret.get("api_key")
        if not api_key:
            raise ValueError(
                f"Credential {credential_id} has no 'api_key' field in secret data"
            )
        return cast(str, api_key)
