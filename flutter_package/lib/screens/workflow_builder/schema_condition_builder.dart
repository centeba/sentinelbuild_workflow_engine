// SchemaConditionBuilder — a no-code condition editor for non-technical users.
//
// Renders an AND/OR/NOT tree where every leaf is a cascade of dropdowns:
//   Domain → Entity → Field → Operator → Value
// The domain/entity/field choices come from the pack's `data_domains` schema
// (registry.packDataDomains), and the value-picker is chosen by the field type
// (enum dropdown / reference dropdown / bool / number / date / text). The user
// never types a field path or an expression.
//
// Emits the structured group consumed by mit-stack's rule engine:
//   {combinator: "and"|"or"|"not",
//    rules: [ {domain, entity, field, operator, value} | <nested group> ]}
//
// Reused by the canvas trigger-filter config, the domain_condition node, and
// (later) the recipe builder + rules screen.
import 'package:flutter/material.dart';

import '../../theme.dart';
import 'schema_driven_config_form.dart' show ReferenceField;

/// Friendly labels for rule-engine operators (the schema declares operator
/// keys; we render human text).
const Map<String, String> kOperatorLabels = {
  'eq': 'equals',
  'neq': 'does not equal',
  'in': 'is any of',
  'not_in': 'is none of',
  'contains': 'contains',
  'starts_with': 'starts with',
  'gt': 'greater than',
  'gte': 'at least',
  'lt': 'less than',
  'lte': 'at most',
  'between': 'is between',
  'is_empty': 'is empty',
  'is_not_empty': 'is not empty',
  'is_true': 'is yes',
  'is_false': 'is no',
  'matches_regex': 'matches pattern',
  'date_before': 'is before',
  'date_after': 'is after',
  'date_equals': 'is on',
  'within_last_n_days': 'within last N days',
  'older_than_n_days': 'older than N days',
};

/// Operators that need no value widget.
const Set<String> _kNoValueOps = {'is_true', 'is_false', 'is_empty', 'is_not_empty'};

/// Operators whose value is a list / range (rendered as comma-separated text).
const Set<String> _kMultiValueOps = {'in', 'not_in', 'between'};

class SchemaConditionBuilder extends StatefulWidget {
  /// `data_domains` from the node-type registry (one entry per pack domain).
  final List<Map<String, dynamic>> domains;

  /// The current condition group (``{combinator, rules}``) or null/empty.
  final Map<String, dynamic>? value;

  /// Called with the full updated group on every edit.
  final void Function(Map<String, dynamic> group) onChanged;

  const SchemaConditionBuilder({
    super.key,
    required this.domains,
    required this.value,
    required this.onChanged,
  });

  @override
  State<SchemaConditionBuilder> createState() => _SchemaConditionBuilderState();
}

class _SchemaConditionBuilderState extends State<SchemaConditionBuilder> {
  late Map<String, dynamic> _group;

  @override
  void initState() {
    super.initState();
    _group = _normalize(widget.value);
  }

  Map<String, dynamic> _normalize(Map<String, dynamic>? g) {
    if (g == null || g.isEmpty) return {'combinator': 'and', 'rules': <dynamic>[]};
    return {
      'combinator': (g['combinator'] as String?) ?? 'and',
      'rules': List<dynamic>.from(g['rules'] as List? ?? const []),
    };
  }

