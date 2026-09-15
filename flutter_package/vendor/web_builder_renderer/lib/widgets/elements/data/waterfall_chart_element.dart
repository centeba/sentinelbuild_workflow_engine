import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class WaterfallChartElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const WaterfallChartElement({super.key, required this.element, required this.mode});

  @override
  State<WaterfallChartElement> createState() => _WaterfallChartElementState();
}

class _WaterfallChartElementState extends State<WaterfallChartElement> {
  int? _hovIndex;

  @override
  Widget build(BuildContext context) {
    final title = widget.element.config['title'] as String? ?? 'Waterfall';
    final rawItems = widget.element.config['items'];
    final items = (rawItems is List) ? rawItems.cast<Map>() : <Map>[];

    if (items.isEmpty) return const SizedBox.shrink();

    // Build running totals
    double running = 0;
    final bars = <_WaterfallBar>[];
    for (final item in items) {
      final value = (item['value'] as num?)?.toDouble() ?? 0.0;
      final type = item['type'] as String? ?? 'positive';
      final label = item['label'] as String? ?? '';
      if (type == 'subtotal' || type == 'total') {
        running = value;
        bars.add(_WaterfallBar(label: label, value: value, start: 0, end: value, type: type));
      } else {
        final start = running;
        running += value;
        bars.add(_WaterfallBar(label: label, value: value, start: start, end: running, type: type));
      }
    }

    final allValues = bars.expand((b) => [b.start, b.end]).toList();
    final maxVal = allValues.reduce((a, b) => a > b ? a : b);
    final minVal = allValues.reduce((a, b) => a < b ? a : b).clamp(double.negativeInfinity, 0.0);
    final range = (maxVal - minVal).abs();
    // ignore: unused_local_variable
    final zeroFraction = range > 0 ? (-minVal / range) : 0.0;

    return Container(
      padding: const EdgeInsets.all(OTokens.s5),
      decoration: BoxDecoration(
        color: OPaletteScope.of(context).bgGlass,
        borderRadius: BorderRadius.circular(OTokens.radiusLg),
        border: Border.all(color: OPaletteScope.of(context).bgGlassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.plusJakartaSans(
              fontSize: OTokens.textBase, fontWeight: FontWeight.w600,
              color: OPaletteScope.of(context).textBright)),
          const SizedBox(height: OTokens.s4),
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: bars.asMap().entries.map((entry) {
                final i = entry.key;
                final bar = entry.value;
                final isHov = _hovIndex == i;

                final barColor = switch (bar.type) {
                  'subtotal' => OPaletteScope.of(context).neutralBlue,
                  'total' => OPaletteScope.of(context).primaryBlue,
                  _ => bar.value >= 0 ? OPaletteScope.of(context).gainGreen : OPaletteScope.of(context).lossRed,
                };

                final topFrac = (maxVal - bar.end.clamp(minVal, maxVal)) / range;
                final heightFrac = (bar.end - bar.start).abs() / range;
                final spacerFrac = topFrac;

                return Expanded(
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _hovIndex = i),
                    onExit: (_) => setState(() => _hovIndex = null),
                    child: Tooltip(
                      message: '${bar.label}: ${bar.value >= 0 ? '+' : ''}${bar.value.toStringAsFixed(0)}',
                      child: Column(
                        children: [
                          SizedBox(height: spacerFrac * 200),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              height: heightFrac * 200,
                              decoration: BoxDecoration(
                                color: isHov
                                    ? barColor
                                    : barColor.withValues(alpha: 0.7),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3)),
                                boxShadow: isHov
                                    ? [BoxShadow(color: barColor.withValues(alpha: 0.4), blurRadius: 8)]
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: OTokens.s2),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // X-axis labels
          Row(
            children: bars.map((b) => Expanded(
              child: Text(
                b.label,
                style: GoogleFonts.inter(fontSize: 8, color: OPaletteScope.of(context).textMuted),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

class _WaterfallBar {
  final String label;
  final double value;
  final double start;
  final double end;
  final String type;

  const _WaterfallBar({
    required this.label,
    required this.value,
    required this.start,
    required this.end,
    required this.type,
  });
}
