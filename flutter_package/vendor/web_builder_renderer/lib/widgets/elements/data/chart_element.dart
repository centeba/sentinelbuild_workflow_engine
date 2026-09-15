import 'dart:ui';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class ChartElement extends ConsumerWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const ChartElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = OPaletteScope.of(context);
    final config = element.config;
    final chartType = config['chartType'] as String? ?? 'line';
    final height = (config['height'] as num?)?.toDouble() ?? 280.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(OTokens.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(OTokens.s5),
          height: height + OTokens.s10,
          decoration: BoxDecoration(
            color: pal.bgGlass,
            borderRadius: BorderRadius.circular(OTokens.radiusLg),
            border: Border.all(color: pal.bgGlassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    config['title'] as String? ?? 'Chart',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: OTokens.textBase,
                      fontWeight: FontWeight.w600,
                      color: pal.textBright,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: OTokens.s2, vertical: 2),
                    decoration: BoxDecoration(
                      color: pal.primaryBlue.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(OTokens.radiusFull),
                    ),
                    child: Text(
                      chartType,
                      style: TextStyle(
                        fontSize: OTokens.textXs,
                        color: pal.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: OTokens.s4),
              Expanded(
                child: switch (chartType) {
                  'pie' => _buildPieChart(pal),
                  'donut' => _buildDonutChart(pal),
                  'bar' => _buildBarChart(pal),
                  'scatter' => _buildScatterChart(pal),
                  'radar' => _buildRadarChart(pal),
                  _ => _buildLineChart(chartType == 'area', pal),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLineChart(bool isArea, OPaletteData pal) {
    final spots = _demoLineSpots();
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(
            color: pal.borderSubtle,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, _) => Text(
                v.round().toString(),
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: pal.textMuted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, _) => Text(
                'Q${v.round() + 1}',
                style: GoogleFonts.inter(
                    fontSize: 10, color: pal.textMuted),
              ),
            ),
          ),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: pal.primaryBlue,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3.5,
                color: pal.primaryBlue,
                strokeWidth: 1.5,
                strokeColor: pal.bgCanvas,
              ),
            ),
            belowBarData: isArea
                ? BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        pal.primaryBlue.withValues(alpha: 0.25),
                        pal.primaryBlue.withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  )
                : BarAreaData(show: false),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => pal.bgRaised,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      s.y.round().toString(),
                      GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: pal.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart(OPaletteData pal) {
    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: pal.borderSubtle, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, _) => Text(
                'Q${v.round() + 1}',
                style: GoogleFonts.inter(
                    fontSize: 10, color: pal.textMuted),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, _) => Text(
                v.round().toString(),
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: pal.textMuted),
              ),
            ),
          ),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barGroups: _demoBarGroups(pal),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => pal.bgRaised,
          ),
        ),
      ),
    );
  }

  Widget _buildPieChart(OPaletteData pal) {
    return PieChart(
      PieChartData(
        sections: _demoPieSections(false, pal),
        sectionsSpace: 2,
        centerSpaceRadius: 0,
      ),
    );
  }

  Widget _buildDonutChart(OPaletteData pal) {
    return PieChart(
      PieChartData(
        sections: _demoPieSections(true, pal),
        sectionsSpace: 3,
        centerSpaceRadius: 40,
      ),
    );
  }

  Widget _buildScatterChart(OPaletteData pal) {
    final spots = [
      ScatterSpot(1.2, 35, dotPainter: FlDotCirclePainter(radius: 6, color: pal.primaryBlue, strokeWidth: 0)),
      ScatterSpot(2.5, 62, dotPainter: FlDotCirclePainter(radius: 8, color: pal.accentCyan, strokeWidth: 0)),
      ScatterSpot(3.1, 48, dotPainter: FlDotCirclePainter(radius: 5, color: pal.gainGreen, strokeWidth: 0)),
      ScatterSpot(4.0, 78, dotPainter: FlDotCirclePainter(radius: 10, color: pal.primaryBlue.withValues(alpha: 0.7), strokeWidth: 0)),
      ScatterSpot(2.0, 55, dotPainter: FlDotCirclePainter(radius: 7, color: pal.accentViolet, strokeWidth: 0)),
      ScatterSpot(5.2, 90, dotPainter: FlDotCirclePainter(radius: 9, color: pal.warningAmber, strokeWidth: 0)),
      ScatterSpot(1.8, 42, dotPainter: FlDotCirclePainter(radius: 6, color: pal.accentCyan, strokeWidth: 0)),
      ScatterSpot(3.7, 68, dotPainter: FlDotCirclePainter(radius: 7, color: pal.gainGreen, strokeWidth: 0)),
    ];
    return ScatterChart(
      ScatterChartData(
        scatterSpots: spots,
        minX: 0, maxX: 6, minY: 0, maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (_) => FlLine(color: pal.borderSubtle, strokeWidth: 1),
          getDrawingVerticalLine: (_) => FlLine(color: pal.borderSubtle, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24,
            getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0), style: GoogleFonts.jetBrainsMono(fontSize: 10, color: pal.textMuted)))),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36,
            getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0), style: GoogleFonts.jetBrainsMono(fontSize: 10, color: pal.textMuted)))),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        scatterTouchData: ScatterTouchData(
          touchTooltipData: ScatterTouchTooltipData(
            getTooltipColor: (_) => pal.bgRaised,
            getTooltipItems: (spot) => ScatterTooltipItem(
              '(${spot.x.toStringAsFixed(1)}, ${spot.y.toStringAsFixed(0)})',
              textStyle: GoogleFonts.jetBrainsMono(fontSize: 11, color: pal.textPrimary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRadarChart(OPaletteData pal) {
    final features = ['Return', 'Risk', 'Liquidity', 'Yield', 'Growth', 'Stability'];
    return RadarChart(
      RadarChartData(
        radarShape: RadarShape.polygon,
        tickCount: 4,
        ticksTextStyle: const TextStyle(fontSize: 0),
        radarBorderData: BorderSide(color: pal.borderSubtle),
        gridBorderData: BorderSide(color: pal.borderSubtle, width: 0.5),
        titleTextStyle: GoogleFonts.inter(fontSize: 10, color: pal.textSecondary),
        getTitle: (index, angle) => RadarChartTitle(text: features[index % features.length], angle: angle),
        dataSets: [
          RadarDataSet(
            dataEntries: [72, 45, 88, 60, 78, 55].map((v) => RadarEntry(value: v.toDouble())).toList(),
            fillColor: pal.primaryBlue.withValues(alpha: 0.2),
            borderColor: pal.primaryBlue,
            borderWidth: 2,
            entryRadius: 3,
          ),
          RadarDataSet(
            dataEntries: [55, 70, 60, 80, 50, 75].map((v) => RadarEntry(value: v.toDouble())).toList(),
            fillColor: pal.accentCyan.withValues(alpha: 0.15),
            borderColor: pal.accentCyan,
            borderWidth: 2,
            entryRadius: 3,
          ),
        ],
      ),
    );
  }

  List<FlSpot> _demoLineSpots() => [
        const FlSpot(0, 42),
        const FlSpot(1, 68),
        const FlSpot(2, 55),
        const FlSpot(3, 89),
        const FlSpot(4, 76),
        const FlSpot(5, 95),
      ];

  List<BarChartGroupData> _demoBarGroups(OPaletteData pal) {
    final values = [42.0, 68.0, 55.0, 89.0, 76.0, 95.0];
    return values.asMap().entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: e.value,
            color: pal.primaryBlue,
            width: 16,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: 100,
              color: pal.bgRaised,
            ),
          ),
        ],
      );
    }).toList();
  }

  List<PieChartSectionData> _demoPieSections(bool donut, OPaletteData pal) {
    final colors = [
      pal.primaryBlue,
      pal.accentCyan,
      pal.accentViolet,
      pal.gainGreen,
      pal.warningAmber,
    ];
    final values = [35.0, 25.0, 20.0, 12.0, 8.0];
    return values.asMap().entries.map((e) {
      return PieChartSectionData(
        value: e.value,
        color: colors[e.key % colors.length],
        radius: donut ? 50 : 80,
        title: '${e.value.round()}%',
        titleStyle: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        showTitle: e.value > 10,
      );
    }).toList();
  }
}
