import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../binding/expression_resolver.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../../../providers/section_counts_provider.dart';
import '../data/data_fetch.dart';
import '../element_renderer.dart';

/// Editable, API-backed data grid (the Mitigation workspace's moisture &
/// equipment logs). Loads rows from `element.dataBinding` (GET), renders them
/// as a spreadsheet, and persists per-row mutations against templated URLs:
///   - `config.rowCreateUrl`  → POST  (Add row)
///   - `config.rowUpdateUrl`  → PATCH (inline cell edit; `{{row.id}}`)
///   - `config.rowDeleteUrl`  → DELETE (`{{row.id}}`)
/// Flags: `allowAdd` / `allowEdit` / `allowDelete` (default true). Set
/// `allowEdit:false` for append-only logs (e.g. immutable moisture readings).
///
/// Columns (`config.columns[]`): `{field, header, type, editable, width,
/// renderer, options, compute}` where `type` ∈
/// text|number|date|select|bool|computed (`bool` = a star toggle that PATCHes
/// the boolean field immediately — e.g. a note's `pinned`).
/// `config.colorRules[]` tints rows by a numeric threshold ({field, op, value,
/// tint}); first match wins (a rule with no field is the default).
class DataGridElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const DataGridElement({
    super.key,
    required this.element,
    required this.mode,
    this.pageId = '',
  });

  @override
  ConsumerState<DataGridElement> createState() => _DataGridElementState();
}

class _DataGridElementState extends ConsumerState<DataGridElement> {
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _draft; // unsaved new row (null = not adding)
  bool _loading = true;
  bool _savingDraft = false;
  Object? _error;
  void Function()? _cancelRefresh;

  Map<String, dynamic> get _cfg => widget.element.config;
  bool get _allowAdd => _cfg['allowAdd'] != false && _cfg['rowCreateUrl'] != null;
  bool get _allowEdit => _cfg['allowEdit'] != false && _cfg['rowUpdateUrl'] != null;
  bool get _allowDelete =>
      _cfg['allowDelete'] != false && _cfg['rowDeleteUrl'] != null;

