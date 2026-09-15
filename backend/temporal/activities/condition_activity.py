"""Condition evaluation activity for if/else branching."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from temporalio import activity


@dataclass
class ConditionParams:
    input_data: dict[str, Any]
    expression: str  # e.g. "data.status == 'active'" or JMESPath boolean


@activity.defn
async def evaluate_condition(params: ConditionParams) -> bool:
    """Evaluate a boolean expression against input data. Returns True/False."""
    from RestrictedPython import compile_restricted, safe_globals
    from RestrictedPython.Guards import guarded_iter_unpack_sequence, safer_getattr

    # Expose data as 'data' in expression scope
    code = compile_restricted(
        f"result = bool({params.expression})", "<condition>", "exec"
    )
    globs = {
        **safe_globals,
        "_getitem_": lambda obj, idx: obj[idx],
        "_getattr_": safer_getattr,
        "_getiter_": iter,
        "_iter_unpack_sequence_": guarded_iter_unpack_sequence,
        "data": params.input_data,
    }
    exec(code, globs)
    return bool(globs.get("result", False))
