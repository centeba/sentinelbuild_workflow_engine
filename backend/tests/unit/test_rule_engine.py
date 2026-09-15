"""
Unit tests for api.services.rule_engine — pure-function helpers.

Covers:
  - _get_field: dot-notation field access
  - _eval_leaf: single condition evaluation for all operators
  - _interp: template interpolation
  - evaluate_decision_table: decision table with hit policies
"""

from api.services.rule_engine import (
    _eval_leaf,
    _get_field,
    _interp,
    evaluate_decision_table,
)

# ─── _get_field ───────────────────────────────────────────────────────────────


def test_get_field_dot_notation():
    """Two-level dot-notation returns the nested value."""
    data = {"user": {"email": "a@b.com"}}
    assert _get_field(data, "user.email") == "a@b.com"


def test_get_field_missing_key_returns_none():
    """A missing key at any level returns None."""
    data = {"user": {"name": "Alice"}}
    assert _get_field(data, "user.email") is None


def test_get_field_deeply_nested():
    """Three-level dot-notation returns the correct value."""
    data = {"a": {"b": {"c": 42}}}
    assert _get_field(data, "a.b.c") == 42


def test_get_field_non_dict_intermediate_returns_none():
    """When an intermediate value is not a dict, returns None."""
    data = {"user": "not-a-dict"}
    assert _get_field(data, "user.email") is None


def test_get_field_top_level():
    """Single-segment path returns the top-level value."""
    data = {"score": 99}
    assert _get_field(data, "score") == 99


# ─── _eval_leaf — fixture data ────────────────────────────────────────────────

_DATA = {
    "name": "Alice",
    "score": "85",
    "active": "true",
    "email": "alice@example.com",
    "tags": "vip,premium",
    "created_at": "2020-01-01T00:00:00",
    "empty_field": "",
}


# ─── eq / neq ─────────────────────────────────────────────────────────────────


def test_eval_leaf_eq_true():
    """eq: field value equals ref → True."""
    assert (
        _eval_leaf(_DATA, {"field": "name", "operator": "eq", "value": "Alice"}) is True
    )


def test_eval_leaf_eq_false():
    """eq: field value does not equal ref → False."""
    assert (
        _eval_leaf(_DATA, {"field": "name", "operator": "eq", "value": "Bob"}) is False
    )


def test_eval_leaf_neq_true():
    """neq: field value differs from ref → True."""
    assert (
        _eval_leaf(_DATA, {"field": "name", "operator": "neq", "value": "Bob"}) is True
    )


def test_eval_leaf_neq_false():
    """neq: field value equals ref → False."""
    assert (
        _eval_leaf(_DATA, {"field": "name", "operator": "neq", "value": "Alice"})
        is False
    )


# ─── contains / not_contains ──────────────────────────────────────────────────


def test_eval_leaf_contains_true():
    """contains: substring present → True."""
    assert (
        _eval_leaf(
            _DATA, {"field": "email", "operator": "contains", "value": "example"}
        )
        is True
    )


def test_eval_leaf_contains_false():
    """contains: substring absent → False."""
    assert (
        _eval_leaf(_DATA, {"field": "email", "operator": "contains", "value": "google"})
        is False
    )


def test_eval_leaf_not_contains_true():
    """not_contains: substring absent → True."""
    assert (
        _eval_leaf(
            _DATA, {"field": "email", "operator": "not_contains", "value": "google"}
        )
        is True
    )


def test_eval_leaf_not_contains_false():
    """not_contains: substring present → False."""
    assert (
        _eval_leaf(
            _DATA, {"field": "email", "operator": "not_contains", "value": "example"}
        )
        is False
    )


# ─── starts_with / ends_with ──────────────────────────────────────────────────


def test_eval_leaf_starts_with_true():
    """starts_with: prefix matches → True."""
    assert (
        _eval_leaf(
            _DATA, {"field": "email", "operator": "starts_with", "value": "alice"}
        )
        is True
    )


