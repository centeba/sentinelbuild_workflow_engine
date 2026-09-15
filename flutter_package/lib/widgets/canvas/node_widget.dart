import 'package:flutter/material.dart';
import '../../models/workflow_node.dart';

/// A draggable workflow node card rendered on the canvas.
class NodeWidget extends StatelessWidget {
  final WorkflowNode node;
  final bool isSelected;
  final VoidCallback onTap;
  final void Function(Offset delta) onDragUpdate;
  final VoidCallback onStartEdge;
  final VoidCallback onEndEdge;
  final VoidCallback onDelete;
  /// Pinned output from the last execution — shown as a badge when non-null.
  final Map<String, dynamic>? pinnedOutput;

  const NodeWidget({
    super.key,
    required this.node,
    required this.isSelected,
    required this.onTap,
    required this.onDragUpdate,
    required this.onStartEdge,
    required this.onEndEdge,
    required this.onDelete,
    this.pinnedOutput,
  });

  @override
  Widget build(BuildContext context) {
    final meta = NodeTypeMeta.forType(node.type);
    return GestureDetector(
      onTap: onTap,
      onPanUpdate: (details) => onDragUpdate(details.delta),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Container(
          width: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF6366F1) : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Node header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: meta.color.withOpacity(0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                ),
                child: Row(
                  children: [
                    Icon(meta.icon, size: 16, color: meta.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        nodeDisplayName(node, meta),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: meta.color,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: onDelete,
                      child: Icon(Icons.close, size: 14, color: meta.color.withOpacity(0.6)),
                    ),
                  ],
                ),
              ),
              // Node type label
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      meta.label,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              // Pinned output badge
              if (pinnedOutput != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF064E3B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.push_pin, size: 10, color: Color(0xFF22C55E)),
                    const SizedBox(width: 4),
                    const Text('Last output pinned',
                        style: TextStyle(fontSize: 10, color: Color(0xFF86EFAC))),
                  ]),
                ),
              // Connection ports. Each 12px dot gets a ~36px opaque
              // hit target so clicks land reliably and beat the card's
              // pan/select gesture (HitTestBehavior.opaque makes the
              // port win hit-testing over the parent in its region).
              Padding(
                padding: const EdgeInsets.only(bottom: 2, left: 4, right: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Input port (left) — tap to FINISH a connection here.
                    if (!node.type.endsWith('_trigger'))
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onEndEdge,
                        child: Tooltip(
                          message: 'Click to connect an incoming arrow here',
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _Port(color: meta.color, isInput: true),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 36),
                    // Output port (right) — tap to START a connection.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => onStartEdge(),
                      onTapUp: (_) {},
                      child: Tooltip(
                        message: 'Click to start an arrow from here',
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _Port(color: meta.color, isInput: false),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Port extends StatelessWidget {
  final Color color;
  final bool isInput;

  const _Port({required this.color, required this.isInput});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color, width: 2),
        shape: BoxShape.circle,
      ),
    );
  }
}

// ── Node type metadata ────────────────────────────────────────────────────────

class NodeTypeMeta {
  final String label;
  final IconData icon;
  final Color color;

  const NodeTypeMeta({required this.label, required this.icon, required this.color});

