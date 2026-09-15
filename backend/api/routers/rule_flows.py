"""
Rule Flows router — Gap 12: visual rule chaining.

A RuleFlow is an ordered pipeline of rules evaluated in sequence.
Each step's set_field output (when pass_output=True) is merged into
the shared event_data before the next step runs.
"""

import time
import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from api.deps import CurrentUser, get_current_user
from api.models.rule import Rule
from api.models.rule_flow import RuleFlow, RuleFlowStep
from api.schemas.rule import (
    RuleFlowCreate,
    RuleFlowExecuteRequest,
    RuleFlowExecuteResponse,
    RuleFlowResponse,
    RuleFlowStepCreate,
    RuleFlowStepResponse,
    RuleFlowUpdate,
)
from api.services.rule_engine import process_event
from shared.db import get_db

router = APIRouter(prefix="/rule-flows", tags=["rule-flows"])


# ─── Helpers ──────────────────────────────────────────────────────────────────


async def _get_flow_or_404(
    db: AsyncSession, flow_id: uuid.UUID, org_id: uuid.UUID
) -> RuleFlow:
    res = await db.execute(
        select(RuleFlow).where(RuleFlow.id == flow_id, RuleFlow.org_id == org_id)
    )
    flow = res.scalar_one_or_none()
    if not flow:
        raise HTTPException(status_code=404, detail="Rule flow not found")
    return flow


async def _load_steps(db: AsyncSession, flow_id: uuid.UUID) -> list[RuleFlowStep]:
    res = await db.execute(
        select(RuleFlowStep)
        .where(RuleFlowStep.flow_id == flow_id)
        .order_by(RuleFlowStep.step_order.asc())
    )
    return list(res.scalars().all())


async def _sync_steps(
    db: AsyncSession, flow_id: uuid.UUID, steps_in: list[RuleFlowStepCreate]
) -> None:
    """Replace all steps for a flow with the provided list."""
    await db.execute(delete(RuleFlowStep).where(RuleFlowStep.flow_id == flow_id))
    for i, s in enumerate(steps_in):
        db.add(
            RuleFlowStep(
                flow_id=flow_id,
                rule_id=s.rule_id,
                step_order=s.step_order if s.step_order != 0 else i,
                pass_output=s.pass_output,
                label=s.label,
            )
        )


def _flow_response(flow: RuleFlow, steps: list[RuleFlowStep]) -> RuleFlowResponse:
    return RuleFlowResponse(
        id=flow.id,
        org_id=flow.org_id,
        name=flow.name,
        description=flow.description,
        is_active=flow.is_active,
        trigger_events=flow.trigger_events,
        steps=[
            RuleFlowStepResponse(
                id=s.id,
                flow_id=s.flow_id,
                rule_id=s.rule_id,
                step_order=s.step_order,
                pass_output=s.pass_output,
                label=s.label,
            )
            for s in steps
        ],
        created_at=flow.created_at,
        updated_at=flow.updated_at,
    )


# ─── CRUD ─────────────────────────────────────────────────────────────────────


