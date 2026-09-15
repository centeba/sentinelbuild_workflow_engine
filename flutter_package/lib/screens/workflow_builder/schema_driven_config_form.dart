// Schema-driven config form for pack-contributed workflow nodes.
//
// When the admin selects a `pack_trigger` or `pack_action` on the
// canvas, the right-side `NodeConfigPanel` looks up the node's
// JSON Schema in the registry and hands it to this widget. The form
// renders typed fields (string / number / boolean / enum / array /
// reference) and emits a flat `Map<String, dynamic>` back via
// `onChanged` — same contract as the hand-tuned `_FieldDef` switch
// the panel uses for built-in nodes.
//
// Modeled directly on `tool_params_form.dart`, but takes the schema
// inline (the registry endpoint already returned it) instead of
// re-fetching per skill.
//
// Property types beyond plain JSON Schema:
//   - `"reference"` — a dropdown whose options come from a remote
//     endpoint. Spec shape:
//       {
//         "type": "reference",
//         "source_url": "/api/restoration/v1/email-templates",
//         "label_field": "name",
//         "value_field": "id"
//       }
//     The form fetches `source_url` (via the same Dio client used
//     for the registry call) at first render and renders a
//     DropdownButtonFormField. This is how pack actions like
//     "Notify project manager" can show "Email template ▾" with
//     options pulled live from restoration's catalog.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../services/api_client.dart';
import '../../theme.dart';
import 'node_type_registry.dart';

class SchemaDrivenConfigForm extends ConsumerStatefulWidget {
  final Map<String, dynamic> schema;
  final Map<String, dynamic> initialValues;
  final void Function(Map<String, dynamic> values) onChanged;

  const SchemaDrivenConfigForm({
    super.key,
    required this.schema,
    required this.initialValues,
    required this.onChanged,
  });

  @override
  ConsumerState<SchemaDrivenConfigForm> createState() =>
      _SchemaDrivenConfigFormState();
}

class _SchemaDrivenConfigFormState
    extends ConsumerState<SchemaDrivenConfigForm> {
  late Map<String, dynamic> _values;
  // Controllers for string fields so the variable picker can insert a
  // token at the caret instead of only appending.
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValues);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key, String initial) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: initial),
    );
  }

  void _setValue(String key, dynamic value) {
    setState(() => _values[key] = value);
    widget.onChanged(_values);
  }

  /// Available `{{...}}` variables an admin can insert. Sourced from the
  /// node-type registry: every restoration trigger's `payload_schema`
  /// contributes `{{trigger.<field>}}` entries, plus the always-present
  /// `{{execution.id}}`. This is the data-driven half of the picker —
  /// adding a field to a trigger's payload_schema makes it offerable
  /// here with no extra wiring. (Upstream per-node outputs —
  /// `{{nodes.<id>.body...}}` — need the builder's live graph and are a
  /// follow-up.)
  List<MapEntry<String, String>> _availableVariables(
    NodeTypeRegistry? reg,
  ) {
    final out = <MapEntry<String, String>>[
      const MapEntry('Execution ID', '{{execution.id}}'),
    ];
    final seen = <String>{};
    if (reg != null) {
      for (final trig in reg.packTriggers) {
        final schema = (trig['payload_schema'] as Map?)?.cast<String, dynamic>();
        final props = (schema?['properties'] as Map?)?.cast<String, dynamic>();
        if (props == null) continue;
        for (final field in props.keys) {
          final token = '{{trigger.$field}}';
          if (seen.add(token)) {
            out.add(MapEntry(field, token));
          }
        }
      }
    }
    return out;
  }

  void _insertToken(String key, String token) {
    final ctrl = _controllers[key];
    if (ctrl == null) {
      _setValue(key, '${_values[key] ?? ''}$token');
      return;
    }
    final sel = ctrl.selection;
    final text = ctrl.text;
    final at = (sel.start >= 0) ? sel.start : text.length;
    final newText = text.replaceRange(
      at,
      (sel.end >= 0) ? sel.end : at,
      token,
    );
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: at + token.length),
    );
    _setValue(key, newText);
  }

  Widget _variablePickerButton(String key) {
    final reg = ref.watch(nodeTypeRegistryProvider).value;
    final vars = _availableVariables(reg);
    return PopupMenuButton<String>(
      tooltip: 'Insert variable',
      icon: const Icon(Icons.data_object, size: 16, color: AppTheme.textMuted),
      itemBuilder: (_) => [
        for (final v in vars)
          PopupMenuItem<String>(
            value: v.value,
            child: Text(
              '${v.key}  —  ${v.value}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
      onSelected: (token) => _insertToken(key, token),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schema = widget.schema;
    final props = (schema['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    if (props.isEmpty) {
      return const SizedBox.shrink();
    }
    final required = ((schema['required'] as List?) ?? const [])
        .cast<dynamic>()
        .map((e) => e.toString())
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in props.entries)
          _buildField(
            entry.key,
            (entry.value as Map).cast<String, dynamic>(),
            isRequired: required.contains(entry.key),
          ),
      ],
    );
  }

  // ── Field renderers ───────────────────────────────────────────────────────

  Widget _label(String key, {required bool isRequired}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: key),
          if (isRequired)
            const TextSpan(
              text: ' *',
              style: TextStyle(
                color: AppTheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
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
    final helper = (spec['description'] as String?)?.trim();

    // 1. Reference — async dropdown loaded from a sibling endpoint.
    if (type == 'reference') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ReferenceField(
          fieldKey: key,
          spec: spec,
          currentValue: current,
          isRequired: isRequired,
          helper: helper,
          onChanged: (v) => _setValue(key, v),
        ),
      );
    }

    // 2. Enum (any inline type) — static dropdown.
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

    // 3. Typed primitive renderers.
    switch (type) {
      case 'boolean':
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: _label(key, isRequired: isRequired),
            subtitle: helper == null
                ? null
                : Text(
                    helper,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
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
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            onChanged: (v) {
              final parsed =
                  type == 'integer' ? int.tryParse(v) : double.tryParse(v);
              _setValue(key, parsed ?? v);
            },
          ),
        );
      case 'array':
        // Comma/newline-separated text input. Same convention as
        // tool_params_form.dart — when admins need richer
        // multi-select, the schema author should use a multi-enum
        // or upgrade this to a chips widget.
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
              _setValue(key, parts);
            },
          ),
        );
      case 'string':
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextFormField(
            controller: _controllerFor(key, current?.toString() ?? ''),
            decoration: InputDecoration(
              label: _label(key, isRequired: isRequired),
              isDense: true,
              helperText: helper,
              helperMaxLines: 3,
              // Point-and-click variable insertion — no hand-typing
              // {{trigger.project_id}} etc.
              suffixIcon: _variablePickerButton(key),
            ),
            minLines: 1,
            maxLines: (spec['format'] == 'multiline') ? 4 : 1,
            onChanged: (v) => _setValue(key, v),
          ),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reference field: dropdown populated by an async fetch.