  @override
  void initState() {
    super.initState();
    if (widget.mode == RenderMode.builder) {
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      final ctx = ref.read(bindingContextProvider)[widget.pageId];
      final binding = widget.element.dataBinding;
      if (ctx != null && binding != null) {
        _cancelRefresh = bindRefreshOn(ctx, binding, () async {
          await _load();
        });
      }
    });
  }

  @override
  void dispose() {
    _cancelRefresh?.call();
    super.dispose();
  }

  BindingContext? get _ctx => ref.read(bindingContextProvider)[widget.pageId];

  /// Resolve `{{i18n.<key>}}` tokens in a label synchronously (column headers /
  /// empty state / title render in build(), so we can't await the async
  /// resolver). Falls back to the verbatim token on a miss.
  String _i18n(dynamic raw) {
    final s = raw?.toString() ?? '';
    final ctx = _ctx;
    if (ctx == null || !s.contains('{{i18n.')) return s;
    return s.replaceAllMapped(RegExp(r'\{\{i18n\.([^}]+)\}\}'), (m) {
      final v = ctx.translator.translate(m.group(1)!.trim());
      return (v ?? m.group(0))?.toString() ?? '';
    });
  }

  Future<void> _load() async {
    final ctx = _ctx;
    final binding = widget.element.dataBinding;
    if (ctx == null || binding == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final rows = await fetchBindingRows(ctx, binding);
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
          _error = null;
        });
        ref
            .read(sectionCountsProvider.notifier)
            .report(widget.pageId, widget.element.sectionId, rows.length);
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  // ── Persistence (POST/PATCH/DELETE via resolved templated URLs) ──
  Future<dynamic> _write(
    String method,
    String urlTemplate,
    Map<String, dynamic> row, {
    Map<String, dynamic>? body,
  }) async {
    final ctx = _ctx;
    if (ctx == null) return null;
    final resolver = ExpressionResolver(ctx);
    var url = urlTemplate.replaceAllMapped(
      RegExp(r'\{\{row\.([^}]+)\}\}'),
      (m) => '${row[m.group(1)!] ?? ''}',
    );
    url = await resolver.resolve(url);
    final headers = <String, String>{'Content-Type': 'application/json'};
    final binding = widget.element.dataBinding;
    if (binding != null) {
      for (final e in binding.headers.entries) {
        final v = await resolver.resolve(e.value);
        if (v.isNotEmpty) headers[e.key] = v;
      }
    }
    // Resolve `{{route.*}}`/`{{session.*}}` tokens in string body values
    // (e.g. newRowDefaults `{sub_job_id: '{{route.subJobId}}'}`).
    Map<String, dynamic>? sendBody = body;
    if (body != null) {
      sendBody = {};
      for (final e in body.entries) {
        var v = e.value;
        if (v is String && v.contains('{{')) v = await resolver.resolve(v);
        sendBody[e.key] = v;
      }
    }
    final resp = await Dio().request<dynamic>(
      url,
      options: Options(method: method, headers: headers),
      data: sendBody,
    );
    for (final s in ctx.dataSources.values) {
      s.invalidate();
    }
    final ev = _cfg['refreshEvent'] as String?;
    if (ev != null && ev.isNotEmpty) ctx.eventBus.publish(ev);
    return resp.data;
  }

  Future<void> _commitEdit(
      Map<String, dynamic> row, _GridCol col, dynamic value) async {
    final urlTemplate = _cfg['rowUpdateUrl'] as String?;
    if (urlTemplate == null) return;
    if ('${row[col.field]}' == '$value') return; // no-op
    final previous = row[col.field];
    setState(() => row[col.field] = value); // optimistic
    try {
      await _write('PATCH', urlTemplate, row, body: {col.field: value});
    } catch (e) {
      if (mounted) {
        setState(() => row[col.field] = previous);
        _toast('Save failed: $e');
      }
    }
  }

  Future<void> _saveDraft() async {
    final urlTemplate = _cfg['rowCreateUrl'] as String?;
    final draft = _draft;
    if (urlTemplate == null || draft == null) return;
    setState(() => _savingDraft = true);
    try {
      final created =
          await _write('POST', urlTemplate, const {}, body: Map.of(draft));
      if (mounted) {
        setState(() {
          if (created is Map) {
            _rows.insert(0, Map<String, dynamic>.from(created));
          }
          _draft = null;
          _savingDraft = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingDraft = false);
        _toast('Add failed: $e');
      }
    }
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final urlTemplate = _cfg['rowDeleteUrl'] as String?;
    if (urlTemplate == null) return;
    setState(() => _rows.remove(row));
    try {
      await _write('DELETE', urlTemplate, row);
    } catch (e) {
      if (mounted) {
        _toast('Delete failed: $e');
        await _load();
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final cols = _parseCols(_cfg['columns']);
    final title = _cfg['title'] != null ? _i18n(_cfg['title']) : null;
    final addLabel = _cfg['addLabel'] != null ? _i18n(_cfg['addLabel']) : '+ Add';

    return Container(
      decoration: BoxDecoration(
        color: pal.bgSurface,
        borderRadius: BorderRadius.circular(OTokens.radiusLg),
        border: Border.all(color: pal.borderSubtle),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 1)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null || _allowAdd)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  OTokens.s4, OTokens.s3, OTokens.s3, OTokens.s3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title ?? '',
                      style: GoogleFonts.inter(
                        fontSize: OTokens.textMd,
                        fontWeight: FontWeight.w700,
                        color: pal.textBright,
                      ),
                    ),
                  ),
                  if (_allowAdd && widget.mode != RenderMode.builder)
                    TextButton(
                      onPressed: _draft == null
                          ? () => setState(() => _draft = Map<String, dynamic>.from(
                              (_cfg['newRowDefaults'] as Map?)?.cast<String, dynamic>() ??
                                  const {}))
                          : null,
                      style: TextButton.styleFrom(
                        backgroundColor: pal.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: GoogleFonts.inter(
                            fontSize: OTokens.textXs, fontWeight: FontWeight.w600),
                      ),
                      child: Text(addLabel),
                    ),
                ],
              ),
            ),
          // Header row
          _gridRow(
            pal: pal,
            cols: cols,
            vPad: 10,
            decoration: BoxDecoration(
              color: pal.bgRaised,
              border: Border(bottom: BorderSide(color: pal.borderSubtle)),
            ),
            trailing: _allowDelete ? const SizedBox(width: 44) : null,
            cellBuilder: (c) => Text(
              _i18n(c.header).toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: OTokens.textXs,
                fontWeight: FontWeight.w700,
                color: pal.textMuted,
                letterSpacing: 0.4,
              ),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Failed to load: $_error',
                  style: GoogleFonts.inter(fontSize: OTokens.textSm, color: pal.lossRed)),
            )
          else ...[
            if (_draft != null) _draftRow(pal, cols),
            for (final row in _rows) _dataRow(pal, cols, row),
            if (_rows.isEmpty && _draft == null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _cfg['emptyStateMessage'] != null
                      ? _i18n(_cfg['emptyStateMessage'])
                      : 'No rows yet.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: OTokens.textSm, color: pal.textMuted),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// One table row laid out with thin vertical separators between columns
  /// (and before the trailing actions column). Cells stretch to the row's
  /// height via IntrinsicHeight so the separators form continuous, aligned
  /// rules — keeping dense grids readable.
  Widget _gridRow({
    required OPaletteData pal,
    required List<_GridCol> cols,
    required double vPad,
    required Widget Function(_GridCol col) cellBuilder,
    Widget? trailing,
    BoxDecoration? decoration,
  }) {
    final divider = pal.borderSubtle;
    final children = <Widget>[];
    for (int i = 0; i < cols.length; i++) {
      final drawRight = i != cols.length - 1 || trailing != null;
      children.add(Expanded(
        flex: cols[i].flex,
        child: Container(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: vPad),
          decoration: drawRight
              ? BoxDecoration(border: Border(right: BorderSide(color: divider)))
              : null,
          child: cellBuilder(cols[i]),
        ),
      ));
    }
    if (trailing != null) children.add(trailing);
    return Container(
      decoration: decoration,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _dataRow(OPaletteData pal, List<_GridCol> cols, Map<String, dynamic> row) {
    final grid = _gridRow(
      pal: pal,
      cols: cols,
      vPad: 8,
      decoration: BoxDecoration(
        color: _tintFor(pal, row),
        border: Border(top: BorderSide(color: pal.borderSubtle)),
      ),
      trailing: _allowDelete
          ? SizedBox(
              width: 44,
              child: IconButton(
                icon: Icon(Icons.close, size: 16, color: pal.textMuted),
                tooltip: 'Delete',
                onPressed: () => _deleteRow(row),
              ),
            )
          : null,
      cellBuilder: (c) => _cell(pal, c, row, draft: false),
    );
    // Opt-in row navigation: `config.rowAction.to` (with {{row.<field>}} +
    // {{route.*}} tokens) makes the whole row tappable → navigate. Used by
    // read-only list grids (e.g. the assignment queue) to open a record.
    final cfg = widget.element.config['rowAction'];
    final route = (cfg is Map) ? cfg['to'] as String? : null;
    if (route == null || route.isEmpty) return grid;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _openRow(route, row),
        child: grid,
      ),
    );
  }

  void _openRow(String template, Map<String, dynamic> row) {
    var target = template;
    row.forEach((k, v) => target = target.replaceAll('{{row.$k}}', '$v'));
    final ctx = _ctx;
    if (ctx != null && target.contains('{{')) {
      try {
        target = ExpressionResolver(ctx).resolveValueSync(target).toString();
      } catch (_) {/* fall back to partially-resolved route */}
    }
    final cbReg = ref.read(pageRendererCallbacksProvider);
    final raw = cbReg[widget.pageId] ??
        (cbReg.values.isNotEmpty ? cbReg.values.first : null);
    if (raw != null) {
      try {
        (raw as dynamic).onNavigate?.call(target, const <String, dynamic>{});
      } catch (_) {/* host without a navigate callback */}
    }
  }

  Widget _draftRow(OPaletteData pal, List<_GridCol> cols) {
    return _gridRow(
      pal: pal,
      cols: cols,
      vPad: 8,
      decoration: BoxDecoration(
        color: pal.primaryBlue.withValues(alpha: 0.05),
        border: Border(top: BorderSide(color: pal.primaryBlue.withValues(alpha: 0.3))),
      ),
      trailing: SizedBox(
        width: 44,
        child: _savingDraft
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(
                icon: Icon(Icons.check, size: 18, color: pal.gainGreen),
                tooltip: 'Save',
                onPressed: _saveDraft,
              ),
      ),
      cellBuilder: (c) => _cell(pal, c, _draft!, draft: true),
    );
  }

  /// One cell: editable input when allowed (or always for the draft row),
  /// otherwise a read-only rendering.
  Widget _cell(OPaletteData pal, _GridCol c, Map<String, dynamic> row,
      {required bool draft}) {
    final value = row[c.field];
    if (c.type == 'computed') {
      return Text(_computed(c, row),
          style: GoogleFonts.jetBrainsMono(fontSize: OTokens.textSm, color: pal.textPrimary));
    }
    final editable = draft || (_allowEdit && c.editable);
    if (!editable) {
      return _readOnly(pal, c, value);
    }
    void onCommit(dynamic v) {
      if (draft) {
        setState(() => row[c.field] = v);
      } else {
        _commitEdit(row, c, v);
      }
    }

    switch (c.type) {
      case 'select':
        return _SelectCell(value: value, options: c.options, onChanged: onCommit);
      case 'bool':
        return _BoolCell(value: value == true, onChanged: onCommit);
      case 'date':
        return _DateCell(value: value?.toString(), onCommit: onCommit);
      case 'number':
        return _TextCell(
            key: ValueKey('${row['id'] ?? 'draft'}-${c.field}'),
            initial: value?.toString() ?? '',
            number: true,
            onCommit: (s) => onCommit(s.isEmpty ? null : num.tryParse(s) ?? s));
      default:
        return _TextCell(
            key: ValueKey('${row['id'] ?? 'draft'}-${c.field}'),
            initial: value?.toString() ?? '',
            number: false,
            onCommit: onCommit);
    }
  }

  Widget _readOnly(OPaletteData pal, _GridCol c, dynamic value) {
    if (c.type == 'bool') {
      final on = value == true;
      return Icon(on ? Icons.star : Icons.star_border,
          size: 18, color: on ? pal.warningAmber : pal.textMuted);
    }
    final s = value == null ? '' : '$value';
    switch (c.renderer) {
      case 'badge':
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: pal.primaryBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(_humanize(s),
                style: GoogleFonts.inter(
                    fontSize: OTokens.textXs, fontWeight: FontWeight.w600, color: pal.primaryBlue)),
          ),
        );
      case 'mono':
        return Text(s,
            style: GoogleFonts.jetBrainsMono(fontSize: OTokens.textSm, color: pal.textBright));
      case 'relative_time':
        return Text(_relative(s),
            style: GoogleFonts.inter(fontSize: OTokens.textSm, color: pal.textMuted));
      default:
        return Text(c.type == 'select' ? _humanize(s) : s,
            style: GoogleFonts.inter(fontSize: OTokens.textSm, color: pal.textPrimary),
            overflow: TextOverflow.ellipsis);
    }
  }

  // ── Helpers ──
  Color? _tintFor(OPaletteData pal, Map<String, dynamic> row) {
    final rules = _cfg['colorRules'];
    if (rules is! List) return null;
    for (final r in rules) {
      if (r is! Map) continue;
      final field = r['field'] as String?;
      if (field == null) return _tintColor(pal, r['tint']); // default catch-all
      final op = r['op'] as String? ?? 'gte';
      final expectedNum = num.tryParse('${r['value']}');
      if (expectedNum == null) {
        // String comparison (e.g. drying_status == 'high').
        final hit = switch (op) {
          'eq' => '${row[field]}' == '${r['value']}',
          'ne' => '${row[field]}' != '${r['value']}',
          _ => false,
        };
        if (hit) return _tintColor(pal, r['tint']);
        continue;
      }
      final actual = num.tryParse('${row[field]}');
      if (actual == null) continue;
      final hit = switch (op) {
        'gt' => actual > expectedNum,
        'gte' => actual >= expectedNum,
        'lt' => actual < expectedNum,
        'lte' => actual <= expectedNum,
        'eq' => actual == expectedNum,
        _ => false,
      };
      if (hit) return _tintColor(pal, r['tint']);
    }
    return null;
  }

  Color? _tintColor(OPaletteData pal, dynamic tint) {
    switch ('$tint') {
      case 'high':
        return pal.lossRed.withValues(alpha: 0.08);
      case 'med':
        return pal.warningAmber.withValues(alpha: 0.12);
      case 'ok':
        return pal.gainGreen.withValues(alpha: 0.08);
      default:
        return null;
    }
  }

  String _computed(_GridCol c, Map<String, dynamic> row) {
    final expr = c.compute ?? '';
    final m = RegExp(r'^days_between\(([^,]+),\s*([^)]*)\)$').firstMatch(expr);
    if (m != null) {
      final a = DateTime.tryParse('${row[m.group(1)!.trim()] ?? ''}');
      final bRaw = row[m.group(2)!.trim()];
      final b = bRaw == null || '$bRaw'.isEmpty
          ? DateTime.now()
          : DateTime.tryParse('$bRaw');
      if (a != null && b != null) return '${b.difference(a).inDays}';
    }
    final direct = row[expr];
    return direct == null ? '' : '$direct';
  }

  static String _humanize(String k) => k.isEmpty
      ? k
      : k
          .split('_')
          .map((s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1))
          .join(' ');

  static String _relative(String v) {
    final dt = DateTime.tryParse(v);
    if (dt == null) return v;
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

// ── Column model ──
class _GridCol {
  final String field;
  final String header;
  final String type; // text|number|date|select|computed
  final String renderer; // default|badge|mono|relative_time
  final bool editable;
  final int flex;
  final List<Map<String, dynamic>> options; // for select
  final String? compute;
  const _GridCol({
    required this.field,
    required this.header,
    required this.type,
    required this.renderer,
    required this.editable,
    required this.flex,
    required this.options,
    required this.compute,
  });
}

List<_GridCol> _parseCols(dynamic raw) {
  if (raw is! List) return const [];
  final out = <_GridCol>[];
  for (final c in raw) {
    if (c is! Map) continue;
    final opts = <Map<String, dynamic>>[];
    final rawOpts = c['options'];
    if (rawOpts is List) {
      for (final o in rawOpts) {
        if (o is Map) {
          opts.add({'value': o['value'], 'label': o['label'] ?? o['value']});
        } else {
          opts.add({'value': o, 'label': o});
        }
      }
    }
    out.add(_GridCol(
      field: (c['field'] as String?) ?? '',
      header: (c['header'] as String?) ?? '',
      type: (c['type'] as String?) ?? 'text',
      renderer: (c['renderer'] as String?) ?? 'default',
      editable: c['editable'] != false,
      flex: c['width'] == 'flex' ? 3 : ((c['width'] as num?)?.toInt() ?? 1),
      options: opts,
      compute: c['compute'] as String?,
    ));
  }
  return out;
}

// ── Inline editors ──
InputDecoration _cellDecoration(OPaletteData pal) => InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      filled: true,
      fillColor: pal.bgRaised,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: pal.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: pal.primaryBlue, width: 1.5),
      ),
    );

