import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/ai_api.dart' show aiAdminApiProvider;
import '../../theme.dart';

/// Renders typed input fields driven by a tool's ``params_schema``.
///
/// Phase E1: when a ``tool_node`` is selected in the workflow builder,
/// fetch ``GET /ai-skills/registry/{skill_name}`` to retrieve the
/// JSONSchema and render a ``string`` / ``number`` / ``boolean`` /
/// enum / ``array`` control per property. Validation falls out of the
/// schema — bad input shows red helper text, the form still emits the
/// raw value so the backend can surface its own validation errors.
class ToolParamsForm extends ConsumerStatefulWidget {
  final String skillName;
  final Map<String, dynamic> initialValues;
  final void Function(Map<String, dynamic> values) onChanged;

  const ToolParamsForm({
    super.key,
    required this.skillName,
    required this.initialValues,
    required this.onChanged,
  });

  @override
  ConsumerState<ToolParamsForm> createState() => _ToolParamsFormState();
}

class _ToolParamsFormState extends ConsumerState<ToolParamsForm> {
  Map<String, dynamic>? _schema;
  Map<String, dynamic> _values = {};
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValues);
    _load();
  }

  @override
  void didUpdateWidget(ToolParamsForm old) {
    super.didUpdateWidget(old);
    if (old.skillName != widget.skillName) {
      setState(() {
        _schema = null;
        _values = Map<String, dynamic>.from(widget.initialValues);
        _loading = true;
        _error = null;
      });
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.skillName.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final api = ref.read(aiAdminApiProvider);
      final meta = await api.getRegistryTool(widget.skillName);
      if (!mounted) return;
      setState(() {
        _schema = (meta['params_schema'] as Map?)?.cast<String, dynamic>();
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

  void _setValue(String key, dynamic value) {
    setState(() => _values[key] = value);
    widget.onChanged(_values);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text('Schema unavailable: $_error',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
      );
    }
    final schema = _schema;
    if (schema == null) {
      return const SizedBox.shrink();
    }
    final props = (schema['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    if (props.isEmpty) return const SizedBox.shrink();
    final required = ((schema['required'] as List?) ?? const []).cast<dynamic>().map((e) => e.toString()).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('PARAMETERS', style: AppTheme.sectionLabel),
        ),
        for (final entry in props.entries)
          _buildField(
            entry.key,
            (entry.value as Map).cast<String, dynamic>(),
            isRequired: required.contains(entry.key),
          ),
      ],
    );
  }

  /// Field label with a red asterisk for required fields. Emitted as a
  /// ``Text.rich`` so it composes inside ``InputDecoration.label``.
  Widget _label(String key, {required bool isRequired}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: key),
          if (isRequired)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  /// Compose the helper-text shown below each field. Combines the schema's
  /// ``description`` with min/max range hints so the user sees why a value
  /// might be invalid without having to consult the registry endpoint.
  String? _helperText(Map<String, dynamic> spec) {
    final desc = (spec['description'] as String?)?.trim();
    final range = _numberHelper(spec);
    if (desc != null && desc.isNotEmpty && range != null) return '$desc  ($range)';
    if (desc != null && desc.isNotEmpty) return desc;
    return range;
  }

  Widget _buildField(
    String key,
    Map<String, dynamic> spec, {
    required bool isRequired,
  }) {
    final type = spec['type'] as String?;
    final enumValues = (spec['enum'] as List?)?.cast<dynamic>();
    final defaultValue = spec['default'];
    final current = _values[key] ?? defaultValue;
    final helper = _helperText(spec);

    if (enumValues != null && enumValues.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DropdownButtonFormField<String>(
          decoration: InputDecoration(
            label: _label(key, isRequired: isRequired),
            isDense: true,
            helperText: helper,
            helperMaxLines: 3,
          ),
          initialValue: current?.toString(),
          items: [
            for (final v in enumValues)
              DropdownMenuItem(value: v.toString(), child: Text(v.toString())),
          ],
          onChanged: (v) => _setValue(key, v),
          validator: isRequired
              ? (v) => (v == null || v.isEmpty) ? '$key is required' : null
              : null,
        ),
      );
    }

    switch (type) {
      case 'boolean':
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: _label(key, isRequired: isRequired),
            subtitle: helper == null ? null : Text(helper, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            value: current == true,
            onChanged: (v) => _setValue(key, v),
          ),
        );
      case 'integer':
      case 'number':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextFormField(
            initialValue: current?.toString() ?? '',
            decoration: InputDecoration(
              label: _label(key, isRequired: isRequired),
              isDense: true,
              helperText: helper,
              helperMaxLines: 3,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            onChanged: (v) {
              final parsed = type == 'integer' ? int.tryParse(v) : double.tryParse(v);
              _setValue(key, parsed ?? v);
            },
            validator: (v) => _validateNumber(v, spec, isRequired: isRequired, isInteger: type == 'integer'),
          ),
        );
      case 'array':
        // Render as a multi-line text field; comma- or newline-separated
        // values become a List<String>. items.type=number/integer parses
        // each element.
        final itemSpec = (spec['items'] as Map?)?.cast<String, dynamic>();
        final itemType = itemSpec?['type'] as String?;
        final asList = current is List ? current : <dynamic>[];
        final initialText = asList.map((e) => e?.toString() ?? '').join(', ');
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextFormField(
            initialValue: initialText,
            decoration: InputDecoration(
              label: _label(key, isRequired: isRequired),
              isDense: true,
              helperText: helper == null
                  ? 'comma- or newline-separated'
                  : '$helper  (comma- or newline-separated)',
              helperMaxLines: 3,
            ),
            minLines: 1,
            maxLines: 4,
            onChanged: (v) {
              final parts = v
                  .split(RegExp(r'[,\n]'))
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              if (itemType == 'integer') {
                _setValue(key, parts.map((s) => int.tryParse(s) ?? s).toList());
              } else if (itemType == 'number') {
                _setValue(key, parts.map((s) => double.tryParse(s) ?? s).toList());
              } else {
                _setValue(key, parts);
              }
            },
            validator: isRequired
                ? (v) => (v == null || v.trim().isEmpty) ? '$key is required' : null
                : null,
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextFormField(
            initialValue: current?.toString() ?? '',
            decoration: InputDecoration(
              label: _label(key, isRequired: isRequired),
              isDense: true,
              helperText: helper,
              helperMaxLines: 3,
            ),
            onChanged: (v) => _setValue(key, v),
            validator: isRequired
                ? (v) => (v == null || v.isEmpty) ? '$key is required' : null
                : null,
          ),
        );
    }
  }

  String? _numberHelper(Map<String, dynamic> spec) {
    final mn = spec['minimum'];
    final mx = spec['maximum'];
    if (mn == null && mx == null) return null;
    return 'range: ${mn ?? '—'} … ${mx ?? '—'}';
  }

  /// Client-side numeric validation: required, parseable, within range.
  String? _validateNumber(
    String? raw,
    Map<String, dynamic> spec, {
    required bool isRequired,
    required bool isInteger,
  }) {
    if (raw == null || raw.isEmpty) {
      return isRequired ? 'required' : null;
    }
    final parsed = isInteger ? int.tryParse(raw) : double.tryParse(raw);
    if (parsed == null) return isInteger ? 'must be an integer' : 'must be a number';
    final mn = spec['minimum'];
    final mx = spec['maximum'];
    if (mn is num && parsed < mn) return 'min: $mn';
    if (mx is num && parsed > mx) return 'max: $mx';
    return null;
  }
}
