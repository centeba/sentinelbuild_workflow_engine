import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../../../providers/section_counts_provider.dart';
import '../element_renderer.dart';
import 'data_fetch.dart';

/// List of items bound to an API source. Honors:
///   - viewMode: 'card' | 'row'
///   - titleField / subtitleField / trailingField / badgeField / tagField
///   - groupBy (renders a section header per distinct value)
///   - emptyStateTitle / emptyStateMessage
class ListElement extends ConsumerWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const ListElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = OPaletteScope.of(context);
    final binding = element.dataBinding;
    final ctxMap = ref.watch(bindingContextProvider);
    final ctx = ctxMap[pageId];
    final cfg = element.config;
    final viewMode = (cfg['viewMode'] as String?) ?? 'card';
    final titleField = (cfg['titleField'] as String?) ?? 'title';
    final subtitleField = cfg['subtitleField'] as String?;
    final trailingField = cfg['trailingField'] as String?;
    final badgeField = cfg['badgeField'] as String?;
    final tagField = cfg['tagField'] as String?;
    final groupBy = cfg['groupBy'] as String?;
    final emptyTitle = (cfg['emptyStateTitle'] as String?) ?? 'No items';
    final emptyMessage = (cfg['emptyStateMessage'] as String?) ?? '';

    if (binding == null || mode == RenderMode.builder) {
      return _renderList(
        const [
          {'title': 'Item One', 'subtitle': 'Updated just now'},
          {'title': 'Item Two', 'subtitle': 'Updated yesterday'},
          {'title': 'Item Three', 'subtitle': 'Updated last week'},
        ],
        pal,
        viewMode: viewMode,
        titleField: titleField,
        subtitleField: subtitleField,
        trailingField: trailingField,
        badgeField: badgeField,
        tagField: tagField,
        groupBy: null,
      );
    }
    if (ctx == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchBindingRows(ctx, binding),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Failed to load: ${snap.error}',
              style: GoogleFonts.inter(
                  fontSize: OTokens.textSm, color: pal.lossRed),
            ),
          );
        }
        final items = snap.data ?? const [];
        // Report the count for the collapsible-section header badge (post-frame
        // so we don't mutate a provider during build).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(sectionCountsProvider.notifier)
              .report(pageId, element.sectionId, items.length);
        });
        if (items.isEmpty) return _emptyState(emptyTitle, emptyMessage, pal);
        return _renderList(
          items,
          pal,
          viewMode: viewMode,
          titleField: titleField,
          subtitleField: subtitleField,
          trailingField: trailingField,
          badgeField: badgeField,
          tagField: tagField,
          groupBy: groupBy,
        );
      },
    );
  }

  Widget _renderList(
    List<Map<String, dynamic>> items,
    OPaletteData pal, {
    required String viewMode,
    required String titleField,
    String? subtitleField,
    String? trailingField,
    String? badgeField,
    String? tagField,
    String? groupBy,
  }) {
    if (groupBy != null) {
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final it in items) {
        final k = '${it[groupBy] ?? "Other"}';
        (grouped[k] ??= []).add(it);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: OTokens.s2),
              child: Text(
                entry.key,
                style: GoogleFonts.inter(
                  fontSize: OTokens.textXs,
                  fontWeight: FontWeight.w600,
                  color: pal.textMuted,
                  letterSpacing: 0.08,
                ),
              ),
            ),
            for (final it in entry.value)
              _ItemCard(
                item: it,
                viewMode: viewMode,
                titleField: titleField,
                subtitleField: subtitleField,
                trailingField: trailingField,
                badgeField: badgeField,
                tagField: tagField,
              ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items
          .map((it) => _ItemCard(
                item: it,
                viewMode: viewMode,
                titleField: titleField,
                subtitleField: subtitleField,
                trailingField: trailingField,
                badgeField: badgeField,
                tagField: tagField,
              ))
          .toList(),
    );
  }

  Widget _emptyState(String title, String message, OPaletteData pal) {
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: pal.bgGlass,
        borderRadius: BorderRadius.circular(OTokens.radiusLg),
        border: Border.all(color: pal.borderSubtle),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: GoogleFonts.inter(
                  fontSize: OTokens.textMd,
                  fontWeight: FontWeight.w600,
                  color: pal.textBright,
                )),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: OTokens.textSm, color: pal.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final String viewMode;
  final String titleField;
  final String? subtitleField;
  final String? trailingField;
  final String? badgeField;
  final String? tagField;

  const _ItemCard({
    required this.item,
    required this.viewMode,
    required this.titleField,
    required this.subtitleField,
    required this.trailingField,
    required this.badgeField,
    required this.tagField,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final it = widget.item;
    final title = _str(it[widget.titleField]);
    final subtitle =
        widget.subtitleField == null ? '' : _str(it[widget.subtitleField]);
    final trailing =
        widget.trailingField == null ? '' : _str(it[widget.trailingField]);
    final badge = _badgeLabel(widget.badgeField, it);
    final tags =
        widget.tagField == null ? const [] : (it[widget.tagField] as List? ?? const []);
    final isCard = widget.viewMode == 'card';

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover && isCard ? 1.005 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          margin: const EdgeInsets.only(bottom: OTokens.s2),
          padding: const EdgeInsets.all(OTokens.s3),
          decoration: BoxDecoration(
            color: isCard
                ? (_hover ? pal.bgRaised : pal.bgGlass)
                : Colors.transparent,
            borderRadius: isCard ? BorderRadius.circular(OTokens.radiusMd) : null,
            border: isCard
                ? Border.all(
                    color: _hover ? pal.borderStrong : pal.borderSubtle)
                : Border(
                    bottom: BorderSide(color: pal.borderSubtle)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.inter(
                          fontSize: OTokens.textBase,
                          fontWeight: FontWeight.w500,
                          color: pal.textBright,
                        )),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: GoogleFonts.inter(
                              fontSize: OTokens.textSm,
                              color: pal.textMuted)),
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: tags
                            .map((t) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: pal.bgRaised,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('$t',
                                      style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: pal.textMuted,
                                          fontWeight: FontWeight.w500)),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 12),
                _badge('$badge', pal),
              ],
              if (trailing.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(_relative(trailing),
                    style: GoogleFonts.inter(
                        fontSize: 12, color: pal.textMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Resolve the badge text for an item, or null to render no badge.
  /// Boolean fields (e.g. `pinned`) are presence flags: shown only when true,
  /// labeled with the humanized field name (so `pinned: false` renders nothing
  /// instead of a stray "false" chip). Other values render their string.
  static String? _badgeLabel(String? field, Map<String, dynamic> item) {
    if (field == null) return null;
    final raw = item[field];
    if (raw == null) return null;
    if (raw is bool) {
      if (!raw) return null;
      final words = field
          .replaceAll('_', ' ')
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => '${w[0].toUpperCase()}${w.substring(1)}');
      return words.join(' ');
    }
    final s = '$raw'.trim();
    return s.isEmpty ? null : s;
  }

  Widget _badge(String value, OPaletteData pal) {
    final c = _badgeColor(value, pal);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(value,
          style: GoogleFonts.inter(
              fontSize: OTokens.textXs, fontWeight: FontWeight.w600, color: c)),
    );
  }

  static String _str(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return '$v';
  }

  static String _relative(String v) {
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

  static Color _badgeColor(String value, OPaletteData pal) {
    return switch (value.toLowerCase()) {
      'active' || 'open' || 'in_progress' => pal.neutralBlue,
      'pending' => pal.textMuted,
      'complete' || 'signed' || 'uploaded' || 'closed' => pal.gainGreen,
      'cancelled' || 'rejected' || 'expired' || 'blocked' => pal.lossRed,
      'on_hold' || 'review' || 'waived' || 'high' => pal.warningAmber,
      'urgent' => pal.lossRed,
      'low' => pal.textMuted,
      'medium' => pal.neutralBlue,
      _ => pal.textSecondary,
    };
  }
}
