import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../../page_renderer_widget.dart';
import '../element_renderer.dart';
import 'data_fetch.dart';

/// Resolves the dataBinding URL + headers, fetches via the matching
/// HttpDataSource (or plain Dio fallback), maps response rows through
/// config.columns. Supports per-cell `renderer` hints: default / badge /
/// tag_pills / color_swatch / relative_time / mono / boolean / icon.
///
/// When no dataBinding is configured the widget renders fixture rows so
/// the designer canvas has something to show.
class DataTableElement extends ConsumerWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const DataTableElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final binding = element.dataBinding;
    final ctxMap = ref.watch(bindingContextProvider);
    final ctx = ctxMap[pageId];
    final cfg = element.config;
    final columns = _parseColumns(cfg['columns']);
    final emptyTitle = cfg['emptyStateTitle'] as String? ?? 'Nothing here yet';
    final emptyMessage = cfg['emptyStateMessage'] as String? ?? '';

    if (binding == null || mode == RenderMode.builder) {
      return _shell(child: _fixtureBody(columns));
    }
    if (ctx == null) {
      return _shell(child: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ));
    }

    return _shell(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchBindingRows(ctx, binding),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) {
            return _ErrorRow(message: '${snap.error}');
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return _EmptyRow(title: emptyTitle, message: emptyMessage);
          }
          // Optional click navigation. Author shape:
          //   "config.rowAction": {"type": "navigate", "to": "/projects/{{row.id}}"}
          final rowActionMap = cfg['rowAction'] as Map<String, dynamic>?;
          return Column(
            children: [
              _HeaderRow(columns: columns),
              for (int i = 0; i < rows.length; i++)
                _BoundRow(
                  row: rows[i],
                  columns: columns,
                  alternate: i.isOdd,
                  isLast: i == rows.length - 1,
                  onTap: rowActionMap == null
                      ? null
                      : () => _fireRowAction(ref, rowActionMap, rows[i]),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Substitutes `{{row.<field>}}` tokens in the action's `to` template
  /// with values from the clicked row, then fires the host's
  /// `PageRendererCallbacks.onNavigate`.
  void _fireRowAction(
    WidgetRef ref,
    Map<String, dynamic> action,
    Map<String, dynamic> row,
  ) {
    final to = action['to'] as String? ?? '';
    if (to.isEmpty) return;
    final substituted = to.replaceAllMapped(
      RegExp(r'\{\{row\.([^}]+)\}\}'),
      (m) => '${row[m.group(1)!] ?? ''}',
    );
    final callbacks =
        ref.read(pageRendererCallbacksProvider)[pageId];
    if (callbacks is PageRendererCallbacks) {
      callbacks.onNavigate?.call(substituted, const {});
    }
  }

  Widget _shell({required Widget child}) {
    return Builder(
      builder: (context) {
        final pal = OPaletteScope.of(context);
        return Container(
          decoration: BoxDecoration(
            color: pal.bgSurface,
            borderRadius: BorderRadius.circular(OTokens.radiusLg),
            border: Border.all(color: pal.borderSubtle),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 1)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      },
    );
  }

  Widget _fixtureBody(List<TableColumn> columns) {
    // When unbound we still need to show *something* in the designer canvas.
    final placeholderColumns = columns.isEmpty
        ? [
            const TableColumn(header: 'Name', field: 'name', flex: 2),
            const TableColumn(header: 'Status', field: 'status'),
            const TableColumn(header: 'Value', field: 'value'),
          ]
        : columns;
    final placeholderRows = [
      {'name': 'Item One', 'status': 'active', 'value': '100'},
      {'name': 'Item Two', 'status': 'pending', 'value': '85'},
      {'name': 'Item Three', 'status': 'active', 'value': '240'},
    ];
    return Column(
      children: [
        _HeaderRow(columns: placeholderColumns),
        for (int i = 0; i < placeholderRows.length; i++)
          _BoundRow(
            row: placeholderRows[i],
            columns: placeholderColumns,
            alternate: i.isOdd,
            isLast: i == placeholderRows.length - 1,
          ),
      ],
    );
  }
}

// ── Column model ─────────────────────────────────────────────────────────

class TableColumn {
  final String header;
  final String field;
  final String renderer; // 'default' | 'badge' | 'tag_pills' | ...
  final int flex;

  const TableColumn({
    required this.header,
    required this.field,
    this.renderer = 'default',
    this.flex = 1,
  });
}

List<TableColumn> _parseColumns(dynamic raw) {
  if (raw is! List) return const [];
  final out = <TableColumn>[];
  for (final c in raw) {
    if (c is! Map) continue;
    out.add(TableColumn(
      header: (c['header'] as String?) ?? '',
      field: (c['field'] as String?) ?? '',
      renderer: (c['renderer'] as String?) ?? 'default',
      flex: c['width'] == 'flex' ? 3 : 1,
    ));
  }
  return out;
}

// ── Gridded cells ──────────────────────────────────────────────────────────

/// Lays out one table row's cells with thin vertical separators between
/// columns. Cells carry their own padding so the separators (and the row's
/// horizontal border) span the full cell height for a clean, readable grid.
/// Column flex is identical across header + every row, so the vertical lines
/// line up into continuous rules.
List<Widget> _gridCells(
  BuildContext context,
  List<TableColumn> columns,
  Widget Function(TableColumn col) cellBuilder,
) {
  // Same colour as the horizontal row borders so the grid reads evenly.
  // Drawn as a per-cell right BorderSide (not a 1px-wide Container) so it
  // renders crisply on web and spans the full cell height under stretch.
  final divider = OPaletteScope.of(context).borderSubtle;
  final out = <Widget>[];
  for (int i = 0; i < columns.length; i++) {
    out.add(Expanded(
      flex: columns[i].flex,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(
            horizontal: OTokens.s4, vertical: OTokens.s3),
        decoration: i == columns.length - 1
            ? null
            : BoxDecoration(
                border: Border(right: BorderSide(color: divider))),
        child: cellBuilder(columns[i]),
      ),
    ));
  }
  return out;
}

// ── Header row ───────────────────────────────────────────────────────────

class _HeaderRow extends StatelessWidget {
  final List<TableColumn> columns;
  const _HeaderRow({required this.columns});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: pal.bgRaised.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: pal.borderSubtle)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _gridCells(
            context,
            columns,
            (col) => Text(
              col.header.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: OTokens.textXs,
                fontWeight: FontWeight.w600,
                color: pal.textMuted,
                letterSpacing: 0.08,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bound row ────────────────────────────────────────────────────────────

class _BoundRow extends StatefulWidget {
  final Map<String, dynamic> row;
  final List<TableColumn> columns;
  final bool alternate;
  final bool isLast;
  final VoidCallback? onTap;

  const _BoundRow({
    required this.row,
    required this.columns,
    required this.alternate,
    required this.isLast,
    this.onTap,
  });

  @override
  State<_BoundRow> createState() => _BoundRowState();
}

class _BoundRowState extends State<_BoundRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final clickable = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: _hovered
                ? pal.bgHover.withValues(alpha: 0.6)
                : widget.alternate
                    ? pal.bgRaised.withValues(alpha: 0.2)
                    : Colors.transparent,
            border: widget.isLast
                ? null
                : Border(
                    bottom:
                        BorderSide(color: pal.borderSubtle, width: 1)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _gridCells(
                context,
                widget.columns,
                (col) => _renderCell(widget.row[col.field], col.renderer),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _renderCell(dynamic value, String renderer) {
    switch (renderer) {
      case 'badge':
        return _badgeCell(value);
      case 'tag_pills':
        return _tagPillsCell(value);
      case 'color_swatch':
        return _swatchCell(value);
      case 'relative_time':
        return _relativeTimeCell(value);
      case 'mono':
        return _monoCell(value);
      case 'boolean':
        return _booleanCell(value);
      case 'icon':
        return _iconCell(value);
      default:
        return _defaultCell(value);
    }
  }

  Widget _defaultCell(dynamic value) {
    final pal = OPaletteScope.of(context);
    return Text(
      _str(value),
      style: GoogleFonts.inter(
        fontSize: OTokens.textSm,
        color: pal.textPrimary,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _monoCell(dynamic value) {
    final pal = OPaletteScope.of(context);
    return Text(
      _str(value),
      style: GoogleFonts.jetBrainsMono(
        fontSize: OTokens.textSm,
        color: pal.textBright,
        fontWeight: FontWeight.w500,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _badgeCell(dynamic value) {
    final pal = OPaletteScope.of(context);
    final s = _str(value);
    final color = _badgeColor(s, pal);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          s,
          style: GoogleFonts.inter(
            fontSize: OTokens.textXs,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _tagPillsCell(dynamic value) {
    final pal = OPaletteScope.of(context);
    if (value is! List) return _defaultCell(value);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: value.map((t) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: pal.bgRaised,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$t',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: pal.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _swatchCell(dynamic value) {
    final pal = OPaletteScope.of(context);
    final hex = value is String && value.startsWith('#') && value.length == 7
        ? value
        : null;
    final color = hex == null
        ? pal.textMuted
        : Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: pal.borderSubtle),
      ),
    );
  }

  Widget _relativeTimeCell(dynamic value) {
    final pal = OPaletteScope.of(context);
    return Text(
      _relative(value),
      style: GoogleFonts.inter(
        fontSize: OTokens.textSm,
        color: pal.textMuted,
      ),
    );
  }

  Widget _booleanCell(dynamic value) {
    final pal = OPaletteScope.of(context);
    final on = value == true;
    return Icon(
      on ? Icons.check_circle : Icons.cancel,
      size: 18,
      color: on ? pal.gainGreen : pal.textMuted,
    );
  }

  Widget _iconCell(dynamic value) {
    return _defaultCell(value); // Phase-3: map name → IconData.
  }

  static String _str(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num || v is bool) return '$v';
    return v.toString();
  }

  static Color _badgeColor(String value, OPaletteData pal) {
    return switch (value.toLowerCase()) {
      'active' || 'open' || 'in_progress' => pal.neutralBlue,
      'pending' => pal.textMuted,
      'complete' || 'signed' || 'uploaded' || 'closed' => pal.gainGreen,
      'cancelled' || 'rejected' || 'expired' || 'blocked' => pal.lossRed,
      'on_hold' || 'review' || 'waived' => pal.warningAmber,
      'intake' => pal.textMuted,
      'assessment' => pal.neutralBlue,
      'mitigation' => pal.neutralBlue,
      'demolition' => pal.warningAmber,
      'reconstruction' => pal.accentViolet,
      'closeout' => pal.gainGreen,
      'archived' => pal.textMuted,
      _ => pal.textSecondary,
    };
  }

  static String _relative(dynamic v) {
    if (v is! String || v.isEmpty) return '';
    try {
      final dt = DateTime.parse(v);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 30) return '${diff.inDays}d ago';
      return '${(diff.inDays / 30).floor()}mo ago';
    } catch (_) {
      return v;
    }
  }
}

// ── Helper widgets ───────────────────────────────────────────────────────

class _EmptyRow extends StatelessWidget {
  final String title;
  final String message;
  const _EmptyRow({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    return Padding(
      padding: const EdgeInsets.all(36),
      child: Center(
        child: Column(
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: OTokens.textMd,
                fontWeight: FontWeight.w600,
                color: pal.textBright,
              ),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: OTokens.textSm,
                  color: pal.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  final String message;
  const _ErrorRow({required this.message});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Failed to load: $message',
        style: GoogleFonts.inter(
          fontSize: OTokens.textSm,
          color: pal.lossRed,
        ),
      ),
    );
  }
}
