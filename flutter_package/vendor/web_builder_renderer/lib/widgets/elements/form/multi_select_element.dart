import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../binding/expression_resolver.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

/// Multi-select chip picker.
///
/// Option shapes (same as SelectFieldElement):
///   1. List of strings:  `options: ["a", "b"]`
///   2. List of maps:     `options: [{label, value}, ...]`
///   3. Remote fetch:     `optionsFromUrl: {url, headers, labelField, valueField}`
///
/// The selected *values* are published two ways so they can flow into a
/// sibling element's binding (e.g. a fileUpload's `tags` field):
///   • FormScope.report(id, "v1,v2")  — when inside a <form>
///   • page element-value map         — `{{element.<id>.value}}` resolves to
///     the comma-joined value string (the shape restoration's upload
///     endpoint expects for its `tags` form field).
class MultiSelectElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const MultiSelectElement({
    super.key,
    required this.element,
    required this.mode,
    this.pageId = '',
  });

  @override
  ConsumerState<MultiSelectElement> createState() => _MultiSelectElementState();
}

class _Option {
  final String label;
  final String value;
  const _Option(this.label, this.value);
}

class _MultiSelectElementState extends ConsumerState<MultiSelectElement> {
  final Set<String> _selected = {};
  // Values the user typed that aren't in the fetched catalog ("type-to-create").
  final List<String> _custom = [];
  final TextEditingController _newTagCtrl = TextEditingController();
  List<_Option> _options = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _newTagCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _options = _parseStaticOptions();
    final remote = widget.element.config['optionsFromUrl'];
    if (remote is Map) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchRemote(remote));
    }
    // Seed `{{element.<id>.value}}` as an empty string on first render so a
    // sibling binding referencing it before any selection resolves to "" —
    // not an unresolved `{{...}}` token (ExpressionResolver leaves paths
    // that have never been set untouched, which breaks a query string like
    // `?tags={{element.x.value}}` on initial page load).
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
  }

  List<_Option> _parseStaticOptions() {
    final raw = widget.element.config['options'];
    if (raw is! List) return const [];
    final out = <_Option>[];
    for (final entry in raw) {
      if (entry is String) {
        out.add(_Option(entry, entry));
      } else if (entry is Map) {
        final label = (entry['label'] ?? entry['value'] ?? '').toString();
        final value = (entry['value'] ?? entry['label'] ?? '').toString();
        if (label.isEmpty && value.isEmpty) continue;
        out.add(_Option(label, value));
      }
    }
    return out;
  }

  String? _resolvePageId() {
    if (widget.pageId.isNotEmpty) return widget.pageId;
    final map = ref.read(bindingContextProvider);
    if (map.length == 1) return map.keys.first;
    return null;
  }

  Future<void> _fetchRemote(Map raw) async {
    final pageId = _resolvePageId();
    final ctx = pageId == null ? null : ref.read(bindingContextProvider)[pageId];
    if (ctx == null) return;
    final resolver = ExpressionResolver(ctx);
    final url = await resolver.resolve('${raw['url'] ?? ''}');
    if (url.isEmpty) return;
    final headers = <String, String>{};
    final rawHeaders = (raw['headers'] as Map?) ?? const {};
    for (final entry in rawHeaders.entries) {
      final v = await resolver.resolve('${entry.value}');
      if (v.isNotEmpty) headers['${entry.key}'] = v;
    }
    final labelField = (raw['labelField'] as String?) ?? 'label';
    final valueField = (raw['valueField'] as String?) ?? 'value';

    if (mounted) setState(() => _loading = true);
    try {
      final dio = Dio();
      final r = await dio.get<dynamic>(url, options: Options(headers: headers));
      final list = r.data is List
          ? (r.data as List)
          : (r.data is Map && (r.data as Map)['items'] is List
              ? ((r.data as Map)['items'] as List)
              : const []);
      final fetched = <_Option>[];
      for (final row in list) {
        if (row is Map) {
          final label = (row[labelField] ?? row['name'] ?? '').toString();
          final value = (row[valueField] ?? row['key'] ?? row['id'] ?? '')
              .toString();
          if (value.isEmpty) continue;
          fetched.add(_Option(label.isEmpty ? value : label, value));
        }
      }
      if (mounted) {
        setState(() {
          _options = fetched;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _shortError(e);
          _loading = false;
        });
      }
    }
  }

  String _shortError(Object e) {
    if (e is DioException) {
      return e.response?.statusCode != null
          ? 'HTTP ${e.response!.statusCode}'
          : (e.message ?? 'fetch failed');
    }
    return '$e'.split('\n').first;
  }

  void _toggle(String value) {
    setState(() {
      if (_selected.contains(value)) {
        _selected.remove(value);
        _custom.remove(value);
      } else {
        _selected.add(value);
      }
    });
    _publish();
  }

  /// Add a user-typed tag (normalised to a lowercase, underscore key) as a
  /// new selected value. The backend turns unknown keys into project tags.
  void _addTyped() {
    final raw = _newTagCtrl.text.trim();
    if (raw.isEmpty) return;
    final key = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (key.isEmpty) return;
    setState(() {
      _selected.add(key);
      final inOptions = _options.any((o) => o.value == key);
      if (!inOptions && !_custom.contains(key)) _custom.add(key);
      _newTagCtrl.clear();
    });
    _publish();
  }

  void _publish() {
    // Option-order values first, then any typed customs — all selected.
    final ordered = _options.map((o) => o.value).where(_selected.contains).toList();
    for (final c in _custom) {
      if (_selected.contains(c) && !ordered.contains(c)) ordered.add(c);
    }
    final joined = ordered.join(',');
    // Report the actual LIST to the form (not a comma-joined string). Form
    // bodies serialize to JSON, and multi-value fields like `tags` map to a
    // JSON array — reporting a string sent `tags: ""` and the API rejected it
    // with "Input should be a valid list" (422). Keep the joined string for
    // page-context token substitution ({{...}}), which is string-based.
    FormScope.maybeOf(context)?.report(widget.element.id, List<String>.from(ordered));
    final pageId = _resolvePageId();
    if (pageId != null) {
      ref
          .read(bindingContextProvider.notifier)
          .setElementValue(pageId, widget.element.id, joined);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final label = widget.element.config['label'] as String? ?? 'Select';
    final required = widget.element.config['required'] as bool? ?? false;
    final allowCreate = widget.element.config['allowCreate'] as bool? ?? false;
    final interactive = widget.mode != RenderMode.builder;

    // Chips: catalog options + any user-typed customs not in the catalog.
    final customChips = _custom
        .where((c) => !_options.any((o) => o.value == c))
        .map((c) => _Option(c, c))
        .toList();
    final allChips = [..._options, ...customChips];

    return FormFieldShell(
      label: label,
      required: required,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (allChips.isEmpty && !allowCreate)
            Text(
              _error != null ? '— (load failed: $_error)' : 'No options',
              style: GoogleFonts.inter(
                fontSize: OTokens.textXs,
                color: pal.textMuted,
              ),
            )
          else if (allChips.isNotEmpty)
            Wrap(
              spacing: OTokens.s2,
              runSpacing: OTokens.s2,
              children: allChips.map((opt) {
                final isSelected = _selected.contains(opt.value);
                return GestureDetector(
                  onTap: interactive ? () => _toggle(opt.value) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                        horizontal: OTokens.s3, vertical: OTokens.s2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? pal.primaryBlue.withValues(alpha: 0.15)
                          : pal.bgSurface,
                      borderRadius: BorderRadius.circular(OTokens.radiusFull),
                      border: Border.all(
                        color: isSelected
                            ? pal.primaryBlue.withValues(alpha: 0.6)
                            : pal.borderSubtle,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          Icon(LucideIcons.check,
                              size: 12, color: pal.primaryBlue),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          opt.label,
                          style: GoogleFonts.inter(
                            fontSize: OTokens.textXs,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected
                                ? pal.primaryBlue
                                : pal.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          if (allowCreate && interactive) ...[
            const SizedBox(height: OTokens.s2),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTagCtrl,
                    onSubmitted: (_) => _addTyped(),
                    style: GoogleFonts.inter(
                        fontSize: OTokens.textSm, color: pal.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Type a new tag, press Enter',
                      hintStyle: GoogleFonts.inter(
                          fontSize: OTokens.textXs, color: pal.textMuted),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: OTokens.s3, vertical: OTokens.s2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(OTokens.radiusSm),
                        borderSide: BorderSide(color: pal.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(OTokens.radiusSm),
                        borderSide: BorderSide(color: pal.borderSubtle),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: OTokens.s2),
                TextButton.icon(
                  onPressed: _addTyped,
                  icon: const Icon(LucideIcons.plus, size: 14),
                  label: const Text('Add'),
                ),
              ],
            ),
          ],
          if (_selected.isNotEmpty) ...[
            const SizedBox(height: OTokens.s2),
            Text(
              '${_selected.length} selected',
              style: GoogleFonts.inter(
                  fontSize: OTokens.textXs, color: pal.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
