"""
Unit tests for api.constants.

Verifies that:
  - All list constants contain exactly the documented values
  - No list contains duplicate entries
  - Named scalar constants match their expected string values
  - Named constants are members of their corresponding list
"""

import pytest

from api import constants

# ─── Helper ───────────────────────────────────────────────────────────────────


def _no_duplicates(lst: list) -> bool:
    """Return True if the list has no duplicate elements."""
    return len(lst) == len(set(lst))


# ─── Role constants ───────────────────────────────────────────────────────────


def test_all_roles_contains_exactly_five_roles():
    """ALL_ROLES contains exactly 5 entries (3 original + 2 SentinelBuild roles)."""
    assert len(constants.ALL_ROLES) == 5


def test_all_roles_contains_expected_values():
    """ALL_ROLES contains admin, member, viewer, system_admin, and company_admin."""
    assert set(constants.ALL_ROLES) == {
        "admin",
        "member",
        "viewer",
        "system_admin",
        "company_admin",
    }


def test_all_roles_no_duplicates():
    """ALL_ROLES has no duplicate values."""
    assert _no_duplicates(constants.ALL_ROLES)


def test_role_admin_value():
    """ROLE_ADMIN == 'admin'."""
    assert constants.ROLE_ADMIN == "admin"


def test_role_member_value():
    """ROLE_MEMBER == 'member'."""
    assert constants.ROLE_MEMBER == "member"


def test_role_viewer_value():
    """ROLE_VIEWER == 'viewer'."""
    assert constants.ROLE_VIEWER == "viewer"


def test_role_admin_in_all_roles():
    """ROLE_ADMIN is a member of ALL_ROLES."""
    assert constants.ROLE_ADMIN in constants.ALL_ROLES


def test_role_member_in_all_roles():
    """ROLE_MEMBER is a member of ALL_ROLES."""
    assert constants.ROLE_MEMBER in constants.ALL_ROLES


def test_role_viewer_in_all_roles():
    """ROLE_VIEWER is a member of ALL_ROLES."""
    assert constants.ROLE_VIEWER in constants.ALL_ROLES


# ─── Rule type constants ──────────────────────────────────────────────────────


def test_all_rule_types_contains_exactly_three():
    """ALL_RULE_TYPES contains exactly 3 entries."""
    assert len(constants.ALL_RULE_TYPES) == 3


def test_all_rule_types_expected_values():
    """ALL_RULE_TYPES contains condition_tree, decision_table, javascript."""
    assert set(constants.ALL_RULE_TYPES) == {
        "condition_tree",
        "decision_table",
        "javascript",
    }


def test_all_rule_types_no_duplicates():
    """ALL_RULE_TYPES has no duplicate values."""
    assert _no_duplicates(constants.ALL_RULE_TYPES)


def test_rule_type_condition_tree_value():
    """RULE_TYPE_CONDITION_TREE == 'condition_tree'."""
    assert constants.RULE_TYPE_CONDITION_TREE == "condition_tree"


# ─── Rule status constants ────────────────────────────────────────────────────


def test_all_rule_statuses_contains_exactly_two():
    """ALL_RULE_STATUSES contains exactly 2 entries."""
    assert len(constants.ALL_RULE_STATUSES) == 2


def test_all_rule_statuses_expected_values():
    """ALL_RULE_STATUSES contains draft and published."""
    assert set(constants.ALL_RULE_STATUSES) == {"draft", "published"}


def test_all_rule_statuses_no_duplicates():
    """ALL_RULE_STATUSES has no duplicate values."""
    assert _no_duplicates(constants.ALL_RULE_STATUSES)


def test_rule_status_draft_value():
    """RULE_STATUS_DRAFT == 'draft'."""
    assert constants.RULE_STATUS_DRAFT == "draft"


def test_rule_status_published_value():
    """RULE_STATUS_PUBLISHED == 'published'."""
    assert constants.RULE_STATUS_PUBLISHED == "published"