def test_eval_leaf_starts_with_false():
    """starts_with: prefix does not match → False."""
    assert (
        _eval_leaf(_DATA, {"field": "email", "operator": "starts_with", "value": "bob"})
        is False
    )


def test_eval_leaf_ends_with_true():
    """ends_with: suffix matches → True."""
    assert (
        _eval_leaf(_DATA, {"field": "email", "operator": "ends_with", "value": ".com"})
        is True
    )


def test_eval_leaf_ends_with_false():
    """ends_with: suffix does not match → False."""
    assert (
        _eval_leaf(_DATA, {"field": "email", "operator": "ends_with", "value": ".org"})
        is False
    )


# ─── numeric comparisons ──────────────────────────────────────────────────────


def test_eval_leaf_gt_true():
    """gt: 85 > 80 → True."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "gt", "value": "80"}) is True
    )


def test_eval_leaf_gt_false():
    """gt: 85 > 90 → False."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "gt", "value": "90"}) is False
    )


def test_eval_leaf_gte_equal():
    """gte: 85 >= 85 → True."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "gte", "value": "85"}) is True
    )


def test_eval_leaf_gte_greater():
    """gte: 85 >= 80 → True."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "gte", "value": "80"}) is True
    )


def test_eval_leaf_gte_false():
    """gte: 85 >= 90 → False."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "gte", "value": "90"}) is False
    )


def test_eval_leaf_lt_true():
    """lt: 85 < 90 → True."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "lt", "value": "90"}) is True
    )


def test_eval_leaf_lt_false():
    """lt: 85 < 80 → False."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "lt", "value": "80"}) is False
    )


def test_eval_leaf_lte_equal():
    """lte: 85 <= 85 → True."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "lte", "value": "85"}) is True
    )


def test_eval_leaf_lte_false():
    """lte: 85 <= 80 → False."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "lte", "value": "80"}) is False
    )


# ─── in / not_in ──────────────────────────────────────────────────────────────


def test_eval_leaf_in_true():
    """in: field value is in comma-separated list → True."""
    assert (
        _eval_leaf(
            _DATA, {"field": "name", "operator": "in", "value": "Alice,Bob,Carol"}
        )
        is True
    )


def test_eval_leaf_in_false():
    """in: field value is not in comma-separated list → False."""
    assert (
        _eval_leaf(_DATA, {"field": "name", "operator": "in", "value": "Bob,Carol"})
        is False
    )


def test_eval_leaf_in_list_value():
    """in: ref can also be a Python list."""
    assert (
        _eval_leaf(
            _DATA, {"field": "name", "operator": "in", "value": ["Alice", "Bob"]}
        )
        is True
    )


def test_eval_leaf_not_in_true():
    """not_in: field value absent from list → True."""
    assert (
        _eval_leaf(_DATA, {"field": "name", "operator": "not_in", "value": "Bob,Carol"})
        is True
    )


def test_eval_leaf_not_in_false():
    """not_in: field value present in list → False."""
    assert (
        _eval_leaf(_DATA, {"field": "name", "operator": "not_in", "value": "Alice,Bob"})
        is False
    )


# ─── between ──────────────────────────────────────────────────────────────────


def test_eval_leaf_between_in_range():
    """between: 85 is within [50, 100] → True."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "between", "value": "50,100"})
        is True
    )


def test_eval_leaf_between_boundary_low():
    """between: 85 is on lower boundary [85, 100] → True."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "between", "value": "85,100"})
        is True
    )


def test_eval_leaf_between_boundary_high():
    """between: 85 is on upper boundary [50, 85] → True."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "between", "value": "50,85"})
        is True
    )


def test_eval_leaf_between_out_of_range():
    """between: 85 is not within [90, 100] → False."""
    assert (
        _eval_leaf(_DATA, {"field": "score", "operator": "between", "value": "90,100"})
        is False
    )


def test_eval_leaf_between_invalid_value():
    """between: non-numeric field value → False (coercion fails)."""
    assert (
        _eval_leaf(_DATA, {"field": "name", "operator": "between", "value": "0,100"})
        is False
    )


