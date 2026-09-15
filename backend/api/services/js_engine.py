"""
JavaScript rule engine — Gap 11: Scripted rules.

Executes sandboxed JavaScript code via dukpy (Duktape embedding).
The script receives the event data as a global `event` object and must
return either:
  - A boolean (true = match, false = no match)
  - An object: { matched: true/false, data: { ... } }
    where `data` fields are merged back into event_data on match.

Example JS code:
    // Match orders over $500 from VIP customers
    var order = event.data || {};
    order.amount > 500 && event.customer_tier === 'vip';

Or with output:
    var score = event.credit_score;
    if (score >= 750) {
        ({ matched: true, data: { risk_level: 'low', rate: 3.5 } });
    } else if (score >= 650) {
        ({ matched: true, data: { risk_level: 'medium', rate: 5.0 } });
    } else {
        ({ matched: false });
    }
"""

import json
import logging
from typing import Any

from shared.config import get_settings

logger = logging.getLogger(__name__)

# Try to import dukpy; fall back gracefully if not installed
try:
    import dukpy

    _DUKPY_AVAILABLE = True
except ImportError:
    _DUKPY_AVAILABLE = False
    logger.warning(
        "dukpy not installed — JavaScript rule type will always return (False, {}). "
        "Install with: pip install dukpy"
    )


# Hard limit: reject scripts that run longer than this (dukpy timeout is best-effort).
# Configurable via JS_TIMEOUT_MS env var.
def _js_timeout_ms() -> int:
    return get_settings().js_timeout_ms


# Built-in helpers injected into every JS context
_JS_PRELUDE = """
var console = { log: function(){}, warn: function(){}, error: function(){} };
function __run__(event, code) {
    try {
        var __result__ = eval(code);
        if (typeof __result__ === 'boolean') {
            return JSON.stringify({ matched: __result__, data: {} });
        }
        if (__result__ !== null && typeof __result__ === 'object') {
            return JSON.stringify({
                matched: !!__result__.matched,
                data: __result__.data || {}
            });
        }
        // Treat any truthy non-boolean as a match
        return JSON.stringify({ matched: !!__result__, data: {} });
    } catch(e) {
        return JSON.stringify({ matched: false, error: String(e) });
    }
}
"""


def evaluate_js_rule(
    code: str, event_data: dict[str, Any]
) -> tuple[bool, dict[str, Any]]:
    """
    Execute `code` in a sandboxed Duktape JS context.

    Args:
        code: JavaScript expression/statements. The last evaluated value
              determines the match result (see module docstring).
        event_data: The event payload available as `event` in JS.

    Returns:
        (matched: bool, output_data: dict)
        output_data fields should be merged into event_data by the caller
        if matched is True and output_data is non-empty.
    """
    if not _DUKPY_AVAILABLE:
        return False, {"error": "dukpy not installed"}

    if not code or not code.strip():
        return False, {"error": "Empty JS code"}

    try:
        # Serialize event_data to JSON so it's safely passed into Duktape
        event_json = json.dumps(event_data, default=str)

        full_script = (
            _JS_PRELUDE
            + f"\nvar event = {event_json};\n"
            + f"__run__(event, {json.dumps(code)});"
        )

        raw = dukpy.evaljs(full_script)

        if isinstance(raw, str):
            result = json.loads(raw)
        elif isinstance(raw, dict):
            result = raw
        else:
            return False, {"error": f"Unexpected JS return type: {type(raw)}"}

        matched = bool(result.get("matched", False))
        # Only surface ``data`` on a positive match — a non-matching rule must
        # not leak its payload to the caller (which merges it into the event).
        output_data = (result.get("data") or {}) if matched else {}
        if isinstance(output_data, str):
            try:
                output_data = json.loads(output_data)
            except Exception:
                output_data = {}

        if "error" in result:
            logger.debug("JS rule error: %s", result["error"])

        return matched, output_data

    except Exception as exc:
        logger.warning("JS rule execution failed: %s", exc)
        return False, {"error": str(exc)}


def validate_js_syntax(code: str) -> str | None:
    """
    Quick syntax check. Returns None on success, error message on failure.
    Used by the API before saving a JS rule.
    """
    if not _DUKPY_AVAILABLE:
        return None  # Can't validate; allow saving

    try:
        # Wrap in a function to trigger syntax errors without executing
        check_script = f"(function(){{ {code} }})"
        dukpy.evaljs(f"try {{ {check_script}; null; }} catch(e) {{ String(e); }}")
        return None
    except Exception as exc:
        return str(exc)
