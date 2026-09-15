import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class HeatmapElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const HeatmapElement({super.key, required this.element, required this.mode});

  @override
  State<HeatmapElement> createState() => _HeatmapElementState();
}

class _HeatmapElementState extends State<HeatmapElement> {
  late List<List<double>> _data;
  int? _hovRow;
  int? _hovCol;

  @override
  void initState() {
    super.initState();
    _generateData();
  }

  void _generateData() {
    final rawRows = widget.element.config['rowLabels'];
    final rawCols = widget.element.config['colLabels'];
    final rows = (rawRows is List) ? rawRows.length : 5;
    final cols = (rawCols is List) ? rawCols.length : 8;
    final rng = math.Random(42);
    _data = List.generate(rows, (_) =>
        List.generate(cols, (_) => rng.nextDouble()));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.element.config['title'] as String? ?? 'Heatmap';
    final rawRows = widget.element.config['rowLabels'];
    final rowLabels = (rawRows is List) ? rawRows.cast<String>() : <String>[];
    final rawCols = widget.element.config['colLabels'];
    final colLabels = (rawCols is List) ? rawCols.cast<String>() : <String>[];
    final colorKey = widget.element.config['color'] as String? ?? 'blue';

    final baseColor = switch (colorKey) {
      'green' => OPaletteScope.of(context).gainGreen,
      'amber' => OPaletteScope.of(context).warningAmber,
      'violet' => OPaletteScope.of(context).accentViolet,
      'cyan' => OPaletteScope.of(context).accentCyan,
      _ => OPaletteScope.of(context).primaryBlue,
    };

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

          // Column headers
          Row(
            children: [
              const SizedBox(width: 36),
              ...colLabels.map((c) => Expanded(child: Text(c,
                  style: GoogleFonts.inter(fontSize: 9, color: OPaletteScope.of(context).textMuted),
                  textAlign: TextAlign.center))),
            ],
          ),
          const SizedBox(height: OTokens.s2),

          // Grid
          ...List.generate(rowLabels.length, (r) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(rowLabels[r],
                      style: GoogleFonts.inter(fontSize: 9, color: OPaletteScope.of(context).textMuted)),
                ),
                ...List.generate(colLabels.length, (c) {
                  final intensity = _data[r][c];
                  final isHov = _hovRow == r && _hovCol == c;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: MouseRegion(
                        onEnter: (_) => setState(() { _hovRow = r; _hovCol = c; }),
                        onExit: (_) => setState(() { _hovRow = null; _hovCol = null; }),
                        child: Tooltip(
                          message: intensity.toStringAsFixed(2),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 100),
                            height: 20,
                            decoration: BoxDecoration(
                              color: baseColor.withValues(
                                  alpha: 0.08 + intensity * 0.7),
                              borderRadius: BorderRadius.circular(3),
                              border: isHov
                                  ? Border.all(color: baseColor, width: 1.5)
                                  : null,
                              boxShadow: isHov ? [
                                BoxShadow(color: baseColor.withValues(alpha: 0.3), blurRadius: 6),
                              ] : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          )),

          const SizedBox(height: OTokens.s3),
          // Legend
          Row(
            children: [
              Text('Low', style: GoogleFonts.inter(fontSize: 9, color: OPaletteScope.of(context).textMuted)),
              const SizedBox(width: OTokens.s2),
              ...List.generate(5, (i) => Expanded(
                child: Container(
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: baseColor.withValues(alpha: 0.08 + (i / 4) * 0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              )),
              const SizedBox(width: OTokens.s2),
              Text('High', style: GoogleFonts.inter(fontSize: 9, color: OPaletteScope.of(context).textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