# ─── Approval status constants ────────────────────────────────────────────────


def test_all_approval_statuses_contains_exactly_three():
    """ALL_APPROVAL_STATUSES contains exactly 3 entries."""
    assert len(constants.ALL_APPROVAL_STATUSES) == 3


def test_all_approval_statuses_expected_values():
    """ALL_APPROVAL_STATUSES contains pending, approved, rejected."""
    assert set(constants.ALL_APPROVAL_STATUSES) == {"pending", "approved", "rejected"}


def test_all_approval_statuses_no_duplicates():
    """ALL_APPROVAL_STATUSES has no duplicate values."""
    assert _no_duplicates(constants.ALL_APPROVAL_STATUSES)


def test_approval_status_pending_value():
    """APPROVAL_STATUS_PENDING == 'pending'."""
    assert constants.APPROVAL_STATUS_PENDING == "pending"


def test_approval_status_pending_in_all_approval_statuses():
    """APPROVAL_STATUS_PENDING is in ALL_APPROVAL_STATUSES."""
    assert constants.APPROVAL_STATUS_PENDING in constants.ALL_APPROVAL_STATUSES


# ─── Hit policy constants ─────────────────────────────────────────────────────


def test_all_hit_policies_contains_exactly_four():
    """ALL_HIT_POLICIES contains exactly 4 entries."""
    assert len(constants.ALL_HIT_POLICIES) == 4


def test_all_hit_policies_expected_values():
    """ALL_HIT_POLICIES contains first, collect_all, any_match, unique."""
    assert set(constants.ALL_HIT_POLICIES) == {
        "first",
        "collect_all",
        "any_match",
        "unique",
    }


def test_all_hit_policies_no_duplicates():
    """ALL_HIT_POLICIES has no duplicate values."""
    assert _no_duplicates(constants.ALL_HIT_POLICIES)


def test_hit_policy_first_value():
    """HIT_POLICY_FIRST == 'first'."""
    assert constants.HIT_POLICY_FIRST == "first"


def test_hit_policy_first_in_all_hit_policies():
    """HIT_POLICY_FIRST is in ALL_HIT_POLICIES."""
    assert constants.HIT_POLICY_FIRST in constants.ALL_HIT_POLICIES


# ─── Action type constants ────────────────────────────────────────────────────


def test_all_action_types_contains_exactly_six():
    """ALL_ACTION_TYPES contains exactly 6 entries."""
    assert len(constants.ALL_ACTION_TYPES) == 6


def test_all_action_types_expected_values():
    """ALL_ACTION_TYPES contains the 6 documented action types."""
    assert set(constants.ALL_ACTION_TYPES) == {
        "trigger_workflow",
        "send_email",
        "send_webhook",
        "set_field",
        "add_tag",
        "stop_processing",
    }


def test_all_action_types_no_duplicates():
    """ALL_ACTION_TYPES has no duplicate values."""
    assert _no_duplicates(constants.ALL_ACTION_TYPES)


def test_action_trigger_workflow_value():
    """ACTION_TRIGGER_WORKFLOW == 'trigger_workflow'."""
    assert constants.ACTION_TRIGGER_WORKFLOW == "trigger_workflow"


def test_action_trigger_workflow_in_all_action_types():
    """ACTION_TRIGGER_WORKFLOW is in ALL_ACTION_TYPES."""
    assert constants.ACTION_TRIGGER_WORKFLOW in constants.ALL_ACTION_TYPES


# ─── Event type constants ─────────────────────────────────────────────────────


def test_all_event_types_contains_exactly_seven():
    """ALL_EVENT_TYPES contains exactly 7 entries."""
    assert len(constants.ALL_EVENT_TYPES) == 7


def test_all_event_types_expected_values():
    """ALL_EVENT_TYPES contains the 7 documented event types."""
    assert set(constants.ALL_EVENT_TYPES) == {
        "form_submit",
        "workflow_complete",
        "workflow_fail",
        "webhook",
        "schedule",
        "manual",
        "imap_trigger",
    }