  static const _map = <String, NodeTypeMeta>{
    // Triggers
    'webhook_trigger': NodeTypeMeta(label: 'Webhook', icon: Icons.webhook, color: Color(0xFF6366F1)),
    'cron_trigger': NodeTypeMeta(label: 'Cron', icon: Icons.schedule, color: Color(0xFF6366F1)),
    'manual_trigger': NodeTypeMeta(label: 'Manual', icon: Icons.play_circle_outline, color: Color(0xFF6366F1)),
    'form_trigger': NodeTypeMeta(label: 'Form Submit', icon: Icons.dynamic_form_outlined, color: Color(0xFF6366F1)),
    'imap_trigger': NodeTypeMeta(label: 'Email (IMAP)', icon: Icons.mark_email_unread_outlined, color: Color(0xFF6366F1)),
    // Core actions
    'http_request': NodeTypeMeta(label: 'HTTP Request', icon: Icons.http, color: Color(0xFF0EA5E9)),
    'web_scraper': NodeTypeMeta(label: 'Web Scraper', icon: Icons.travel_explore, color: Color(0xFF8B5CF6)),
    // Logic
    'transform': NodeTypeMeta(label: 'Transform', icon: Icons.transform, color: Color(0xFF10B981)),
    'if_condition': NodeTypeMeta(label: 'If / Else', icon: Icons.alt_route, color: Color(0xFFF59E0B)),
    'switch': NodeTypeMeta(label: 'Switch', icon: Icons.device_hub, color: Color(0xFFF59E0B)),
    'for_each': NodeTypeMeta(label: 'For Each', icon: Icons.loop, color: Color(0xFF0EA5E9)),
    'merge': NodeTypeMeta(label: 'Merge', icon: Icons.merge_type, color: Color(0xFF8B5CF6)),
    'run_code': NodeTypeMeta(label: 'Code', icon: Icons.code, color: Color(0xFFEC4899)),
    'delay': NodeTypeMeta(label: 'Delay', icon: Icons.hourglass_empty, color: Color(0xFF9CA3AF)),
    // Approval / Orchestration
    'wait_approval': NodeTypeMeta(label: 'Wait for Approval', icon: Icons.approval_outlined, color: Color(0xFFD97706)),
    'call_workflow': NodeTypeMeta(label: 'Call Workflow', icon: Icons.account_tree_outlined, color: Color(0xFF6366F1)),
    // Automate (Rules / Decision Tables) — see node_palette "Automate" group.
    // Decision Tables are a *rule_type*, not a separate workflow node: create a
    // rule with rule_type=decision_table, then drop an Evaluate Rules node here
    // pointed at the matching event_type.
    'evaluate_rules': NodeTypeMeta(label: 'Evaluate Rules', icon: Icons.rule_outlined, color: Color(0xFF14B8A6)),
    // Database
    'db_query': NodeTypeMeta(label: 'DB Query', icon: Icons.storage, color: Color(0xFF6B7280)),
    // Email
    'send_email': NodeTypeMeta(label: 'SMTP Email', icon: Icons.email_outlined, color: Color(0xFFEF4444)),
    'gmail_send': NodeTypeMeta(label: 'Gmail Send', icon: Icons.mark_email_read_outlined, color: Color(0xFFEA4335)),
    'gmail_read': NodeTypeMeta(label: 'Gmail Read', icon: Icons.inbox_outlined, color: Color(0xFFEA4335)),
    'outlook_send': NodeTypeMeta(label: 'Outlook Send', icon: Icons.forward_to_inbox_outlined, color: Color(0xFF0078D4)),
    'outlook_read': NodeTypeMeta(label: 'Outlook Read', icon: Icons.mail_outline, color: Color(0xFF0078D4)),
    // Cloud storage
    's3': NodeTypeMeta(label: 'AWS S3', icon: Icons.cloud_upload_outlined, color: Color(0xFFFF9900)),
    'google_drive': NodeTypeMeta(label: 'Google Drive', icon: Icons.drive_folder_upload_outlined, color: Color(0xFF1FA463)),
    // Spreadsheets
    'excel_read': NodeTypeMeta(label: 'Excel Read', icon: Icons.table_chart_outlined, color: Color(0xFF217346)),
    'excel_write': NodeTypeMeta(label: 'Excel Write', icon: Icons.table_rows_outlined, color: Color(0xFF217346)),
    // AI
    'claude_llm': NodeTypeMeta(label: 'Claude AI (legacy)', icon: Icons.auto_awesome_outlined, color: Color(0xFFD97757)),
    'agent_node': NodeTypeMeta(label: 'Run Agent', icon: Icons.smart_toy_outlined, color: Color(0xFF10B981)),
    // ``tool_node`` invokes a single registered skill (Python tool or
    // prompt-skill) — the palette's dynamic TOOLS section drops these
    // pre-populated with ``skill_name``.
    'tool_node': NodeTypeMeta(label: 'Tool', icon: Icons.handyman_outlined, color: Color(0xFF14B8A6)),
    // Multi-agent orchestration — config carries an AgentGraphSpec JSON
    // dispatched by ``run_agent_graph_node`` (depth ≤ MAX_DEPTH=3).
    'agent_graph_node': NodeTypeMeta(label: 'Agent Graph', icon: Icons.account_tree_outlined, color: Color(0xFF8B5CF6)),
    // Payments
    'stripe': NodeTypeMeta(label: 'Stripe', icon: Icons.payment_outlined, color: Color(0xFF635BFF)),
    // Marketing
    'mailchimp': NodeTypeMeta(label: 'Mailchimp', icon: Icons.campaign_outlined, color: Color(0xFFFFE01B)),
    // Pack-contributed domain nodes (restoration etc.). The specific
    // event/action name comes from config.node_key — see
    // nodeDisplayName() — so these are just the base icon/colour.
    'pack_trigger': NodeTypeMeta(label: 'Trigger', icon: Icons.sensors, color: Color(0xFF00C2B2)),
    'pack_action': NodeTypeMeta(label: 'Action', icon: Icons.bolt, color: Color(0xFF00C2B2)),
  };

  static NodeTypeMeta forType(String type) =>
      _map[type] ?? const NodeTypeMeta(label: 'Node', icon: Icons.circle_outlined, color: Color(0xFF9CA3AF));
}

/// Human label for a node card. Priority:
///   1. an explicit ``node.name`` the author set,
///   2. the pack node's ``event_type``/``node_key`` prettified
///      (e.g. ``restoration.project_created`` → "Project created"),
///   3. the static type label (``meta.label``).
String nodeDisplayName(WorkflowNode node, NodeTypeMeta meta) {
  if (node.name.isNotEmpty) return node.name;
  final cfg = node.config;
  final raw = cfg['event_type'] ?? cfg['node_key'];
  if (raw is String && raw.isNotEmpty) {
    final tail = raw.contains('.') ? raw.split('.').last : raw;
    final words = tail.replaceAll('_', ' ').trim();
    if (words.isNotEmpty) {
      return words[0].toUpperCase() + words.substring(1);
    }
  }
  return meta.label;
}
