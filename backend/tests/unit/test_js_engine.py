"""
Unit tests for api.services.js_engine.

Tests evaluate_js_rule and validate_js_syntax.
All tests are skipped gracefully if dukpy is not installed.
"""

import pytest

# Skip the entire module if dukpy is not installed.
# evaluate_js_rule returns (False, {"error": "dukpy not installed"}) in that
# case, but testing the actual JS execution paths requires dukpy to be present.
dukpy = pytest.importorskip(
    "dukpy", reason="dukpy not installed; skipping JS engine tests"
)

from api.services.js_engine import evaluate_js_rule, validate_js_syntax

# ─── evaluate_js_rule ─────────────────────────────────────────────────────────


def test_js_boolean_true_return():
    """Script returning boolean true → (True, {})."""
    matched, data = evaluate_js_rule("true;", {})
    assert matched is True
    assert data == {}


def test_js_boolean_false_return():
    """Script returning boolean false → (False, {})."""
    matched, data = evaluate_js_rule("false;", {})
    assert matched is False
    assert data == {}


def test_js_object_return_matched_true():
    """Script returning object with matched=true and data → (True, data)."""
    code = "({ matched: true, data: { score: 99 } });"
    matched, output = evaluate_js_rule(code, {})
    assert matched is True
    assert output.get("score") == 99


def test_js_object_return_matched_false():
    """Script returning object with matched=false → (False, {})."""
    code = "({ matched: false, data: { score: 99 } });"
    matched, output = evaluate_js_rule(code, {})
    assert matched is False
    assert output == {}


def test_js_truthy_non_boolean():
    """Script returning a truthy non-boolean (1 + 1 = 2) → (True, {})."""
    matched, data = evaluate_js_rule("1 + 1;", {})
    assert matched is True
    assert data == {}


def test_js_falsy_zero():
    """Script returning 0 (falsy) → (False, {})."""
    matched, data = evaluate_js_rule("0;", {})
    assert matched is False
    assert data == {}


def test_js_event_data_access():
    """Script accesses event_data via the `event` global."""
    code = "event.amount > 50;"
    matched, data = evaluate_js_rule(code, {"amount": 100})
    assert matched is True
    assert data == {}


def test_js_event_data_access_false():
    """Script accesses event_data and condition evaluates to false."""
    code = "event.amount > 50;"
    matched, data = evaluate_js_rule(code, {"amount": 10})
    assert matched is False


def test_js_exception_returns_false():
    """Script that throws a JS exception → (False, {}) — no Python exception raised."""
    matched, data = evaluate_js_rule("throw new Error('x');", {})
    assert matched is False
    # The implementation returns {} or {"error": ...} — either is acceptable
    assert isinstance(data, dict)


def test_js_empty_code_returns_false():
    """Empty code string → (False, {})."""
    matched, data = evaluate_js_rule("", {})
    assert matched is False
    assert isinstance(data, dict)


def test_js_whitespace_only_code_returns_false():
    """Whitespace-only code string → (False, {})."""
    matched, data = evaluate_js_rule("   \n\t  ", {})
    assert matched is False


# ─── validate_js_syntax ───────────────────────────────────────────────────────


def test_validate_js_syntax_valid():
    """Valid JavaScript → returns None (no error)."""
    result = validate_js_syntax("var x = 1 + 2;")
    assert result is None


def test_validate_js_syntax_invalid():
    """Invalid JavaScript → returns a non-empty error string."""
    result = validate_js_syntax("var x = {")
    # Should return an error message (string), not None
    assert isinstance(result, str)
    assert len(result) > 0


def test_validate_js_syntax_empty_string():
    """Empty string — implementation-defined result; just assert correct type."""
    result = validate_js_syntax("")
    # Must be either None (valid) or a string (error message)
    assert result is None or isinstance(result, str)


def test_validate_js_syntax_complex_valid():
    """Multi-statement valid JS → None."""
    code = """
    var x = 1;
    var y = x + 2;
    y > 2;
    """
    assert validate_js_syntax(code) is None
