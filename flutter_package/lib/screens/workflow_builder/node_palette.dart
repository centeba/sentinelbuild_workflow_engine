import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mit_stack/mit_stack.dart' show aiAdminApiProvider;
import '../../i18n/translate_extension.dart';
import '../../widgets/canvas/node_widget.dart';
import '../../theme.dart';
import 'node_type_registry.dart';

/// Sidebar of draggable workflow nodes.
///
/// Static groups (Triggers, Actions, …) are hardcoded; the **TOOLS**
/// group is hydrated at runtime from
/// ``GET /ai-skills?active=true`` so any skill registered (built-in or
/// host-defined) shows up automatically. Tapping a tool drops a
/// ``tool_node`` pre-populated with ``skill_name`` so the workflow
/// executor knows which skill to invoke without further config.
class NodePalette extends ConsumerStatefulWidget {
  /// Receives the new node's type plus an optional initial config map
  /// (used for tool nodes to pre-fill ``skill_name``).
  final void Function(String type, [Map<String, dynamic>? initialConfig])
      onNodeSelected;
  const NodePalette({super.key, required this.onNodeSelected});

  @override
  ConsumerState<NodePalette> createState() => _NodePaletteState();
}

class _NodePaletteState extends ConsumerState<NodePalette> {
  // Group ``name`` is now a translation key — resolved at render time.
  static const _staticGroups = [
    _Group('node_palette.group.triggers',     ['webhook_trigger', 'cron_trigger', 'manual_trigger', 'form_trigger', 'imap_trigger']),
    _Group('node_palette.group.actions',      ['http_request', 'web_scraper', 'db_query']),
    _Group('node_palette.group.logic',        ['if_condition', 'domain_condition', 'switch', 'for_each', 'merge', 'transform', 'run_code', 'delay']),
    _Group('node_palette.group.automate',     ['evaluate_rules']),
    _Group('node_palette.group.approval',     ['wait_approval', 'call_workflow']),
    _Group('node_palette.group.email',        ['send_email', 'gmail_send', 'gmail_read', 'outlook_send', 'outlook_read']),
    _Group('node_palette.group.storage',      ['s3', 'google_drive']),
    _Group('node_palette.group.spreadsheets', ['excel_read', 'excel_write']),
    // ``agent_node`` replaces the old ``claude_llm`` palette entry. It's
    // configured with an ``agent_id`` (lookup of an AIAgentConfig); the
    // model + system prompt + skills come from that config.
    _Group('node_palette.group.ai',           ['agent_node', 'agent_graph_node']),
    _Group('node_palette.group.payments',     ['stripe']),
    _Group('node_palette.group.marketing',    ['mailchimp']),
  ];

  /// Active skills loaded from the AI admin API. Each becomes a
  /// draggable ``tool_node`` that pre-fills ``skill_name`` on drop.
  List<_SkillEntry> _tools = const [];
  bool _toolsLoading = true;
  Object? _toolsError;

  @override
  void initState() {
    super.initState();
    _loadTools();
  }

