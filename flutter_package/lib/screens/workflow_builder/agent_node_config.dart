import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/ai_api.dart' show aiAdminApiProvider;

import '../../i18n/translate_extension.dart';
import '../../theme.dart';

/// Phase-B richer ``agent_node`` config form.
///
/// The plan called for an agent **dropdown** (sourced from
/// ``/ai-agents``) plus read-only chips of attached skills, so
/// workflow authors don't have to copy UUIDs out of the AI Admin
/// page. Used in [NodeConfigPanel] when the selected node is an
/// ``agent_node``; the surrounding panel still owns the ``input``
/// field plus save semantics.
class AgentNodeConfig extends ConsumerStatefulWidget {
  /// Current selected agent id ("" = none).
  final String agentId;

  /// Called whenever the user picks a new agent.
  final ValueChanged<String> onAgentSelected;

  const AgentNodeConfig({
    super.key,
    required this.agentId,
    required this.onAgentSelected,
  });

  @override
  ConsumerState<AgentNodeConfig> createState() => _AgentNodeConfigState();
}

class _AgentNodeConfigState extends ConsumerState<AgentNodeConfig> {
  List<Map<String, dynamic>> _agents = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(aiAdminApiProvider).listAgents();
      if (!mounted) return;
      setState(() {
        _agents = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _current {
    for (final a in _agents) {
      if ((a['id']?.toString() ?? '') == widget.agentId) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 14, width: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      // Non-fatal — fall back to letting the user paste a UUID.
      return TextFormField(
        initialValue: widget.agentId,
        decoration: InputDecoration(
          labelText: context.t('agent_node.id_label'),
          helperText: context.t('agent_node.could_not_load_helper'),
          isDense: true,
        ),
        onChanged: widget.onAgentSelected,
      );
    }

    final cur = _current;
    final skills = (cur?['skills'] as List?) ?? const [];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.t('agent_node.label'), style: AppTheme.labelStyle),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        initialValue: widget.agentId.isEmpty ? null : widget.agentId,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          hintText: context.t('agent_node.select_hint'),
        ),
        items: [
          for (final a in _agents)
            DropdownMenuItem<String>(
              value: a['id']?.toString() ?? '',
              child: Text(
                '${a['label'] ?? a['name']} '
                '(${a['provider_type']} / ${a['model_name'] ?? ''})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) => widget.onAgentSelected(v ?? ''),
      ),
      if (cur != null) ...[
        const SizedBox(height: 4),
        Text(
          cur['system_prompt'] == null || (cur['system_prompt'] as String).isEmpty
              ? context.t('agent_node.no_system_prompt')
              : '${context.t('agent_node.system_prompt_prefix')}: ${(cur['system_prompt'] as String).split('\n').first}',
          style: AppTheme.captionStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
      const SizedBox(height: 8),
      // Read-only chips of attached skills — clicks deep-link to AI
      // admin so authors can edit.
      if (skills.isNotEmpty) ...[
        Text(context.t('agent_node.attached_skills'), style: AppTheme.labelStyle),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final s in skills)
              Chip(
                label: Text(
                  (s['label'] ?? s['name'] ?? '?').toString(),
                  style: const TextStyle(fontSize: 11),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: const Color(0xFFE0F2FE),
              ),
          ],
        ),
      ] else if (cur != null) ...[
        Text(context.t('agent_node.no_skills'), style: AppTheme.captionStyle),
      ],
    ]);
  }
}
