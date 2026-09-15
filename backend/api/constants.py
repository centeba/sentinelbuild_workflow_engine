"""
Central string constants for the Mit Stack platform.

Every enum-like value that appears in model defaults, router logic, or
service code should be defined here and imported from here — never
repeated as an inline string literal in multiple places.
"""

# ── User roles ─────────────────────────────────────────────────────────────────

ROLE_ADMIN = "admin"
ROLE_MEMBER = "member"
ROLE_VIEWER = "viewer"

# SentinelBuild canonical roles (from User Master JWT)
ROLE_SYSTEM_ADMIN = "system_admin"
ROLE_COMPANY_ADMIN = "company_admin"
ROLE_PLATFORM_ADMIN = "platform_admin"  # legacy alias for system_admin

ALL_ROLES = [
    ROLE_ADMIN,
    ROLE_MEMBER,
    ROLE_VIEWER,
    ROLE_SYSTEM_ADMIN,
    ROLE_COMPANY_ADMIN,
]

# ── Execution statuses ─────────────────────────────────────────────────────────

EXEC_STATUS_PENDING = "pending"
EXEC_STATUS_RUNNING = "running"
EXEC_STATUS_COMPLETED = "completed"
EXEC_STATUS_FAILED = "failed"
EXEC_STATUS_CANCELLED = "cancelled"

ALL_EXEC_STATUSES = [
    EXEC_STATUS_PENDING,
    EXEC_STATUS_RUNNING,
    EXEC_STATUS_COMPLETED,
    EXEC_STATUS_FAILED,
    EXEC_STATUS_CANCELLED,
]

# Node-execution has an extra "skipped" state
NODE_EXEC_STATUS_PENDING = "pending"
NODE_EXEC_STATUS_RUNNING = "running"
NODE_EXEC_STATUS_COMPLETED = "completed"
NODE_EXEC_STATUS_FAILED = "failed"
NODE_EXEC_STATUS_SKIPPED = "skipped"

# ── Trigger types ──────────────────────────────────────────────────────────────

TRIGGER_MANUAL = "manual"
TRIGGER_WEBHOOK = "webhook"
TRIGGER_CRON = "cron"
TRIGGER_FORM = "form"
TRIGGER_IMAP = "imap_trigger"

ALL_TRIGGER_TYPES = [
    TRIGGER_MANUAL,
    TRIGGER_WEBHOOK,
    TRIGGER_CRON,
    TRIGGER_FORM,
    TRIGGER_IMAP,
]

# ── Workflow approval statuses ─────────────────────────────────────────────────
# (for the wait_approval node inside a workflow execution)

WORKFLOW_APPROVAL_PENDING = "pending"
WORKFLOW_APPROVAL_APPROVED = "approved"
WORKFLOW_APPROVAL_REJECTED = "rejected"
WORKFLOW_APPROVAL_TIMEOUT = "timeout"

ALL_WORKFLOW_APPROVAL_STATUSES = [
    WORKFLOW_APPROVAL_PENDING,
    WORKFLOW_APPROVAL_APPROVED,
    WORKFLOW_APPROVAL_REJECTED,
    WORKFLOW_APPROVAL_TIMEOUT,
]

# ── Workflow version statuses ─────────────────────────────────────────────────

WF_VERSION_DRAFT = "draft"
WF_VERSION_ACTIVE = "active"
WF_VERSION_ARCHIVED = "archived"

ALL_WF_VERSION_STATUSES = [WF_VERSION_DRAFT, WF_VERSION_ACTIVE, WF_VERSION_ARCHIVED]

# ── Rule types ─────────────────────────────────────────────────────────────────

RULE_TYPE_CONDITION_TREE = "condition_tree"
RULE_TYPE_DECISION_TABLE = "decision_table"
RULE_TYPE_JAVASCRIPT = "javascript"

ALL_RULE_TYPES = [
    RULE_TYPE_CONDITION_TREE,
    RULE_TYPE_DECISION_TABLE,
    RULE_TYPE_JAVASCRIPT,
]

# ── Rule statuses ──────────────────────────────────────────────────────────────

RULE_STATUS_DRAFT = "draft"
RULE_STATUS_PUBLISHED = "published"

ALL_RULE_STATUSES = [RULE_STATUS_DRAFT, RULE_STATUS_PUBLISHED]

# ── Rule approval statuses ─────────────────────────────────────────────────────