  Future<void> _loadTools() async {
    try {
      final api = ref.read(aiAdminApiProvider);
      final rows = await api.listSkills(activeOnly: true);
      if (!mounted) return;
      setState(() {
        _tools = [
          for (final r in rows)
            // Only ``python_tool`` skills are directly callable as a workflow
            // step. ``prompt`` skills are prompt fragments that only make
            // sense inside an agent's reasoning loop, and a skill flagged
            // ``agent_only`` is explicitly excluded from the palette. Both are
            // still usable via an Agent node's attached-skills allow-list.
            if ((r['kind'] ?? 'prompt') == 'python_tool' &&
                (r['agent_only'] != true))
              _SkillEntry(
                name: (r['name'] ?? '') as String,
                label: (r['label'] ?? r['name'] ?? '') as String,
                modality: (r['modality'] ?? 'any') as String,
              ),
        ]..sort((a, b) => a.label.compareTo(b.label));
        _toolsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Non-fatal — palette stays usable without dynamic tools.
      setState(() {
        _toolsError = e;
        _toolsLoading = false;
      });
    }
  }

  /// Render pack-contributed palette groups from the node-type
  /// registry. Each group lists its declared trigger + action keys;
  /// items use the pack-supplied label_key + icon. The whole block
  /// silently collapses to nothing when the registry endpoint
  /// errors or returns no pack contributions — the static built-in
  /// groups below this still render.
  List<Widget> _buildPackGroups(BuildContext context) {
    final async = ref.watch(nodeTypeRegistryProvider);
    return async.when(
      loading: () => const [],
      error: (_, __) => const [],
      data: (registry) {
        if (registry.packGroups.isEmpty &&
            registry.packTriggers.isEmpty &&
            registry.packActions.isEmpty) {
          return const [];
        }

        final children = <Widget>[];
        // Render each declared group with its members in order.
        for (final group in registry.packGroups) {
          final triggerKeys = List<String>.from(
            (group['trigger_keys'] as List? ?? const [])
                .map((e) => e.toString()),
          );
          final actionKeys = List<String>.from(
            (group['action_keys'] as List? ?? const [])
                .map((e) => e.toString()),
          );
          final labelKey = (group['label_key'] as String?) ?? group['key'];

          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
            child: Text(
              context.t(labelKey).toUpperCase(),
              style: AppTheme.sectionLabel,
            ),
          ));

          for (final key in [...triggerKeys, ...actionKeys]) {
            final spec = registry.lookup(key);
            if (spec == null) continue;
            final label = context.t(
              (spec['label_key'] as String?) ?? key,
            );
            children.add(_PaletteItem(
              // Pack-contributed entries reuse the generic
              // `pack_trigger` / `pack_action` runtime types; the
              // domain identity is carried in the `node_key`
              // initialConfig field.
              type: registry.packTriggers
                      .any((t) => t['key'] == key)
                  ? 'pack_trigger'
                  : 'pack_action',
              labelOverride: label,
              onTap: () => widget.onNodeSelected(
                registry.packTriggers
                        .any((t) => t['key'] == key)
                    ? 'pack_trigger'
                    : 'pack_action',
                {'node_key': key},
              ),
            ));
          }
        }
        return children;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      color: AppTheme.bgRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(context.t('node_palette.title'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                // Pack-contributed groups render first so domain-flavored
                // entries (e.g. a "Restoration" group with "When project
                // is created" trigger) appear above generic platform
                // groups. Falls back to static groups only when the
                // registry endpoint is unreachable.
                ..._buildPackGroups(context),
                for (final group in _staticGroups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                    child: Text(context.t(group.name).toUpperCase(),
                        style: AppTheme.sectionLabel),
                  ),
                  for (final type in group.types)
                    _PaletteItem(
                      type: type,
                      onTap: () => widget.onNodeSelected(type),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                  child: Text(context.t('node_palette.group.tools').toUpperCase(),
                      style: AppTheme.sectionLabel),
                ),
                if (_toolsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: SizedBox(
                      height: 14, width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_toolsError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(context.t('node_palette.failed_load_tools'),
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  )
                else if (_tools.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(context.t('node_palette.no_active_skills'),
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  )
                else
                  for (final t in _tools)
                    _PaletteItem(
                      type: 'tool_node',
                      labelOverride: t.label,
                      onTap: () => widget.onNodeSelected(
                        'tool_node',
                        {'skill_name': t.name},
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteItem extends StatelessWidget {
  final String type;
  final String? labelOverride;
  final VoidCallback onTap;
  const _PaletteItem({required this.type, required this.onTap, this.labelOverride});

  @override
  Widget build(BuildContext context) {
    final meta = NodeTypeMeta.forType(type);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Row(children: [
          Icon(meta.icon, size: 14, color: meta.color),
          const SizedBox(width: 8),
          Expanded(child: Text(labelOverride ?? meta.label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary))),
          const Icon(Icons.add, size: 14, color: AppTheme.textMuted),
        ]),
      ),
    );
  }
}

class _Group {
  final String name;
  final List<String> types;
  const _Group(this.name, this.types);
}

class _SkillEntry {
  final String name;
  final String label;
  final String modality;
  const _SkillEntry({required this.name, required this.label, required this.modality});
}
