import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../element_renderer.dart';

class BreadcrumbsElement extends ConsumerWidget {
  final PageElement element;
  final RenderMode mode;

  const BreadcrumbsElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Items support two shapes:
    //  1. Strings (legacy): ["Home", "Projects", "Detail"]
    //  2. Maps (preferred): [{label: "Projects", to: "/projects"}, {label: "Detail"}]
    // Map items carry an optional `to` route; when present (and not the last
    // crumb), the crumb renders as a clickable link.
    final rawItems = element.config['items'];
    final crumbs = <({String label, String? to})>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is String) {
          crumbs.add((label: entry, to: null));
        } else if (entry is Map) {
          final label = (entry['label'] ?? entry['text'] ?? '').toString();
          final to = entry['to']?.toString();
          crumbs.add((
            label: label,
            to: (to != null && to.trim().isNotEmpty) ? to.trim() : null,
          ));
        }
      }
    }
    // Drop blank crumbs (the published page ends with a placeholder {label:""}).
    crumbs.removeWhere((c) => c.label.trim().isEmpty);
    if (crumbs.isEmpty) return const SizedBox.shrink();

    final pal = OPaletteScope.of(context);

    void navigate(String to) {
      final cbReg = ref.read(pageRendererCallbacksProvider);
      final raw = cbReg.values.isNotEmpty ? cbReg.values.first : null;
      if (raw != null) {
        try {
          // Avoid importing PageRendererCallbacks (would risk an import cycle
          // with page_renderer_widget) — the host callback exposes onNavigate.
          (raw as dynamic).onNavigate?.call(to, const <String, dynamic>{});
        } catch (_) {/* host without a navigate callback — no-op */}
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: crumbs.asMap().entries.expand((entry) {
        final i = entry.key;
        final c = entry.value;
        final isLast = i == crumbs.length - 1;
        // A crumb is a link whenever it declares a `to` route — not based on
        // position. (The current page's crumb carries no `to`, so it stays
        // plain even when it's the last one; and a parent like "Projects"
        // links even if trailing blanks were dropped and it ended up last.)
        final linked = c.to != null && mode != RenderMode.builder;
        final text = Text(
          c.label,
          style: GoogleFonts.inter(
            fontSize: OTokens.textSm,
            color: linked
                ? pal.primaryBlue
                : (isLast ? pal.textBright : pal.textMuted),
            fontWeight: isLast ? FontWeight.w500 : FontWeight.w400,
          ),
        );
        return [
          if (linked)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => navigate(c.to!),
                child: text,
              ),
            )
          else
            text,
          if (!isLast)
            Icon(LucideIcons.chevronRight, size: 12, color: pal.textMuted),
        ];
      }).toList(),
    );
  }
}