class _TextCell extends StatefulWidget {
  final String initial;
  final bool number;
  final ValueChanged<String> onCommit;
  const _TextCell(
      {super.key, required this.initial, required this.number, required this.onCommit});
  @override
  State<_TextCell> createState() => _TextCellState();
}

class _TextCellState extends State<_TextCell> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  late final FocusNode _f = FocusNode();
  String _last = '';

  @override
  void initState() {
    super.initState();
    _last = widget.initial;
    _f.addListener(() {
      if (!_f.hasFocus && _c.text != _last) {
        _last = _c.text;
        widget.onCommit(_c.text);
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    return TextField(
      controller: _c,
      focusNode: _f,
      keyboardType: widget.number ? const TextInputType.numberWithOptions(decimal: true) : null,
      inputFormatters: widget.number
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))]
          : null,
      style: GoogleFonts.inter(fontSize: OTokens.textSm, color: pal.textPrimary),
      decoration: _cellDecoration(pal),
      onSubmitted: (v) {
        _last = v;
        widget.onCommit(v);
      },
    );
  }
}

class _SelectCell extends StatelessWidget {
  final dynamic value;
  final List<Map<String, dynamic>> options;
  final ValueChanged<dynamic> onChanged;
  const _SelectCell(
      {required this.value, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final values = options.map((o) => '${o['value']}').toList();
    final current = values.contains('$value') ? '$value' : null;
    return DropdownButtonFormField<String>(
      initialValue: current,
      isDense: true,
      isExpanded: true,
      decoration: _cellDecoration(pal),
      style: GoogleFonts.inter(fontSize: OTokens.textSm, color: pal.textPrimary),
      items: [
        for (final o in options)
          DropdownMenuItem(value: '${o['value']}', child: Text('${o['label']}')),
      ],
      onChanged: (v) => onChanged(v),
    );
  }
}

class _BoolCell extends StatelessWidget {
  final bool value;
  final ValueChanged<dynamic> onChanged;
  const _BoolCell({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: Icon(value ? Icons.star : Icons.star_border,
            size: 20, color: value ? pal.warningAmber : pal.textMuted),
        tooltip: value ? 'Unpin' : 'Pin',
        onPressed: () => onChanged(!value),
      ),
    );
  }
}

class _DateCell extends StatelessWidget {
  final String? value;
  final ValueChanged<dynamic> onCommit;
  const _DateCell({required this.value, required this.onCommit});
  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final dt = value == null ? null : DateTime.tryParse(value!);
    final label = dt == null
        ? 'Set date'
        : '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: dt ?? DateTime(2026),
          firstDate: DateTime(2015),
          lastDate: DateTime(2035),
        );
        if (picked != null) onCommit(picked.toIso8601String());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: pal.bgRaised,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: pal.borderSubtle),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: OTokens.textSm,
                color: dt == null ? pal.textMuted : pal.textPrimary)),
      ),
    );
  }
}