  void _changed() {
    widget.onChanged(_group);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.domains.isEmpty) {
      return Text(
        'No domain data is available to build conditions. '
        'Install a domain app (pack) first.',
        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
      );
    }
    return _buildGroup(_group, depth: 0);
  }

  Widget _buildGroup(Map<String, dynamic> group, {required int depth}) {
    final combinator = (group['combinator'] as String?) ?? 'and';
    final rules = group['rules'] as List? ?? const [];
    return Container(
      margin: EdgeInsets.only(left: depth == 0 ? 0 : 12, top: 6, bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.bgPage,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Match', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: combinator,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'and', child: Text('ALL of')),
                DropdownMenuItem(value: 'or', child: Text('ANY of')),
                DropdownMenuItem(value: 'not', child: Text('NONE of')),
              ],
              onChanged: (v) {
                group['combinator'] = v ?? 'and';
                _changed();
              },
            ),
            const SizedBox(width: 8),
            Text('the following:',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ]),
          const SizedBox(height: 6),
          for (int i = 0; i < rules.length; i++)
            _buildRule(group, rules, i, depth: depth),
          const SizedBox(height: 4),
          Row(children: [
            TextButton.icon(
              onPressed: () {
                rules.add(<String, dynamic>{
                  'domain': '', 'entity': '', 'field': '',
                  'operator': '', 'value': '',
                });
                group['rules'] = rules;
                _changed();
              },
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add condition'),
            ),
            TextButton.icon(
              onPressed: () {
                rules.add(<String, dynamic>{'combinator': 'and', 'rules': <dynamic>[]});
                group['rules'] = rules;
                _changed();
              },
              icon: const Icon(Icons.account_tree_outlined, size: 14),
              label: const Text('Add group'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildRule(
      Map<String, dynamic> parent, List rules, int index, {required int depth}) {
    final rule = Map<String, dynamic>.from(rules[index] as Map);
    final isGroup = rule.containsKey('combinator');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: isGroup
              ? _buildGroup(rules[index] as Map<String, dynamic>, depth: depth + 1)
              : _LeafRow(
                  key: ValueKey('leaf_${depth}_$index'),
                  domains: widget.domains,
                  leaf: rules[index] as Map<String, dynamic>,
                  onChanged: _changed,
                ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          color: AppTheme.textMuted,
          tooltip: 'Remove',
          onPressed: () {
            rules.removeAt(index);
            parent['rules'] = rules;
            _changed();
          },
        ),
      ],
    );
  }
}

/// One leaf condition: Domain → Entity → Field → Operator → Value.
class _LeafRow extends StatelessWidget {
  final List<Map<String, dynamic>> domains;
  final Map<String, dynamic> leaf;
  final VoidCallback onChanged;

  const _LeafRow({
    super.key,
    required this.domains,
    required this.leaf,
    required this.onChanged,
  });

  Map<String, dynamic>? _domain() {
    final k = leaf['domain'];
    return domains.firstWhere((d) => d['key'] == k, orElse: () => <String, dynamic>{});
  }

  List<Map<String, dynamic>> _entities() {
    final d = _domain();
    return List<Map<String, dynamic>>.from(
      (d?['entities'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  Map<String, dynamic>? _entity() {
    final k = leaf['entity'];
    return _entities().firstWhere((e) => e['key'] == k, orElse: () => <String, dynamic>{});
  }

  List<Map<String, dynamic>> _fields() {
    final e = _entity();
    return List<Map<String, dynamic>>.from(
      (e?['fields'] as List? ?? const []).map((f) => Map<String, dynamic>.from(f as Map)),
    );
  }

  Map<String, dynamic>? _field() {
    final k = leaf['field'];
    return _fields().firstWhere((f) => f['key'] == k, orElse: () => <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    // Auto-select the only domain so the user never sees a 1-item dropdown.
    if ((leaf['domain'] as String? ?? '').isEmpty && domains.length == 1) {
      leaf['domain'] = domains.first['key'];
    }
    final field = _field();
    final ftype = (field?['type'] as String?) ?? 'string';
    final operators = List<String>.from(field?['operators'] as List? ?? const []);
    final op = (leaf['operator'] as String?) ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (domains.length > 1)
            _dd('Domain', leaf['domain'], [
              for (final d in domains)
                DropdownMenuItem(value: d['key'] as String, child: Text(d['label'] as String? ?? d['key'] as String)),
            ], (v) {
              leaf['domain'] = v; leaf['entity'] = ''; leaf['field'] = '';
              leaf['operator'] = ''; leaf['value'] = ''; onChanged();
            }),
          _dd('Data', leaf['entity'], [
            for (final e in _entities())
              DropdownMenuItem(value: e['key'] as String, child: Text(e['label'] as String? ?? e['key'] as String)),
          ], (v) {
            leaf['entity'] = v; leaf['field'] = '';
            leaf['operator'] = ''; leaf['value'] = ''; onChanged();
          }),
          _dd('Field', leaf['field'], [
            for (final f in _fields())
              DropdownMenuItem(value: f['key'] as String, child: Text(f['label'] as String? ?? f['key'] as String)),
          ], (v) {
            leaf['field'] = v;
            // Default to the field's first operator.
            final fl = _fields().firstWhere((f) => f['key'] == v, orElse: () => <String, dynamic>{});
            final ops = List<String>.from(fl['operators'] as List? ?? const []);
            leaf['operator'] = ops.isNotEmpty ? ops.first : 'eq';
            leaf['value'] = ''; onChanged();
          }),
          if (operators.isNotEmpty)
            _dd('Is', op.isEmpty ? null : op, [
              for (final o in operators)
                DropdownMenuItem(value: o, child: Text(kOperatorLabels[o] ?? o)),
            ], (v) { leaf['operator'] = v; onChanged(); }),
          if (op.isNotEmpty && !_kNoValueOps.contains(op))
            _valueWidget(field ?? const {}, ftype, op),
        ],
      ),
    );
  }

  Widget _dd(String hint, String? value, List<DropdownMenuItem<String>> items,
      void Function(String?) onCh) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
      child: DropdownButtonFormField<String>(
        value: (value as String?)?.isEmpty ?? true ? null : value,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: hint, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          border: const OutlineInputBorder(),
        ),
        items: items,
        onChanged: onCh,
      ),
    );
  }

  Widget _valueWidget(Map<String, dynamic> field, String ftype, String op) {
    final width = ftype == 'reference' ? 220.0 : 160.0;
    // List / range operators → comma-separated text fallback (advanced).
    if (_kMultiValueOps.contains(op)) {
      return SizedBox(width: width, child: _text('Values (comma-separated)', keyboard: ftype == 'number' ? TextInputType.number : null));
    }
    switch (ftype) {
      case 'enum':
        final opts = List<Map<String, dynamic>>.from(
          (field['options'] as List? ?? const []).map((o) => Map<String, dynamic>.from(o as Map)),
        );
        return ConstrainedBox(
          constraints: BoxConstraints(minWidth: 140, maxWidth: width),
          child: DropdownButtonFormField<String>(
            value: (leaf['value'] as String?)?.isEmpty ?? true ? null : leaf['value'] as String,
            isDense: true, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Value', isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
            items: [for (final o in opts) DropdownMenuItem(value: o['value'] as String, child: Text(o['label'] as String? ?? o['value'] as String))],
            onChanged: (v) { leaf['value'] = v; onChanged(); },
          ),
        );
      case 'reference':
        return SizedBox(
          width: width,
          child: ReferenceField(
            fieldKey: 'cond_value',
            spec: {
              'source_url': field['source_url'],
              'label_field': field['label_field'] ?? 'name',
              'value_field': field['value_field'] ?? 'id',
            },
            currentValue: leaf['value'],
            isRequired: false,
            helper: null,
            onChanged: (v) { leaf['value'] = v; onChanged(); },
          ),
        );
      case 'number':
        return SizedBox(width: width, child: _text('Value', keyboard: TextInputType.number));
      case 'date':
        return SizedBox(width: width, child: _text('YYYY-MM-DD'));
      default:
        return SizedBox(width: width, child: _text('Value'));
    }
  }

  Widget _text(String label, {TextInputType? keyboard}) {
    return TextFormField(
      initialValue: leaf['value']?.toString() ?? '',
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label, isDense: true, border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      onChanged: (v) { leaf['value'] = v; onChanged(); },
    );
  }
}