// ─────────────────────────────────────────────────────────────────────────────

class ReferenceField extends ConsumerStatefulWidget {
  final String fieldKey;
  final Map<String, dynamic> spec;
  final dynamic currentValue;
  final bool isRequired;
  final String? helper;
  final void Function(String? value) onChanged;

  const ReferenceField({super.key, 
    required this.fieldKey,
    required this.spec,
    required this.currentValue,
    required this.isRequired,
    required this.helper,
    required this.onChanged,
  });

  @override
  ConsumerState<ReferenceField> createState() => ReferenceFieldState();
}

class ReferenceFieldState extends ConsumerState<ReferenceField> {
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _options = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sourceUrl = widget.spec['source_url'] as String?;
    if (sourceUrl == null || sourceUrl.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'reference field missing source_url';
      });
      return;
    }
    try {
      final dio = ref.read(dioProvider);
      // Absolute URL → use a bare Dio (no baseUrl override). The shared dio's
      // auth interceptor doesn't run on this fresh instance, so forward the
      // bearer token explicitly: some reference endpoints (e.g. a company-user
      // picker that returns PII) are JWT-gated and self-scope to the caller's
      // company. Relative URLs go through the shared dio, which already adds it.
      Response<dynamic> r;
      if (sourceUrl.startsWith('http')) {
        final headers = Map<String, dynamic>.from(dio.options.headers);
        final token = await const FlutterSecureStorage()
            .read(key: 'sb_access_token');
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
        r = await Dio(BaseOptions(headers: headers)).get<dynamic>(sourceUrl);
      } else {
        r = await dio.get<dynamic>(sourceUrl);
      }
      final data = r.data;
      final rows = data is List
          ? data
          : (data is Map && data['data'] is List ? data['data'] as List : []);
      if (!mounted) return;
      setState(() {
        _options = [
          for (final row in rows)
            if (row is Map) Map<String, dynamic>.from(row),
        ];
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          height: 14,
          width: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return Text(
        'Could not load options for ${widget.fieldKey}: $_error',
        style: const TextStyle(fontSize: 11, color: AppTheme.error),
      );
    }
    final labelField = (widget.spec['label_field'] as String?) ?? 'name';
    final valueField = (widget.spec['value_field'] as String?) ?? 'id';

    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        label: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: widget.fieldKey),
              if (widget.isRequired)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: AppTheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        isDense: true,
        helperText: widget.helper,
        helperMaxLines: 3,
      ),
      initialValue: widget.currentValue?.toString(),
      items: [
        for (final opt in _options)
          DropdownMenuItem(
            value: opt[valueField]?.toString(),
            child: Text(opt[labelField]?.toString() ?? '<no label>'),
          ),
      ],
      onChanged: widget.onChanged,
      validator: widget.isRequired
          ? (v) => (v == null || v.isEmpty)
              ? '${widget.fieldKey} is required'
              : null
          : null,
    );
  }
}
