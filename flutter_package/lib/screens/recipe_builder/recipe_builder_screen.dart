// RecipeBuilderScreen — a linear When / If / Then automation builder for
// non-technical operations users. No canvas, no node graph: three stacked
// sections that compile to the SAME workflow definition the executor runs, so a
// recipe opens in the canvas for free and one engine runs both.
//
//   When  → a pack trigger (the domain event that starts the automation)
//   If    → optional domain conditions (SchemaConditionBuilder — pick
//           domain→field→value); compiled to a domain_condition branch node
//   Then  → ordered pack actions, each configured via SchemaDrivenConfigForm
//
// Saves via POST /workflows; trigger_type + trigger filter are derived
// server-side from the entry node.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../../theme.dart';
import '../../i18n/translate_extension.dart';
import '../workflow_builder/node_type_registry.dart';
import '../workflow_builder/schema_condition_builder.dart';
import '../workflow_builder/schema_driven_config_form.dart';

class _ActionStep {
  String nodeKey;
  Map<String, dynamic> config;
  _ActionStep({required this.nodeKey, Map<String, dynamic>? config})
      : config = config ?? <String, dynamic>{};
}

class RecipeBuilderScreen extends ConsumerStatefulWidget {
  /// Stamps the owning app so the recipe only shows in that app's list.
  final String? sourceApp;
  const RecipeBuilderScreen({super.key, this.sourceApp});

  @override
  ConsumerState<RecipeBuilderScreen> createState() => _RecipeBuilderScreenState();
}

class _RecipeBuilderScreenState extends ConsumerState<RecipeBuilderScreen> {
  final _name = TextEditingController();
  String? _triggerKey;
  Map<String, dynamic>? _conditions;
  final List<_ActionStep> _actions = [];
  bool _saving = false;

  String _label(Map<String, dynamic> spec) {
    final lk = spec['label_key'] as String?;
    final translated = lk == null ? null : context.t(lk);
    if (translated != null && translated != lk) return translated;
    // Fall back to a friendly form of the key's last segment.
    final key = (spec['key'] as String? ?? '').split('.').last;
    return key.replaceAll('_', ' ').replaceFirstMapped(
        RegExp(r'^.'), (m) => m.group(0)!.toUpperCase());
  }

  Map<String, dynamic> _compile() {
    final nodes = <Map<String, dynamic>>[];
    final edges = <Map<String, dynamic>>[];
    double x = 40;
    nodes.add({
      'id': 'trigger', 'type': 'pack_trigger',
      'position': {'x': x, 'y': 80},
      'config': {'node_key': _triggerKey},
    });
    String prev = 'trigger';
    String? firstEdgeBranch;
    x += 240;

    final hasCond = _conditions != null &&
        ((_conditions!['rules'] as List?)?.isNotEmpty ?? false);
    if (hasCond) {
      nodes.add({
        'id': 'cond', 'type': 'domain_condition',
        'position': {'x': x, 'y': 80},
        'config': {
          'project_id': '{{trigger.project_id}}',
          'conditions': _conditions,
        },
      });
      edges.add({'from': prev, 'to': 'cond'});
      prev = 'cond';
      firstEdgeBranch = 'true_branch'; // actions hang off the "matched" branch
      x += 240;
    }

    for (int i = 0; i < _actions.length; i++) {
      final id = 'action_$i';
      nodes.add({
        'id': id, 'type': 'pack_action',
        'position': {'x': x, 'y': 80},
        'config': {'node_key': _actions[i].nodeKey, ..._actions[i].config},
      });
      final edge = <String, dynamic>{'from': prev, 'to': id};
      if (i == 0 && firstEdgeBranch != null) edge['branch'] = firstEdgeBranch;
      edges.add(edge);
      prev = id;
      x += 240;
    }

    return {
      'nodes': nodes,
      'edges': edges,
      // Lets the UI reopen a linear workflow in this recipe editor.
      'meta': {'builder': 'recipe'},
    };
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _triggerKey == null || _actions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Add a name, a trigger, and at least one action.'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/workflows', data: {
        'name': _name.text.trim(),
        'definition': _compile(),
        if (widget.sourceApp != null) 'source_app': widget.sourceApp,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Automation saved')));
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(nodeTypeRegistryProvider);
    return Scaffold(
      backgroundColor: AppTheme.bgPage,
      appBar: AppBar(
        title: const Text('New automation'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check, size: 16),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (registry) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Automation name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            _section('WHEN', 'this happens', _whenSection(registry)),
            const SizedBox(height: 16),
            _section('IF', 'these conditions match (optional)', _ifSection(registry)),
            const SizedBox(height: 16),
            _section('THEN', 'do these', _thenSection(registry)),
          ],
        ),
      ),
    );
  }

  Widget _section(String tag, String hint, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(tag, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primary)),
            const SizedBox(width: 8),
            Text(hint, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _whenSection(NodeTypeRegistry registry) {
    final triggers = registry.packTriggers;
    if (triggers.isEmpty) {
      return const Text('No triggers available. Install a domain app first.',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted));
    }
    return DropdownButtonFormField<String>(
      value: _triggerKey,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Trigger event', border: OutlineInputBorder(), isDense: true),
      items: [
        for (final t in triggers)
          DropdownMenuItem(value: t['key'] as String, child: Text(_label(t))),
      ],
      onChanged: (v) => setState(() => _triggerKey = v),
    );
  }

  Widget _ifSection(NodeTypeRegistry registry) {
    return SchemaConditionBuilder(
      domains: registry.packDataDomains,
      value: _conditions,
      onChanged: (group) => setState(() => _conditions = group),
    );
  }

  Widget _thenSection(NodeTypeRegistry registry) {
    final actions = registry.packActions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _actions.length; i++)
          _actionCard(registry, i),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: actions.isEmpty
              ? null
              : () => setState(() => _actions.add(
                  _ActionStep(nodeKey: actions.first['key'] as String))),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add action'),
        ),
      ],
    );
  }

  Widget _actionCard(NodeTypeRegistry registry, int i) {
    final actions = registry.packActions;
    final step = _actions[i];
    final spec = actions.firstWhere((a) => a['key'] == step.nodeKey,
        orElse: () => <String, dynamic>{});
    final schema =
        (spec['config_schema'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgPage,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: step.nodeKey,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Action', border: OutlineInputBorder(), isDense: true),
                items: [
                  for (final a in actions)
                    DropdownMenuItem(value: a['key'] as String, child: Text(_label(a))),
                ],
                onChanged: (v) => setState(() {
                  step.nodeKey = v ?? step.nodeKey;
                  step.config = {}; // reset config when the action changes
                }),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.textMuted),
              onPressed: () => setState(() => _actions.removeAt(i)),
            ),
          ]),
          if (schema.isNotEmpty) ...[
            const SizedBox(height: 8),
            SchemaDrivenConfigForm(
              schema: schema,
              initialValues: step.config,
              onChanged: (values) => setState(() => step.config = {...step.config, ...values}),
            ),
          ],
        ],
      ),
    );
  }
}