# ─── is_empty / is_not_empty ──────────────────────────────────────────────────


def test_eval_leaf_is_empty_empty_string():
    """is_empty: empty string → True."""
    assert (
        _eval_leaf(_DATA, {"field": "empty_field", "operator": "is_empty", "value": ""})
        is True
    )


def test_eval_leaf_is_empty_none():
    """is_empty: missing key (None) → True."""
    assert (
        _eval_leaf(_DATA, {"field": "nonexistent", "operator": "is_empty", "value": ""})
        is True
    )


def test_eval_leaf_is_empty_non_empty():
    """is_empty: non-empty string → False."""
    assert (
        _eval_leaf(_DATA, {"field": "name", "operator": "is_empty", "value": ""})
        is False
    )


def test_eval_leaf_is_not_empty_true():
    """is_not_empty: non-empty field → True."""
    assert (
        _eval_leaf(_DATA, {"field": "name", "operator": "is_not_empty", "value": ""})
        is True
    )


def test_eval_leaf_is_not_empty_false():
    """is_not_empty: empty field → False."""
    assert (
        _eval_leaf(
            _DATA, {"field": "empty_field", "operator": "is_not_empty", "value": ""}
        )
        is False
    )


# ─── is_true / is_false ───────────────────────────────────────────────────────


def test_eval_leaf_is_true_string_true():
    """is_true: 'true' string → True."""
    assert (
        _eval_leaf(_DATA, {"field": "active", "operator": "is_true", "value": ""})
        is True
    )


def test_eval_leaf_is_true_string_false():
    """is_true: 'false' string → False."""
    data = {**_DATA, "active": "false"}
    assert (
        _eval_leaf(data, {"field": "active", "operator": "is_true", "value": ""})
        is False
    )


def test_eval_leaf_is_true_numeric_one():
    """is_true: '1' → True."""
    data = {**_DATA, "active": "1"}
    assert (
        _eval_leaf(data, {"field": "active", "operator": "is_true", "value": ""})
        is True
    )


def test_eval_leaf_is_false_string_false():
    """is_false: 'false' string → True."""
    data = {**_DATA, "active": "false"}
    assert (
        _eval_leaf(data, {"field": "active", "operator": "is_false", "value": ""})
        is True
    )


def test_eval_leaf_is_false_string_true():
    """is_false: 'true' string → False."""
    assert (
        _eval_leaf(_DATA, {"field": "active", "operator": "is_false", "value": ""})
        is False
    )


# ─── matches_regex ────────────────────────────────────────────────────────────


def test_eval_leaf_matches_regex_true():
    """matches_regex: valid regex that matches → True."""
    assert (
        _eval_leaf(
            _DATA, {"field": "email", "operator": "matches_regex", "value": r"^alice@"}
        )
        is True
    )


def test_eval_leaf_matches_regex_false():
    """matches_regex: regex that does not match → False."""
    assert (
        _eval_leaf(
            _DATA, {"field": "email", "operator": "matches_regex", "value": r"^bob@"}
        )
        is False
    )


def test_eval_leaf_matches_regex_invalid_pattern():
    """matches_regex: invalid regex pattern → False (no exception)."""
    assert (
        _eval_leaf(
            _DATA, {"field": "email", "operator": "matches_regex", "value": r"[invalid"}
        )
        is False
    )


# ─── date operators ───────────────────────────────────────────────────────────


def test_eval_leaf_date_before_true():
    """date_before: '2019-01-01' is before '2020-01-01' → True."""
    data = {"ts": "2019-01-01T00:00:00"}
    assert (
        _eval_leaf(
            data, {"field": "ts", "operator": "date_before", "value": "2020-01-01"}
        )
        is True
    )


def test_eval_leaf_date_before_false():
    """date_before: '2021-01-01' is NOT before '2020-01-01' → False."""
    data = {"ts": "2021-01-01T00:00:00"}
    assert (
        _eval_leaf(
            data, {"field": "ts", "operator": "date_before", "value": "2020-01-01"}
        )
        is False
    )


