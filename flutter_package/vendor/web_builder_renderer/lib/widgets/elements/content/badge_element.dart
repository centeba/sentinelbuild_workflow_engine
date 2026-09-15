import 'package:flutter/material.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';

class BadgeElement extends StatelessWidget {
  final PageElement element;

  const BadgeElement({super.key, required this.element});

  /// "in_progress" / "intake" → "In Progress" / "Intake" for display.
  String _humanize(String raw) => raw
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final raw = element.config['text'] as String? ?? 'Status';
    final text = _humanize(raw);
    final variant = element.config['variant'] as String? ?? 'success';

    final (bg, fg) = switch (variant) {
      'success' => (
          OPaletteScope.of(context).gainGreen.withValues(alpha: 0.15),
          OPaletteScope.of(context).gainGreen
        ),
      'warning' => (
          OPaletteScope.of(context).warningAmber.withValues(alpha: 0.15),
          OPaletteScope.of(context).warningAmber
        ),
      'error' => (
          OPaletteScope.of(context).lossRed.withValues(alpha: 0.15),
          OPaletteScope.of(context).lossRed
        ),
      'info' => (
          OPaletteScope.of(context).neutralBlue.withValues(alpha: 0.15),
          OPaletteScope.of(context).neutralBlue
        ),
      _ => (
          OPaletteScope.of(context).bgRaised,
          OPaletteScope.of(context).textSecondary
        ),
    };

    // Align + content-size so the chip hugs its label rather than stretching to
    // fill its grid cell (the page grid wraps each element in a fixed-width
    // SizedBox, which otherwise made these into wide pills).
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: OTokens.s3, vertical: OTokens.s1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(OTokens.radiusFull),
          border: Border.all(color: fg.withValues(alpha: 0.3)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: OTokens.textXs,
            fontWeight: FontWeight.w600,
            color: fg,
            letterSpacing: 0.04,
          ),
        ),
      ),
    );
  }
}
