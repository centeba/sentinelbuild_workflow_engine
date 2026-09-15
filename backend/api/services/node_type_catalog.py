"""Built-in workflow-builder node types — single source of truth.

Mirrors the static palette groups historically declared in
``frontend/mit_stack/lib/screens/workflow_builder/node_palette.dart``
so the new ``GET /api/v1/node-types/registry`` endpoint can merge
built-ins with pack-contributed entries without the frontend having
to do its own merge.

The frontend will eventually drop ``_staticGroups`` and read this
catalog through the registry endpoint, but until that switch lands
the two lists must stay in sync. The Dart-side comment in
``node_palette.dart`` cross-references this file.
"""

from __future__ import annotations

from typing import Any

# Built-in node groups in display order. Each entry uses i18n
# label_keys identical to those the Flutter palette already
# references — that means no translation duplication when the
# Flutter side switches to consuming this list.
BUILTIN_GROUPS: list[dict[str, Any]] = [
    {
        "key": "triggers",
        "label_key": "node_palette.group.triggers",
        "node_keys": [
            "webhook_trigger",
            "cron_trigger",
            "manual_trigger",
            "form_trigger",
            "imap_trigger",
        ],
    },
    {
        "key": "actions",
        "label_key": "node_palette.group.actions",
        "node_keys": ["http_request", "web_scraper", "db_query"],
    },
    {
        "key": "logic",
        "label_key": "node_palette.group.logic",
        "node_keys": [
            "if_condition",
            "domain_condition",
            "switch",
            "for_each",
            "merge",
            "transform",
            "run_code",
            "delay",
        ],
    },
    {
        "key": "automate",
        "label_key": "node_palette.group.automate",
        "node_keys": ["evaluate_rules"],
    },
    {
        "key": "approval",
        "label_key": "node_palette.group.approval",
        "node_keys": ["wait_approval", "call_workflow"],
    },
    {
        "key": "email",
        "label_key": "node_palette.group.email",
        "node_keys": [
            "send_email",
            "gmail_send",
            "gmail_read",
            "outlook_send",
            "outlook_read",
        ],
    },
    {
        "key": "storage",
        "label_key": "node_palette.group.storage",
        "node_keys": ["s3", "google_drive"],
    },
    {
        "key": "spreadsheets",
        "label_key": "node_palette.group.spreadsheets",
        "node_keys": ["excel_read", "excel_write"],
    },
    {
        "key": "ai",
        "label_key": "node_palette.group.ai",
        "node_keys": ["agent_node", "agent_graph_node"],
    },
    {
        "key": "payments",
        "label_key": "node_palette.group.payments",
        "node_keys": ["stripe"],
    },
    {
        "key": "marketing",
        "label_key": "node_palette.group.marketing",
        "node_keys": ["mailchimp"],
    },
]


# Built-in node types with minimal schema metadata. ``config_schema``
# is kept empty for built-ins because the Flutter side already
# renders hand-tuned config forms for these — the registry exposes
# just enough info (label + group membership) so the palette can
# render the entry. Pack contributions DO ship JSON Schemas because
# they drive a fully schema-driven config form.
def builtin_node_types() -> list[dict[str, Any]]:
    """Flat list of every built-in node type, with the group key
    each one belongs to so the registry response can be sliced
    either way. The flattening is cached at module-load time."""
    out: list[dict[str, Any]] = []
    for group in BUILTIN_GROUPS:
        for node_key in group["node_keys"]:
            out.append(
                {
                    "key": node_key,
                    "label_key": f"node_palette.node.{node_key}",
                    "group_key": group["key"],
                    "kind": _kind_for(node_key),
                    "is_builtin": True,
                }
            )
    return out


def _kind_for(node_key: str) -> str:
    """Categorise built-in keys as trigger / action / logic. Used by
    the frontend for icon defaulting and edge-port colouring."""
    if node_key.endswith("_trigger"):
        return "trigger"
    if node_key in {
        "if_condition",
        "domain_condition",
        "switch",
        "for_each",
        "merge",
        "transform",
        "run_code",
        "delay",
    }:
        return "logic"
    if node_key in {"wait_approval", "call_workflow", "evaluate_rules"}:
        return "approval"
    return "action"
