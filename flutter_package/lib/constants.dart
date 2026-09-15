import 'package:flutter/material.dart';

/// Central constants for the Mit Stack Flutter app.
///
/// All enum-like string values (rule types, statuses, operators, event types,
/// action types) are defined here and imported from here — never repeated
/// as inline string literals in multiple places.
///
/// Keep these in sync with `backend/api/constants.py`.

// ── User roles ─────────────────────────────────────────────────────────────────

const kRoleAdmin = 'admin';
const kRoleMember = 'member';
const kRoleViewer = 'viewer';

// ── Rule types ─────────────────────────────────────────────────────────────────

const kRuleTypeConditionTree = 'condition_tree';
const kRuleTypeDecisionTable = 'decision_table';
const kRuleTypeJavaScript = 'javascript';

// ── Rule statuses ──────────────────────────────────────────────────────────────

const kRuleStatusDraft = 'draft';
const kRuleStatusPublished = 'published';

// ── Approval statuses ──────────────────────────────────────────────────────────

const kApprovalStatusPending = 'pending';
const kApprovalStatusApproved = 'approved';
const kApprovalStatusRejected = 'rejected';

// ── Decision-table hit policies ────────────────────────────────────────────────

const kHitPolicyFirst = 'first';
const kHitPolicyCollectAll = 'collect_all';
const kHitPolicyAnyMatch = 'any_match';
const kHitPolicyUnique = 'unique';

/// Ordered list used in the hit-policy dropdown.
/// Each map: {'value': String, 'label': String, 'desc': String}
const kHitPolicies = <Map<String, String>>[
  {'value': kHitPolicyFirst,      'label': 'First match',  'desc': 'Stop at the first matching row (default)'},
  {'value': kHitPolicyCollectAll, 'label': 'Collect all',  'desc': 'Execute all matching rows, merge outputs'},
  {'value': kHitPolicyAnyMatch,   'label': 'Any match',    'desc': 'Return true/false only — no actions fired'},
  {'value': kHitPolicyUnique,     'label': 'Unique',       'desc': 'Error if two rows produce the same output field'},
];

// ── Trigger event types ────────────────────────────────────────────────────────

const kEventFormSubmit = 'form_submit';
const kEventWorkflowComplete = 'workflow_complete';
const kEventWorkflowFail = 'workflow_fail';
const kEventWebhook = 'webhook';
const kEventSchedule = 'schedule';
const kEventManual = 'manual';
const kEventImapTrigger = 'imap_trigger';

/// Ordered list used in the trigger-events chip selector.
/// Each map: {'value': String, 'label': String}
const kTriggerEvents = <Map<String, String>>[
  {'value': kEventFormSubmit,       'label': 'Form Submitted'},
  {'value': kEventWorkflowComplete, 'label': 'Workflow Completed'},
  {'value': kEventWorkflowFail,     'label': 'Workflow Failed'},
  {'value': kEventWebhook,          'label': 'Webhook Received'},
  {'value': kEventSchedule,         'label': 'Scheduled'},
  {'value': kEventManual,           'label': 'Manual Trigger'},
];

// ── Condition operators ────────────────────────────────────────────────────────

const kOpEq = 'eq';
const kOpNeq = 'neq';
const kOpContains = 'contains';
const kOpNotContains = 'not_contains';
const kOpStartsWith = 'starts_with';
const kOpEndsWith = 'ends_with';
const kOpGt = 'gt';
const kOpGte = 'gte';
const kOpLt = 'lt';
const kOpLte = 'lte';
const kOpIn = 'in';
const kOpNotIn = 'not_in';
const kOpBetween = 'between';
const kOpIsEmpty = 'is_empty';
const kOpIsNotEmpty = 'is_not_empty';
const kOpMatchesRegex = 'matches_regex';
const kOpIsTrue = 'is_true';
const kOpIsFalse = 'is_false';
const kOpDateBefore = 'date_before';
const kOpDateAfter = 'date_after';
const kOpDateEquals = 'date_equals';
const kOpWithinLastNDays = 'within_last_n_days';
const kOpOlderThanNDays = 'older_than_n_days';

/// Ordered list used in the condition operator dropdown.
/// Each map: {'value': String, 'label': String}
const kOperators = <Map<String, String>>[
  {'value': kOpEq,             'label': '= equals'},
  {'value': kOpNeq,            'label': '≠ not equals'},
  {'value': kOpContains,       'label': 'contains'},
  {'value': kOpNotContains,    'label': 'does not contain'},
  {'value': kOpStartsWith,     'label': 'starts with'},
  {'value': kOpEndsWith,       'label': 'ends with'},
  {'value': kOpGt,             'label': '> greater than'},
  {'value': kOpGte,            'label': '≥ greater or equal'},
  {'value': kOpLt,             'label': '< less than'},
  {'value': kOpLte,            'label': '≤ less or equal'},
  {'value': kOpIn,             'label': 'in list (comma-separated)'},
  {'value': kOpNotIn,          'label': 'not in list'},
  {'value': kOpBetween,        'label': 'between (min,max)'},
  {'value': kOpIsEmpty,        'label': 'is empty'},
  {'value': kOpIsNotEmpty,     'label': 'is not empty'},
  {'value': kOpMatchesRegex,   'label': 'matches regex'},
  {'value': kOpIsTrue,         'label': 'is true'},
  {'value': kOpIsFalse,        'label': 'is false'},
  // ── Date/time ───────────────────────────────────────────────────────────────
  {'value': kOpDateBefore,        'label': 'date is before'},
  {'value': kOpDateAfter,         'label': 'date is after'},
  {'value': kOpDateEquals,        'label': 'date equals'},
  {'value': kOpWithinLastNDays,   'label': 'within last N days'},
  {'value': kOpOlderThanNDays,    'label': 'older than N days'},
];

// ── Rule action types ──────────────────────────────────────────────────────────

const kActionTriggerWorkflow = 'trigger_workflow';
const kActionSendEmail = 'send_email';
const kActionSendWebhook = 'send_webhook';
const kActionSetField = 'set_field';
const kActionAddTag = 'add_tag';
const kActionStopProcessing = 'stop_processing';

/// Ordered list used in the action type dropdown.
/// Each map: {'value': String, 'label': String, 'icon': IconData}
const kActionTypes = <Map<String, Object>>[
  {'value': kActionTriggerWorkflow, 'label': 'Trigger Workflow',  'icon': Icons.account_tree_outlined},
  {'value': kActionSendEmail,       'label': 'Send Email',        'icon': Icons.email_outlined},
  {'value': kActionSendWebhook,     'label': 'Send Webhook',      'icon': Icons.webhook},
  {'value': kActionSetField,        'label': 'Set Field Value',   'icon': Icons.edit_outlined},
  {'value': kActionAddTag,          'label': 'Add Tag',           'icon': Icons.label_outlined},
  {'value': kActionStopProcessing,  'label': 'Stop Processing',   'icon': Icons.block},
];
