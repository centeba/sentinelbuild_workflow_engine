"""Guard against the invoked-but-unregistered Temporal activity bug (Gate 20).

mit-stack is the primary Temporal orchestrator. Its workflows invoke activities
either by function reference (``execute_activity(run_agent_turn, ...)``) or by
string name (``execute_activity("create_execution_record", ...)``). If the
worker's ``activities=[...]`` list omits one, that workflow path fails at runtime
with "activity function is not registered on this worker" — a latent bug that
only trips when the path executes.

This test statically cross-checks, across every ``temporal/activities/*.py`` and
``temporal/workflows/*.py`` plus ``temporal/worker.py``, that every invoked
activity we can resolve statically is registered. It only flags names that ARE
known activities (a ``@activity.defn``), so dynamic/computed dispatch never
false-positives.

Mirrors the email-extractor guard (services/email-extractor/tests/
test_worker_registration.py), generalised for mit-stack's multi-file layout.
"""

from __future__ import annotations

import ast
import pathlib

# backend/tests/temporal/<this file> → backend/temporal
_TEMPORAL = pathlib.Path(__file__).resolve().parents[2] / "temporal"


def _defn_names() -> tuple[set[str], dict[str, str]]:
    """Scan every activities/*.py for @activity.defn.

    Returns (def_names, name_to_def): the set of decorated function names, and a
    map from an explicit ``@activity.defn(name="x")`` override to the function
    name (so a string-named invocation can resolve to what the worker registers).
    """
    def_names: set[str] = set()
    name_to_def: dict[str, str] = {}
    for path in sorted((_TEMPORAL / "activities").glob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if not isinstance(node, ast.AsyncFunctionDef | ast.FunctionDef):
                continue
            for dec in node.decorator_list:
                override = None
                is_defn = False
                if isinstance(dec, ast.Attribute) and dec.attr == "defn":
                    is_defn = True
                elif (
                    isinstance(dec, ast.Call)
                    and isinstance(dec.func, ast.Attribute)
                    and dec.func.attr == "defn"
                ):
                    is_defn = True
                    for kw in dec.keywords:
                        if kw.arg == "name" and isinstance(kw.value, ast.Constant):
                            override = kw.value.value
                if is_defn:
                    def_names.add(node.name)
                    if override:
                        name_to_def[override] = node.name
    return def_names, name_to_def


def _registered() -> set[str]:
    """Bare function names in the worker's Worker(activities=[...]) list."""
    tree = ast.parse((_TEMPORAL / "worker.py").read_text(encoding="utf-8"))
    reg: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "Worker":
            for kw in node.keywords:
                if kw.arg == "activities" and isinstance(kw.value, ast.List):
                    for el in kw.value.elts:
                        if isinstance(el, ast.Name):
                            reg.add(el.id)
                        elif isinstance(el, ast.Attribute):
                            reg.add(el.attr)
    return reg


def _invoked() -> set[str]:
    """First-arg of every execute_activity(...) across workflows/*.py, as either
    a string name or a referenced function name."""
    names: set[str] = set()
    for path in sorted((_TEMPORAL / "workflows").glob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if not (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr == "execute_activity"
                and node.args
            ):
                continue
            arg = node.args[0]
            if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                names.add(arg.value)
            elif isinstance(arg, ast.Name):
                names.add(arg.id)
            elif isinstance(arg, ast.Attribute):
                names.add(arg.attr)
    return names


def test_every_invoked_activity_is_registered() -> None:
    def_names, name_to_def = _defn_names()
    registered = _registered()

    missing: list[str] = []
    for invoked in _invoked():
        # Resolve to the function name the worker would register.
        defn = name_to_def.get(invoked, invoked)
        # Only assert on names that ARE real activities — never flag dynamic /
        # computed dispatch strings that don't correspond to a @activity.defn.
        if defn in def_names and defn not in registered:
            missing.append(invoked)

    assert not missing, (
        "workflows invoke activities the worker never registers "
        f"(NotFoundError at runtime): {sorted(missing)}"
    )


def test_guard_sees_activities_and_registrations() -> None:
    # Sanity: the AST scan actually found the pieces (guards against a silently
    # empty check if the layout moves).
    def_names, _ = _defn_names()
    assert len(def_names) >= 10, "expected many @activity.defn functions"
    assert len(_registered()) >= 10, "expected many registered activities"
    assert _invoked(), "expected execute_activity calls in the workflows"