def test_eval_leaf_date_after_true():
    """date_after: '2021-01-01' is after '2020-01-01' → True."""
    data = {"ts": "2021-01-01T00:00:00"}
    assert (
        _eval_leaf(
            data, {"field": "ts", "operator": "date_after", "value": "2020-01-01"}
        )
        is True
    )


def test_eval_leaf_date_after_false():
    """date_after: '2019-01-01' is NOT after '2020-01-01' → False."""
    data = {"ts": "2019-01-01T00:00:00"}
    assert (
        _eval_leaf(
            data, {"field": "ts", "operator": "date_after", "value": "2020-01-01"}
        )
        is False
    )


def test_eval_leaf_date_equals_same_date():
    """date_equals: same ISO date → True."""
    data = {"ts": "2020-01-01T12:30:00"}
    assert (
        _eval_leaf(
            data, {"field": "ts", "operator": "date_equals", "value": "2020-01-01"}
        )
        is True
    )


def test_eval_leaf_date_equals_different_date():
    """date_equals: different date → False."""
    data = {"ts": "2020-06-15T00:00:00"}
    assert (
        _eval_leaf(
            data, {"field": "ts", "operator": "date_equals", "value": "2020-01-01"}
        )
        is False
    )


# ─── unknown operator ─────────────────────────────────────────────────────────


def test_eval_leaf_unknown_operator_returns_false():
    """Unknown operator string → False."""
    assert (
        _eval_leaf(
            _DATA, {"field": "name", "operator": "does_not_exist", "value": "Alice"}
        )
        is False
    )


# ─── _interp ──────────────────────────────────────────────────────────────────


def test_interp_simple_field_substitution():
    """{{name}} is replaced with the field value."""
    data = {"name": "Alice"}
    assert _interp("Hello, {{name}}!", data) == "Hello, Alice!"


def test_interp_nested_field():
    """{{user.email}} resolves nested dot-notation field."""
    data = {"user": {"email": "alice@example.com"}}
    assert _interp("Email: {{user.email}}", data) == "Email: alice@example.com"


def test_interp_arithmetic_multiplication():
    """{{score * 2}} evaluates the arithmetic expression."""
    data = {"score": "100"}
    result = _interp("{{score * 2}}", data)
    # Result may be "200.0" or "200" — both are acceptable
    assert result in ("200.0", "200")


def test_interp_arithmetic_addition():
    """{{score + 5}} evaluates the addition expression."""
    data = {"score": "95"}
    result = _interp("{{score + 5}}", data)
    assert result in ("100.0", "100")


def test_interp_no_template_tokens():
    """A string with no {{ }} tokens is returned unchanged."""
    data = {"name": "Alice"}
    assert _interp("No placeholders here.", data) == "No placeholders here."


def test_interp_missing_field_becomes_empty_string():
    """A {{ }} referencing a missing field produces an empty string."""
    data = {}
    assert _interp("Value: {{missing_key}}", data) == "Value: "


def test_interp_multiple_tokens():
    """Multiple {{}} tokens in one string are all substituted."""
    data = {"first": "Alice", "last": "Smith"}
    assert _interp("{{first}} {{last}}", data) == "Alice Smith"


# ─── evaluate_decision_table ──────────────────────────────────────────────────


def _make_table(rows, hit_policy="first"):
    """Helper: build a minimal decision table dict."""
    return {
        "hit_policy": hit_policy,
        "input_columns": [{"field": "data.tier", "label": "Tier"}],
        "output_columns": [{"field": "discount_pct", "label": "Discount"}],
        "rows": rows,
    }


def _make_row(op, value, output_value):
    """Helper: build a single decision table row."""
    return {
        "conditions": [{"operator": op, "value": value}],
        "outputs": [{"value": output_value}],
    }


_DT_DATA = {"data": {"tier": "gold"}}


def test_decision_table_first_match_returns_first_row():
    """hit_policy=first: returns first matching row and stops."""
    rows = [
        _make_row("eq", "gold", "20"),
        _make_row("eq", "gold", "99"),  # would also match, but skipped
    ]
    table = _make_table(rows, hit_policy="first")
    matched, actions = evaluate_decision_table(_DT_DATA, table)
    assert matched is True
    assert len(actions) == 1
    assert actions[0]["value"] == "20"