APPROVAL_STATUS_PENDING = "pending"
APPROVAL_STATUS_APPROVED = "approved"
APPROVAL_STATUS_REJECTED = "rejected"

ALL_APPROVAL_STATUSES = [
    APPROVAL_STATUS_PENDING,
    APPROVAL_STATUS_APPROVED,
    APPROVAL_STATUS_REJECTED,
]

# ── Decision-table hit policies ────────────────────────────────────────────────

HIT_POLICY_FIRST = "first"
HIT_POLICY_COLLECT_ALL = "collect_all"
HIT_POLICY_ANY_MATCH = "any_match"
HIT_POLICY_UNIQUE = "unique"

ALL_HIT_POLICIES = [
    HIT_POLICY_FIRST,
    HIT_POLICY_COLLECT_ALL,
    HIT_POLICY_ANY_MATCH,
    HIT_POLICY_UNIQUE,
]

# ── Rule action types ──────────────────────────────────────────────────────────

ACTION_TRIGGER_WORKFLOW = "trigger_workflow"
ACTION_SEND_EMAIL = "send_email"
ACTION_SEND_WEBHOOK = "send_webhook"
ACTION_SET_FIELD = "set_field"
ACTION_ADD_TAG = "add_tag"
ACTION_STOP_PROCESSING = "stop_processing"

ALL_ACTION_TYPES = [
    ACTION_TRIGGER_WORKFLOW,
    ACTION_SEND_EMAIL,
    ACTION_SEND_WEBHOOK,
    ACTION_SET_FIELD,
    ACTION_ADD_TAG,
    ACTION_STOP_PROCESSING,
]

# ── Trigger event types (used in rules' trigger_events field) ──────────────────

EVENT_FORM_SUBMIT = "form_submit"
EVENT_WORKFLOW_COMPLETE = "workflow_complete"
EVENT_WORKFLOW_FAIL = "workflow_fail"
EVENT_WEBHOOK = "webhook"
EVENT_SCHEDULE = "schedule"
EVENT_MANUAL = "manual"
EVENT_IMAP_TRIGGER = "imap_trigger"

ALL_EVENT_TYPES = [
    EVENT_FORM_SUBMIT,
    EVENT_WORKFLOW_COMPLETE,
    EVENT_WORKFLOW_FAIL,
    EVENT_WEBHOOK,
    EVENT_SCHEDULE,
    EVENT_MANUAL,
    EVENT_IMAP_TRIGGER,
]

# ── Condition operators ────────────────────────────────────────────────────────

OP_EQ = "eq"
OP_NEQ = "neq"
OP_CONTAINS = "contains"
OP_NOT_CONTAINS = "not_contains"
OP_STARTS_WITH = "starts_with"
OP_ENDS_WITH = "ends_with"
OP_GT = "gt"
OP_GTE = "gte"
OP_LT = "lt"
OP_LTE = "lte"
OP_IN = "in"
OP_NOT_IN = "not_in"
OP_BETWEEN = "between"
OP_IS_EMPTY = "is_empty"
OP_IS_NOT_EMPTY = "is_not_empty"
OP_MATCHES_REGEX = "matches_regex"
OP_IS_TRUE = "is_true"
OP_IS_FALSE = "is_false"
OP_DATE_BEFORE = "date_before"
OP_DATE_AFTER = "date_after"
OP_DATE_EQUALS = "date_equals"
OP_WITHIN_LAST_N_DAYS = "within_last_n_days"
OP_OLDER_THAN_N_DAYS = "older_than_n_days"

ALL_OPERATORS = [
    OP_EQ,
    OP_NEQ,
    OP_CONTAINS,
    OP_NOT_CONTAINS,
    OP_STARTS_WITH,
    OP_ENDS_WITH,
    OP_GT,
    OP_GTE,
    OP_LT,
    OP_LTE,
    OP_IN,
    OP_NOT_IN,
    OP_BETWEEN,
    OP_IS_EMPTY,
    OP_IS_NOT_EMPTY,
    OP_MATCHES_REGEX,
    OP_IS_TRUE,
    OP_IS_FALSE,
    OP_DATE_BEFORE,
    OP_DATE_AFTER,
    OP_DATE_EQUALS,
    OP_WITHIN_LAST_N_DAYS,
    OP_OLDER_THAN_N_DAYS,
]
