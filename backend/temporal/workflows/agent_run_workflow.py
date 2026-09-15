"""Durable autonomous-agent run (reactive multi-step).

Runs an agent's tool-using loop as a Temporal workflow so high-risk tool
dispatches can durably pause for human approval. Determinism contract: ALL
LLM I/O + policy evaluation happen in activities (run_agent_turn /
run_agent_tool_dispatch); the workflow only holds the opaque, provider-shaped
``messages`` array and orchestrates approvals + caps.

Approvals are SEQUENTIAL within a run (the loop waits for each before
continuing), so a single ``_decision`` slot is sufficient — no token keying.

Surfaced to the chassis via:
  - query ``pending`` → the current approval request ({tool, reason}) or None.
  - signal ``approve(decision)`` → "approved" | "rejected".
"""

import json
from dataclasses import dataclass
from datetime import timedelta
from typing import Any

from temporalio import workflow
from temporalio.common import RetryPolicy

with workflow.unsafe.imports_passed_through():
    from temporal.activities.agent_run_status_activity import (
        AgentRunStatusParams,
        report_agent_run_status,
    )
    from temporal.activities.agent_turn_activity import (
        AgentTurnParams,
        ToolDispatchParams,
        run_agent_tool_dispatch,
        run_agent_turn,
    )


DEFAULT_RETRY = RetryPolicy(maximum_attempts=3, initial_interval=timedelta(seconds=2))


@dataclass
class AgentRunParams:
    agent_id: str
    org_id: str  # acting company id
    prompt: str
    run_id: str
    max_steps: int = 25
    approval_timeout_hours: int = 72


@dataclass
class AgentRunResult:
    status: str  # completed | denied | timeout | failed
    content: str = ""
    steps: int = 0


@workflow.defn
class AgentRunWorkflow:
    def __init__(self) -> None:
        self._decision: str | None = None  # "approved" | "rejected"
        self._pending: dict[str, Any] | None = None

    @workflow.signal
    async def approve(self, decision: str) -> None:
        self._decision = decision

    @workflow.query
    def pending(self) -> dict[str, Any] | None:
        return self._pending

    @workflow.run
    async def run(self, params: AgentRunParams) -> AgentRunResult:
        messages: list[dict[str, Any]] = [{"role": "user", "content": params.prompt}]
        pending_results: list[dict[str, Any]] | None = None
        steps = 0

        await self._status(params, "running", steps)

        for _ in range(params.max_steps):
            steps += 1
            turn = await workflow.execute_activity(
                run_agent_turn,
                AgentTurnParams(
                    agent_id=params.agent_id,
                    org_id=params.org_id,
                    messages=messages,
                    tool_results=pending_results,
                ),
                start_to_close_timeout=timedelta(minutes=10),
                retry_policy=DEFAULT_RETRY,
            )
            messages = turn.get("messages", messages)

            if turn.get("status") == "final":
                await self._status(params, "completed", steps)
                return AgentRunResult(
                    status="completed", content=turn.get("content", ""), steps=steps
                )

            pending_results = []
            for call in turn.get("tool_calls", []):
                decision = call.get("decision", "deny")
                if decision == "allow":
                    pending_results.append(await self._dispatch(params, call))
                elif decision == "approval_required":
                    self._pending = {
                        "tool": call.get("name"),
                        "reason": call.get("reason"),
                    }
                    self._decision = None
                    await self._status(params, "awaiting_approval", steps)
                    try:
                        await workflow.wait_condition(
                            lambda: self._decision is not None,
                            timeout=timedelta(hours=params.approval_timeout_hours),
                        )
                    except Exception:
                        self._decision = "timeout"
                    outcome = self._decision
                    self._pending = None
                    await self._status(params, "running", steps)
                    if outcome == "approved":
                        pending_results.append(await self._dispatch(params, call))
                    else:
                        pending_results.append(
                            _synthetic(
                                call,
                                "rejected",
                                "human rejected this action"
                                if outcome == "rejected"
                                else "approval timed out",
                            )
                        )
                        if outcome == "timeout":
                            await self._status(params, "timeout", steps)
                            return AgentRunResult(status="timeout", steps=steps)
                else:  # deny
                    pending_results.append(
                        _synthetic(call, "denied", call.get("reason", "denied"))
                    )

        await self._status(params, "completed", steps)
        return AgentRunResult(
            status="completed", content="(max steps reached)", steps=steps
        )

    async def _dispatch(
        self, params: AgentRunParams, call: dict[str, Any]
    ) -> dict[str, Any]:
        return await workflow.execute_activity(
            run_agent_tool_dispatch,
            ToolDispatchParams(
                agent_id=params.agent_id,
                org_id=params.org_id,
                tool_call_id=call.get("id", ""),
                tool_name=call.get("name", ""),
                tool_input=call.get("input", {}) or {},
            ),
            start_to_close_timeout=timedelta(minutes=5),
            retry_policy=DEFAULT_RETRY,
        )

    async def _status(self, params: AgentRunParams, status: str, steps: int) -> None:
        try:
            await workflow.execute_activity(
                report_agent_run_status,
                AgentRunStatusParams(
                    run_id=params.run_id,
                    agent_id=params.agent_id,
                    acting_company_id=params.org_id,
                    status=status,
                    step_count=steps,
                    temporal_workflow_id=workflow.info().workflow_id,
                ),
                start_to_close_timeout=timedelta(seconds=20),
                retry_policy=DEFAULT_RETRY,
            )
        except Exception:
            # Status reporting is best-effort — never fail the run on it.
            pass


def _synthetic(call: dict[str, Any], status: str, reason: str) -> dict[str, Any]:
    return {
        "tool_call_id": call.get("id", ""),
        "name": call.get("name", ""),
        "content": json.dumps({"status": status, "reason": reason}),
    }
