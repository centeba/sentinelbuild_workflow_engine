import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class ProgressBarElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const ProgressBarElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final label = element.config['label'] as String? ?? 'Progress';
    // `value` may arrive as a num (literal config) or a String (data-bound
    // from an API / template like "0"). Parse defensively so a string never
    // throws a cast TypeError (which would surface as a red error box and
    // clip everything below it on the page).
    final rawValue = element.config['value'];
    final parsedValue = switch (rawValue) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s.trim()) ?? 0.0,
      _ => 0.0,
    };
    final value = parsedValue.clamp(0.0, 100.0);
    final showPercent = element.config['showPercent'] as bool? ?? true;
    final colorKey = element.config['color'] as String? ?? 'blue';
    final progress = value / 100;

    final barColor = switch (colorKey) {
      'green' => OPaletteScope.of(context).gainGreen,
      'red' => OPaletteScope.of(context).lossRed,
      'amber' => OPaletteScope.of(context).warningAmber,
      'violet' => OPaletteScope.of(context).accentViolet,
      'cyan' => OPaletteScope.of(context).accentCyan,
      _ => OPaletteScope.of(context).primaryBlue,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: OTokens.textSm,
                  fontWeight: FontWeight.w500,
                  color: OPaletteScope.of(context).textPrimary,
                ),
              ),
            ),
            if (showPercent)
              Text(
                '${value.toStringAsFixed(0)}%',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: OTokens.textSm,
                  fontWeight: FontWeight.w600,
                  color: barColor,
                ),
              ),
          ],
        ),
        const SizedBox(height: OTokens.s2),
        ClipRRect(
          borderRadius: BorderRadius.circular(OTokens.radiusFull),
          child: Container(
            height: 6,
            color: OPaletteScope.of(context).bgSurface,
            child: FractionallySizedBox(
              widthFactor: progress,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [barColor.withValues(alpha: 0.8), barColor],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: barColor.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