@router.get("", response_model=list[RuleFlowResponse])
async def list_flows(
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> list[RuleFlowResponse]:
    res = await db.execute(
        select(RuleFlow)
        .where(RuleFlow.org_id == current.org_id)
        .order_by(RuleFlow.created_at.asc())
    )
    flows = res.scalars().all()
    result: list[RuleFlowResponse] = []
    for flow in flows:
        steps = await _load_steps(db, flow.id)
        result.append(_flow_response(flow, steps))
    return result


@router.post("", response_model=RuleFlowResponse, status_code=201)
async def create_flow(
    body: RuleFlowCreate,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> RuleFlowResponse:
    flow = RuleFlow(
        org_id=current.org_id,
        name=body.name,
        description=body.description,
        is_active=body.is_active,
        trigger_events=body.trigger_events,
    )
    db.add(flow)
    await db.flush()  # get flow.id
    await _sync_steps(db, flow.id, body.steps)
    steps = await _load_steps(db, flow.id)
    return _flow_response(flow, steps)


@router.get("/{flow_id}", response_model=RuleFlowResponse)
async def get_flow(
    flow_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> RuleFlowResponse:
    flow = await _get_flow_or_404(db, flow_id, current.org_id)
    steps = await _load_steps(db, flow_id)
    return _flow_response(flow, steps)


@router.put("/{flow_id}", response_model=RuleFlowResponse)
async def update_flow(
    flow_id: uuid.UUID,
    body: RuleFlowUpdate,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> RuleFlowResponse:
    flow = await _get_flow_or_404(db, flow_id, current.org_id)
    update_data = body.model_dump(exclude_none=True)
    steps_in = update_data.pop("steps", None)
    for k, v in update_data.items():
        setattr(flow, k, v)
    if steps_in is not None:
        await _sync_steps(db, flow_id, body.steps or [])
    await db.flush()
    steps = await _load_steps(db, flow_id)
    return _flow_response(flow, steps)


@router.delete("/{flow_id}", status_code=204)
async def delete_flow(
    flow_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> None:
    flow = await _get_flow_or_404(db, flow_id, current.org_id)
    await db.delete(flow)


# ─── Execution ────────────────────────────────────────────────────────────────


@router.post("/{flow_id}/execute", response_model=RuleFlowExecuteResponse)
async def execute_flow(
    flow_id: uuid.UUID,
    body: RuleFlowExecuteRequest,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> RuleFlowExecuteResponse:
    """
    Execute a rule flow: run each step's rule in sequence.

    For each step:
      - Load the rule by step.rule_id
      - Evaluate it against the current event_data
      - If step.pass_output is True, merge any set_field outputs into event_data
      - Continue to the next step regardless of match result

    Returns per-step results and the final event_data state.
    """
    flow = await _get_flow_or_404(db, flow_id, current.org_id)
    if not flow.is_active:
        raise HTTPException(status_code=400, detail="Rule flow is inactive")

    steps = await _load_steps(db, flow_id)
    t_global = time.monotonic()
    event_data = dict(body.event_data)
    step_results: list[dict[str, Any]] = []

    for step in steps:
        if not step.rule_id:
            step_results.append(
                {
                    "step_order": step.step_order,
                    "label": step.label,
                    "rule_id": None,
                    "skipped": True,
                    "reason": "no rule assigned",
                }
            )
            continue

        # Verify rule belongs to this org
        rule_res = await db.execute(
            select(Rule).where(
                Rule.id == step.rule_id,
                Rule.org_id == current.org_id,
            )
        )
        rule = rule_res.scalar_one_or_none()
        if not rule:
            step_results.append(
                {
                    "step_order": step.step_order,
                    "label": step.label,
                    "rule_id": str(step.rule_id),
                    "skipped": True,
                    "reason": "rule not found",
                }
            )
            continue

        t_step = time.monotonic()
        matched_rules = await process_event(
            event_type=body.event_type,
            event_data=event_data,
            org_id=str(current.org_id),
            db=db,
            dry_run=body.dry_run,
        )

        # Find this rule's result in matched list
        rule_result = next(
            (r for r in matched_rules if r["rule_id"] == str(step.rule_id)), None
        )
        matched = rule_result["matched"] if rule_result else False
        actions_executed = rule_result["actions_executed"] if rule_result else []

        # If pass_output, propagate set_field side-effects
        if step.pass_output and matched:
            for action in actions_executed:
                if action.get("type") == "set_field" and action.get("status") == "ok":
                    field = action.get("field", "")
                    value = action.get("value")
                    if field:
                        # Apply to event_data for next step
                        parts = field.split(".")
                        target = event_data
                        for p in parts[:-1]:
                            target = target.setdefault(p, {})
                        target[parts[-1]] = value

        step_results.append(
            {
                "step_order": step.step_order,
                "label": step.label,
                "rule_id": str(step.rule_id),
                "rule_name": rule.name,
                "matched": matched,
                "actions_executed": actions_executed,
                "elapsed_ms": int((time.monotonic() - t_step) * 1000),
            }
        )

    return RuleFlowExecuteResponse(
        flow_id=flow.id,
        event_type=body.event_type,
        steps_executed=len(steps),
        step_results=step_results,
        final_event_data=event_data,
        elapsed_ms=int((time.monotonic() - t_global) * 1000),
    )