def test_decision_table_first_no_match():
    """hit_policy=first: no matching row → (False, [])."""
    rows = [_make_row("eq", "silver", "10")]
    table = _make_table(rows, hit_policy="first")
    matched, actions = evaluate_decision_table(_DT_DATA, table)
    assert matched is False
    assert actions == []


def test_decision_table_collect_all_multiple_matches():
    """hit_policy=collect_all: all matching rows are collected."""
    rows = [
        _make_row("eq", "gold", "20"),
        _make_row("eq", "silver", "10"),  # no match
        _make_row("eq", "gold", "5"),  # also matches
    ]
    table = _make_table(rows, hit_policy="collect_all")
    matched, actions = evaluate_decision_table(_DT_DATA, table)
    assert matched is True
    assert len(actions) == 2
    values = [a["value"] for a in actions]
    assert "20" in values
    assert "5" in values


def test_decision_table_collect_all_no_match():
    """hit_policy=collect_all: no matching rows → (False, [])."""
    rows = [_make_row("eq", "bronze", "5")]
    table = _make_table(rows, hit_policy="collect_all")
    matched, actions = evaluate_decision_table(_DT_DATA, table)
    assert matched is False
    assert actions == []


def test_decision_table_any_match_returns_true_no_actions():
    """hit_policy=any_match: returns (True, []) when any row matches."""
    rows = [_make_row("eq", "gold", "20")]
    table = _make_table(rows, hit_policy="any_match")
    matched, actions = evaluate_decision_table(_DT_DATA, table)
    assert matched is True
    assert actions == []


def test_decision_table_any_match_no_match():
    """hit_policy=any_match: no row matches → (False, [])."""
    rows = [_make_row("eq", "silver", "10")]
    table = _make_table(rows, hit_policy="any_match")
    matched, actions = evaluate_decision_table(_DT_DATA, table)
    assert matched is False
    assert actions == []


def test_decision_table_unique_no_conflict():
    """hit_policy=unique: single match → (True, merged_actions)."""
    rows = [
        _make_row("eq", "gold", "20"),
        _make_row("eq", "silver", "10"),  # no match
    ]
    table = _make_table(rows, hit_policy="unique")
    matched, actions = evaluate_decision_table(_DT_DATA, table)
    assert matched is True
    assert len(actions) == 1
    assert actions[0]["value"] == "20"


def test_decision_table_unique_conflict_returns_error_action():
    """hit_policy=unique: same output field from multiple rows → error action."""
    rows = [
        _make_row("eq", "gold", "20"),
        _make_row("eq", "gold", "30"),  # same condition — conflict on discount_pct
    ]
    table = _make_table(rows, hit_policy="unique")
    matched, actions = evaluate_decision_table(_DT_DATA, table)
    assert matched is True
    assert len(actions) == 1
    assert actions[0]["type"] == "error"
    assert "unique hit policy" in actions[0]["message"]


def test_decision_table_wildcard_any_operator():
    """Wildcard 'ANY' condition always matches regardless of field value."""
    rows = [
        {
            "conditions": [{"operator": "ANY", "value": ""}],
            "outputs": [{"value": "15"}],
        }
    ]
    # Even with a tier value that would not equal anything specific
    data = {"data": {"tier": "platinum"}}
    table = _make_table(rows, hit_policy="first")
    matched, actions = evaluate_decision_table(data, table)
    assert matched is True
    assert actions[0]["value"] == "15"


def test_decision_table_no_rows():
    """An empty rows list → (False, []) for all hit policies."""
    for policy in ("first", "collect_all", "any_match", "unique"):
        table = _make_table([], hit_policy=policy)
        matched, actions = evaluate_decision_table(_DT_DATA, table)
        assert matched is False, f"Expected no match for hit_policy={policy}"
        assert actions == [], f"Expected empty actions for hit_policy={policy}"
