import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../binding/expression_resolver.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../../page_renderer_widget.dart';
import '../element_renderer.dart';
import 'data_fetch.dart';

/// Kanban board bound to an API source. Honors:
///   - config.columns: list of {id, title, color, statusValue} — each
///     defines a column and the value of `groupBy` that maps to it.
///   - config.groupBy: row field used to bucket items into columns
///     (defaults to "status").
///   - config.cardConfig.titleField / subtitleField / tagField / dateField
///   - config.cardConfig.footerActions: list of
///     {label, showWhen: "status == 'pending'", method, endpoint, variant}.
///     The widget evaluates `showWhen` against the card row and shows
///     buttons; clicking POSTs/PATCHes the endpoint then refreshes the
///     board.
class KanbanElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const KanbanElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  ConsumerState<KanbanElement> createState() => _KanbanElementState();
}

class _KanbanElementState extends ConsumerState<KanbanElement> {
  int _refreshTick = 0;

  void _refresh() => setState(() => _refreshTick++);

  @override
  Widget build(BuildContext context) {
    final binding = widget.element.dataBinding;
    final ctxMap = ref.watch(bindingContextProvider);
    final ctx = ctxMap[widget.pageId];
    final cfg = widget.element.config;
    final cols = _parseColumns(cfg['columns'], OPaletteScope.of(context));
    final groupBy = (cfg['groupBy'] as String?) ?? 'status';
    final cardCfg = (cfg['cardConfig'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final emptyMsg = (cfg['emptyStateMessage'] as String?) ?? '';

    if (binding == null || widget.mode == RenderMode.builder) {
      // Designer fixtures
      return _board(cols: cols, items: const [], cardCfg: cardCfg, groupBy: groupBy, emptyMsg: 'Bind data to see cards.');
    }
    if (ctx == null) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    return KeyedSubtree(
      // Re-runs the FutureBuilder after a status mutation.
      key: ValueKey('kanban-$_refreshTick'),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchBindingRows(ctx, binding),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Failed to load: ${snap.error}',
                  style: GoogleFonts.inter(fontSize: OTokens.textSm, color: OPaletteScope.of(context).lossRed)),
            );
          }
          return _board(
            cols: cols,
            items: snap.data ?? const [],
            cardCfg: cardCfg,
            groupBy: groupBy,
            emptyMsg: emptyMsg,
          );
        },
      ),
    );
  }

  Widget _board({
    required List<_ColDef> cols,
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> cardCfg,
    required String groupBy,
    required String emptyMsg,
  }) {
    if (cols.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Kanban requires config.columns to be defined.',
            style: GoogleFonts.inter(color: OPaletteScope.of(context).textMuted)),
      );
    }
    final buckets = <String, List<Map<String, dynamic>>>{
      for (final c in cols) c.statusValue: [],
    };
    for (final it in items) {
      final v = '${it[groupBy] ?? ""}';
      (buckets[v] ?? (buckets[v] = [])).add(it);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final col in cols) ...[
          Expanded(
            child: _ColumnView(
              def: col,
              items: buckets[col.statusValue] ?? const [],
              cardCfg: cardCfg,
              pageId: widget.pageId,
              onActionDone: _refresh,
              emptyMsg: items.isEmpty ? emptyMsg : '',
            ),
          ),
          if (col != cols.last) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _ColDef {
  final String title;
  final String statusValue;
  final Color color;
  const _ColDef({required this.title, required this.statusValue, required this.color});
}

List<_ColDef> _parseColumns(dynamic raw, OPaletteData pal) {
  if (raw is! List) return const [];
  // A column colour may be a `token:<role>` reference (preferred — follows the
  // brand and brightness), a named shorthand, or one of the literal hexes older
  // page definitions were authored with.
  Color colorFor(String? key) {
    if (key == null) return pal.textMuted;
    if (key.startsWith('token:')) {
      return pal.role(key.substring(6)) ?? pal.textMuted;
    }
    return switch (key) {
      '#94a3b8' => pal.textMuted,
      '#2563eb' => pal.primaryBlue,
      '#f59e0b' => pal.warningAmber,
      '#10b981' => pal.gainGreen,
      '#ef4444' => pal.lossRed,
      'blue' => pal.neutralBlue,
      'green' => pal.gainGreen,
      'amber' => pal.warningAmber,
      'red' => pal.lossRed,
      'violet' => pal.accentViolet,
      _ => pal.textMuted,
    };
  }
  return raw.whereType<Map>().map((c) {
    final color = c['color'] as String?;
    return _ColDef(
      title: c['title'] as String? ?? '',
      statusValue: c['statusValue'] as String? ?? (c['id'] as String? ?? ''),
      color: colorFor(color),
    );
  }).toList();
}

class _ColumnView extends StatelessWidget {
  final _ColDef def;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> cardCfg;
  final String pageId;
  final VoidCallback onActionDone;
  final String emptyMsg;

  const _ColumnView({
    required this.def,
    required this.items,
    required this.cardCfg,
    required this.pageId,
    required this.onActionDone,
    required this.emptyMsg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minHeight: 280),
      decoration: BoxDecoration(
        color: OPaletteScope.of(context).bgGlass,
        borderRadius: BorderRadius.circular(OTokens.radiusMd),
        border: Border.all(color: OPaletteScope.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: def.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(def.title,
                    style: GoogleFonts.inter(
                      fontSize: OTokens.textSm,
                      fontWeight: FontWeight.w600,
                      color: def.color,
                    )),
              ),
              Text('${items.length}',
                  style: GoogleFonts.inter(fontSize: OTokens.textXs, color: OPaletteScope.of(context).textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _KanbanCard(
                item: it,
                cardCfg: cardCfg,
                pageId: pageId,
                onActionDone: onActionDone,
              ),
            ),
          if (items.isEmpty && emptyMsg.isEmpty)
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text('—',
                  style: GoogleFonts.inter(fontSize: 12, color: OPaletteScope.of(context).textMuted)),
            ),
          if (items.isEmpty && emptyMsg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(emptyMsg,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 11, color: OPaletteScope.of(context).textMuted)),
            ),
        ],
      ),
    );
  }
}

