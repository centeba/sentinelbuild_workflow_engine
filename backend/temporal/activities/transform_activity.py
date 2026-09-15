"""Data transformation activity using JMESPath and JSONPath."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from temporalio import activity


@dataclass
class TransformParams:
    input_data: dict[str, Any]
    expression: str
    engine: str = "jmespath"  # jmespath | jsonpath | python


@activity.defn
async def transform_data(params: TransformParams) -> dict[str, Any]:
    match params.engine:
        case "jmespath":
            import jmespath

            result = jmespath.search(params.expression, params.input_data)

        case "jsonpath":
            from jsonpath_ng import parse

            expr = parse(params.expression)
            matches = [match.value for match in expr.find(params.input_data)]
            result = matches[0] if len(matches) == 1 else matches

        case "python":
            # Sandboxed Python expression
            from RestrictedPython import compile_restricted, safe_globals
            from RestrictedPython.Guards import (
                guarded_iter_unpack_sequence,
                safer_getattr,
            )

            code = compile_restricted(
                f"result = {params.expression}", "<transform>", "exec"
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
            result = globs.get("result")

        case _:
            raise ValueError(f"Unknown transform engine: {params.engine}")

    # Normalize output to dict
    if isinstance(result, dict):
        return result
    return {"result": result}