def test_all_event_types_no_duplicates():
    """ALL_EVENT_TYPES has no duplicate values."""
    assert _no_duplicates(constants.ALL_EVENT_TYPES)


def test_event_form_submit_value():
    """EVENT_FORM_SUBMIT == 'form_submit'."""
    assert constants.EVENT_FORM_SUBMIT == "form_submit"


def test_event_form_submit_in_all_event_types():
    """EVENT_FORM_SUBMIT is in ALL_EVENT_TYPES."""
    assert constants.EVENT_FORM_SUBMIT in constants.ALL_EVENT_TYPES


# ─── Operator constants ───────────────────────────────────────────────────────


def test_all_operators_contains_exactly_23():
    """ALL_OPERATORS contains exactly 23 entries."""
    assert len(constants.ALL_OPERATORS) == 23


def test_all_operators_expected_values():
    """ALL_OPERATORS contains the 23 documented operators."""
    assert set(constants.ALL_OPERATORS) == {
        "eq",
        "neq",
        "contains",
        "not_contains",
        "starts_with",
        "ends_with",
        "gt",
        "gte",
        "lt",
        "lte",
        "in",
        "not_in",
        "between",
        "is_empty",
        "is_not_empty",
        "matches_regex",
        "is_true",
        "is_false",
        "date_before",
        "date_after",
        "date_equals",
        "within_last_n_days",
        "older_than_n_days",
    }


def test_all_operators_no_duplicates():
    """ALL_OPERATORS has no duplicate values."""
    assert _no_duplicates(constants.ALL_OPERATORS)


# ─── Cross-reference: named constants are in their lists ─────────────────────


@pytest.mark.parametrize(
    "constant,lst",
    [
        (constants.RULE_TYPE_CONDITION_TREE, constants.ALL_RULE_TYPES),
        (constants.RULE_TYPE_DECISION_TABLE, constants.ALL_RULE_TYPES),
        (constants.RULE_TYPE_JAVASCRIPT, constants.ALL_RULE_TYPES),
        (constants.RULE_STATUS_DRAFT, constants.ALL_RULE_STATUSES),
        (constants.RULE_STATUS_PUBLISHED, constants.ALL_RULE_STATUSES),
        (constants.APPROVAL_STATUS_APPROVED, constants.ALL_APPROVAL_STATUSES),
        (constants.APPROVAL_STATUS_REJECTED, constants.ALL_APPROVAL_STATUSES),
        (constants.HIT_POLICY_COLLECT_ALL, constants.ALL_HIT_POLICIES),
        (constants.HIT_POLICY_ANY_MATCH, constants.ALL_HIT_POLICIES),
        (constants.HIT_POLICY_UNIQUE, constants.ALL_HIT_POLICIES),
        (constants.ACTION_SEND_EMAIL, constants.ALL_ACTION_TYPES),
        (constants.ACTION_SEND_WEBHOOK, constants.ALL_ACTION_TYPES),
        (constants.ACTION_SET_FIELD, constants.ALL_ACTION_TYPES),
        (constants.ACTION_ADD_TAG, constants.ALL_ACTION_TYPES),
        (constants.ACTION_STOP_PROCESSING, constants.ALL_ACTION_TYPES),
        (constants.EVENT_WORKFLOW_COMPLETE, constants.ALL_EVENT_TYPES),
        (constants.EVENT_WORKFLOW_FAIL, constants.ALL_EVENT_TYPES),
        (constants.EVENT_WEBHOOK, constants.ALL_EVENT_TYPES),
        (constants.EVENT_SCHEDULE, constants.ALL_EVENT_TYPES),
        (constants.EVENT_MANUAL, constants.ALL_EVENT_TYPES),
        (constants.EVENT_IMAP_TRIGGER, constants.ALL_EVENT_TYPES),
    ],
)
def test_named_constant_is_in_its_list(constant, lst):
    """Each named constant is a member of its corresponding list."""
    assert constant in lst
