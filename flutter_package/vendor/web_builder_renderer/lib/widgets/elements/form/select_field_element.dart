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

/// Single-select dropdown.
///
/// Supports three option shapes (all interchangeable):
///   1. List of strings:  `options: ["Email", "Phone"]`
///   2. List of maps:     `options: [{label: "Email", value: "email"}, ...]`
///   3. Remote fetch:     `optionsFromUrl: {url, headers, labelField, valueField}`
///      The element fetches once on init, maps each response row's
///      `labelField` / `valueField` into the (label, value) tuple, and
///      renders them. `{{...}}` tokens in `url` / `headers` are
///      resolved against the page's BindingContext.
///
/// In all three cases the selected `value` is what's reported to the
/// surrounding form via FormScope.report (label is display-only).
class SelectFieldElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;

  /// The page this field lives on. Needed to resolve the page's
  /// BindingContext for remote option fetches + reporting selected
  /// values. When empty, falls back to the single-registered-context
  /// heuristic (works only when one page is mounted).
  final String pageId;

  const SelectFieldElement({
    super.key,
    required this.element,
    required this.mode,
    this.pageId = '',
  });

  @override
  ConsumerState<SelectFieldElement> createState() => _SelectFieldElementState();
}

class _Option {
  final String label;
  final String value;
  const _Option(this.label, this.value);
}

class _SelectFieldElementState extends ConsumerState<SelectFieldElement> {
  String? _selectedValue;
  String? _selectedLabel;
  List<_Option> _options = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _options = _parseStaticOptions();
    final remote = widget.element.config['optionsFromUrl'];
    if (remote is Map) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchRemote(remote));
    }
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

  Future<void> _fetchRemote(Map raw) async {
    final pageId = _findPageId(context);
    final ctxMap = ref.read(bindingContextProvider);
    final ctx = pageId == null ? null : ctxMap[pageId];
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
          final value = (row[valueField] ?? row['id'] ?? '').toString();
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

  String? _findPageId(BuildContext ctx) {
    // Prefer the explicit pageId passed down from the renderer — robust
    // even when several pages' BindingContexts are registered at once
    // (e.g. after navigating between tabs). Only fall back to the
    // single-context heuristic when no pageId was supplied.
    if (widget.pageId.isNotEmpty) return widget.pageId;
    final map = ref.read(bindingContextProvider);
    if (map.length == 1) return map.keys.first;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final label = widget.element.config['label'] as String? ?? 'Select';
    final placeholder =
        widget.element.config['placeholder'] as String? ?? 'Choose an option';
    final required = widget.element.config['required'] as bool? ?? false;
    final interactive = widget.mode != RenderMode.builder;

    return FormFieldShell(
      label: label,
      required: required,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: (interactive && _options.isNotEmpty)
                ? () => _showBottomSheet(context)
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                horizontal: OTokens.s3,
                vertical: OTokens.s3,
              ),
              decoration: BoxDecoration(
                color: pal.bgSurface,
                borderRadius: BorderRadius.circular(OTokens.radiusSm),
                border: Border.all(color: pal.borderSubtle),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedLabel ??
                          (_loading
                              ? 'Loading…'
                              : (_error != null
                                  ? '— (load failed)'
                                  : placeholder)),
                      style: GoogleFonts.inter(
                        fontSize: OTokens.textSm,
                        color: _selectedLabel != null
                            ? pal.textPrimary
                            : pal.textMuted,
                      ),
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(LucideIcons.chevronsUpDown,
                        size: 14, color: pal.textMuted),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFFB91C1C),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showBottomSheet(BuildContext context) {
    final pal = OPaletteScope.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: pal.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(OTokens.radiusLg)),
      ),
      builder: (_) => ListView(
        shrinkWrap: true,
        children: _options
            .map((opt) => ListTile(
                  title: Text(
                    opt.label,
                    style: GoogleFonts.inter(
                      fontSize: OTokens.textSm,
                      color: pal.textPrimary,
                    ),
                  ),
                  trailing: _selectedValue == opt.value
                      ? Icon(LucideIcons.check,
                          size: 16, color: pal.primaryBlue)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedValue = opt.value;
                      _selectedLabel = opt.label;
                    });
                    FormScope.maybeOf(context)
                        ?.report(widget.element.id, opt.value);
                    // Also publish to the page-scoped element-value map so
                    // standalone (non-form) dropdowns can be referenced via
                    // `{{element.<id>.value}}` in sibling elements' bindings.
                    final pageId = _findPageId(context);
                    if (pageId != null) {
                      ref
                          .read(bindingContextProvider.notifier)
                          .setElementValue(pageId, widget.element.id, opt.value);
                    }
                    Navigator.pop(context);
                  },
                ))
            .toList(),
      ),
    );
  }
}