class _KanbanCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic> cardCfg;
  final String pageId;
  final VoidCallback onActionDone;

  const _KanbanCard({
    required this.item,
    required this.cardCfg,
    required this.pageId,
    required this.onActionDone,
  });

  @override
  ConsumerState<_KanbanCard> createState() => _KanbanCardState();
}

class _KanbanCardState extends ConsumerState<_KanbanCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cardCfg;
    final it = widget.item;
    final titleField = cfg['titleField'] as String? ?? 'title';
    final subtitleField = cfg['subtitleField'] as String?;
    final tagField = cfg['tagField'] as String?;
    final dateField = cfg['dateField'] as String?;
    final actions = (cfg['footerActions'] as List?) ?? const [];

    final title = '${it[titleField] ?? ""}';
    final subtitle = subtitleField == null ? '' : '${it[subtitleField] ?? ""}';
    final tags = (tagField == null ? const [] : (it[tagField] as List? ?? const [])).cast<dynamic>();
    final dateStr = dateField == null ? '' : '${it[dateField] ?? ""}';

    final visibleActions = <Map<String, dynamic>>[];
    for (final a in actions) {
      if (a is! Map) continue;
      final show = a['showWhen'] as String?;
      if (show == null || _evalShowWhen(show, it)) {
        visibleActions.add(Map<String, dynamic>.from(a));
      }
    }

    final cardWidget = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OPaletteScope.of(context).bgRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: OPaletteScope.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_humanize(title),
              style: GoogleFonts.inter(
                  fontSize: OTokens.textSm, fontWeight: FontWeight.w600, color: OPaletteScope.of(context).textBright)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: OPaletteScope.of(context).textMuted)),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: tags
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: OPaletteScope.of(context).bgGlass,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('$t',
                            style: GoogleFonts.inter(
                                fontSize: 10, color: OPaletteScope.of(context).textMuted, fontWeight: FontWeight.w500)),
                      ))
                  .toList(),
            ),
          ],
          if (dateStr.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_relative(dateStr),
                style: GoogleFonts.inter(fontSize: 11, color: OPaletteScope.of(context).textMuted)),
          ],
          if (visibleActions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: visibleActions
                  .map((a) => OutlinedButton(
                        onPressed: _busy ? null : () => _run(a),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          minimumSize: const Size(0, 26),
                          textStyle: GoogleFonts.inter(
                              fontSize: 11, fontWeight: FontWeight.w600),
                          foregroundColor: _variantColor(a['variant'] as String?),
                          side: BorderSide(
                              color: _variantColor(a['variant'] as String?).withValues(alpha: 0.5)),
                        ),
                        child: Text(a['label'] as String? ?? 'Action'),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
    // Optional click-to-open: `cardConfig.cardRoute` (templated with
    // {{card.<field>}} + {{route.<param>}}) navigates to a detail page.
    final cardRoute = widget.cardCfg['cardRoute'] as String?;
    if (cardRoute == null || cardRoute.isEmpty) return cardWidget;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openCard(cardRoute),
        child: cardWidget,
      ),
    );
  }

  void _openCard(String route) {
    var target = _substituteCardTokens(route, widget.item);
    final ctxReg = ref.read(bindingContextProvider);
    final ctx = ctxReg[widget.pageId] ??
        (ctxReg.values.isNotEmpty ? ctxReg.values.first : null);
    if (ctx != null && target.contains('{{')) {
      try {
        target = ExpressionResolver(ctx).resolveValueSync(target).toString();
      } catch (_) {/* fall back to the partially-resolved route */}
    }
    final cbReg = ref.read(pageRendererCallbacksProvider);
    final rawCb = cbReg[widget.pageId] ??
        (cbReg.values.isNotEmpty ? cbReg.values.first : null);
    if (rawCb is PageRendererCallbacks) {
      rawCb.onNavigate?.call(target, const <String, dynamic>{});
    }
  }

  Future<void> _run(Map<String, dynamic> action) async {
    setState(() => _busy = true);
    try {
      final ctxMap = ref.read(bindingContextProvider);
      final ctx = ctxMap[widget.pageId];
      if (ctx == null) return;

      // endpoint may be a template; substitute {{card.x}} from item, then
      // pull base URL from the data source named 'restoration' (or first
      // registered source) so the host doesn't have to be in the template.
      var endpoint = action['endpoint'] as String? ?? '';
      endpoint = _substituteCardTokens(endpoint, widget.item);

      String url;
      Map<String, String> headers = {};
      if (endpoint.startsWith('http')) {
        url = endpoint;
      } else {
        final source = ctx.dataSources.values.isEmpty ? null : ctx.dataSources.values.first;
        if (source == null) return;
        url = '${source.baseUrl ?? ""}$endpoint';
        final token = source.authTokenProvider?.call();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      }
      headers['Content-Type'] = 'application/json';

      final method = (action['method'] as String? ?? 'POST').toLowerCase();
      final body = action['body'];

      final dio = Dio();
      await dio.request<dynamic>(
        url,
        options: Options(method: method, headers: headers),
        data: body,
      );
      // Bust the cache on every registered source so the board refreshes.
      for (final s in ctx.dataSources.values) {
        s.invalidate();
      }
      widget.onActionDone();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Very small evaluator for `showWhen` strings like:
  ///   status == 'pending'
  ///   status != 'complete'
  ///   status in ('pending','active','on_hold')
  bool _evalShowWhen(String expr, Map<String, dynamic> row) {
    // status == 'X'
    final eq = RegExp(r"^\s*([\w_]+)\s*==\s*'([^']*)'\s*$").firstMatch(expr);
    if (eq != null) return '${row[eq.group(1)] ?? ""}' == eq.group(2);
    // status != 'X'
    final ne = RegExp(r"^\s*([\w_]+)\s*!=\s*'([^']*)'\s*$").firstMatch(expr);
    if (ne != null) return '${row[ne.group(1)] ?? ""}' != ne.group(2);
    // status in ('a','b','c')
    final inExpr = RegExp(r"^\s*([\w_]+)\s+in\s*\(([^)]+)\)\s*$").firstMatch(expr);
    if (inExpr != null) {
      final field = inExpr.group(1)!;
      final vals = inExpr.group(2)!.split(',').map((s) {
        final t = s.trim();
        if (t.startsWith("'") && t.endsWith("'")) return t.substring(1, t.length - 1);
        return t;
      }).toSet();
      return vals.contains('${row[field] ?? ""}');
    }
    return true; // unrecognised → show
  }

  String _substituteCardTokens(String s, Map<String, dynamic> item) {
    return s.replaceAllMapped(RegExp(r'\{\{card\.([^}]+)\}\}'), (m) {
      return '${item[m.group(1)!] ?? ""}';
    });
  }

  Color _variantColor(String? v) => switch (v) {
        'primary' => OPaletteScope.of(context).gainGreen,
        'danger' => OPaletteScope.of(context).lossRed,
        'secondary' => OPaletteScope.of(context).textMuted,
        _ => OPaletteScope.of(context).neutralBlue,
      };

  String _humanize(String key) {
    if (key.isEmpty) return key;
    return key.split('_').map((s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1)).join(' ');
  }

  String _relative(String v) {
    try {
      final dt = DateTime.parse(v);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return v;
    }
  }
}
