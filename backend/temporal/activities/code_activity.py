"""Sandboxed code execution activity using RestrictedPython."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from temporalio import activity


@dataclass
class CodeParams:
    code: str
    input_data: dict[str, Any]
    language: str = "python"  # only python supported for now


@activity.defn
async def run_code(params: CodeParams) -> dict[str, Any]:
    if params.language != "python":
        raise ValueError(
            f"Language '{params.language}' not supported. Only Python is available."
        )

    from RestrictedPython import compile_restricted, safe_builtins, safe_globals
    from RestrictedPython.Guards import guarded_iter_unpack_sequence, safer_getattr

    # Build a safe environment
    restricted_builtins = dict(safe_builtins)
    # Allow common safe imports
    restricted_globals = {
        **safe_globals,
        "__builtins__": restricted_builtins,
        # Required by RestrictedPython for subscript access (e.g. data['key'])
        "_getitem_": lambda obj, idx: obj[idx],
        # Required for attribute access on objects
        "_getattr_": safer_getattr,
        # Required for iteration and unpacking
        "_getiter_": iter,
        "_iter_unpack_sequence_": guarded_iter_unpack_sequence,
        "data": params.input_data,
        "result": {},
        "json": __import__("json"),
        "math": __import__("math"),
        "re": __import__("re"),
        "datetime": __import__("datetime"),
    }

    try:
        code = compile_restricted(params.code, "<code_node>", "exec")
        exec(code, restricted_globals)
        result = restricted_globals.get("result", {})
    except Exception as exc:
        raise RuntimeError(f"Code execution failed: {exc}") from exc

    if not isinstance(result, dict):
        result = {"result": result}
    return result
