import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class GanttChartElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const GanttChartElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final title = element.config['title'] as String? ?? 'Timeline';
    final rawPeriods = element.config['periods'];
    final periods = (rawPeriods is List) ? rawPeriods.cast<String>() : <String>[];
    final rawItems = element.config['items'];
    final items = (rawItems is List) ? rawItems.cast<Map>() : <Map>[];

    return Container(
      padding: const EdgeInsets.all(OTokens.s5),
      decoration: BoxDecoration(
        color: pal.bgGlass,
        borderRadius: BorderRadius.circular(OTokens.radiusLg),
        border: Border.all(color: pal.bgGlassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: OTokens.textBase,
              fontWeight: FontWeight.w600,
              color: pal.textBright,
            ),
          ),
          const SizedBox(height: OTokens.s4),

          // Period headers
          Row(
            children: [
              const SizedBox(width: 110),
              ...periods.map((p) => Expanded(
                    child: Text(
                      p,
                      style: GoogleFonts.inter(
                          fontSize: OTokens.textXs,
                          color: pal.textMuted,
                          fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  )),
            ],
          ),
          const SizedBox(height: OTokens.s2),
          Divider(color: pal.borderSubtle, height: 1),

          // Task rows
          ...items.map((item) {
            final label = item['label'] as String? ?? '';
            final start = (item['start'] as num?)?.toInt() ?? 0;
            final end = (item['end'] as num?)?.toInt() ?? 1;
            final colorKey = item['color'] as String? ?? 'blue';
            final barColor = _colorFor(colorKey, pal);
            final total = periods.length;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: OTokens.s2),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                          fontSize: OTokens.textXs,
                          color: pal.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      final cellW = constraints.maxWidth / total;
                      final barLeft = start * cellW;
                      final barWidth = (end - start + 1) * cellW - 4;
                      return SizedBox(
                        height: 24,
                        child: Stack(
                          children: [
                            // Grid lines
                            ...List.generate(total, (i) => Positioned(
                              left: i * cellW,
                              top: 0,
                              bottom: 0,
                              width: 1,
                              child: Container(color: pal.borderSubtle.withValues(alpha: 0.4)),
                            )),
                            // Bar
                            Positioned(
                              left: barLeft + 2,
                              top: 4,
                              width: barWidth,
                              height: 16,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: barColor.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(OTokens.radiusFull),
                                  border: Border.all(color: barColor.withValues(alpha: 0.6)),
                                ),
                                child: Center(
                                  child: Text(
                                    label,
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      color: barColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.clip,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Color _colorFor(String key, OPaletteData pal) => switch (key) {
        'green' => pal.gainGreen,
        'amber' => pal.warningAmber,
        'violet' => pal.accentViolet,
        'cyan' => pal.accentCyan,
        'red' => pal.lossRed,
        _ => pal.primaryBlue,
      };
}
