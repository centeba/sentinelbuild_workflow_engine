import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class SparklineElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const SparklineElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final label = element.config['label'] as String? ?? '';
    final colorKey = element.config['color'] as String? ?? 'blue';
    final height = (element.config['height'] as num?)?.toDouble() ?? 56.0;
    final showDelta = element.config['showDelta'] as bool? ?? true;

    final lineColor = switch (colorKey) {
      'green' => OPaletteScope.of(context).gainGreen,
      'red' => OPaletteScope.of(context).lossRed,
      'amber' => OPaletteScope.of(context).warningAmber,
      'violet' => OPaletteScope.of(context).accentViolet,
      'cyan' => OPaletteScope.of(context).accentCyan,
      _ => OPaletteScope.of(context).primaryBlue,
    };

    const demoData = [42.0, 38.0, 52.0, 48.0, 61.0, 57.0, 70.0, 65.0, 78.0, 82.0];
    final last = demoData.last;
    final first = demoData.first;
    final delta = ((last - first) / first * 100);
    final deltaPositive = delta >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: OTokens.s4, vertical: OTokens.s3),
      decoration: BoxDecoration(
        color: OPaletteScope.of(context).bgGlass,
        borderRadius: BorderRadius.circular(OTokens.radiusMd),
        border: Border.all(color: OPaletteScope.of(context).bgGlassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.isNotEmpty)
                  Text(label,
                      style: GoogleFonts.inter(
                          fontSize: OTokens.textXs,
                          color: OPaletteScope.of(context).textSecondary)),
                if (showDelta) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${deltaPositive ? '+' : ''}${delta.toStringAsFixed(1)}%',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: OTokens.textSm,
                      fontWeight: FontWeight.w700,
                      color: deltaPositive ? OPaletteScope.of(context).gainGreen : OPaletteScope.of(context).lossRed,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 100,
            height: height,
            child: CustomPaint(
              painter: _SparklinePainter(data: demoData, color: lineColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  const _SparklinePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final minV = data.reduce((a, b) => a < b ? a : b);
    final maxV = data.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).clamp(1.0, double.infinity);
    final n = data.length;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < n; i++) {
      final x = size.width * i / (n - 1);
      final y = size.height * (1 - (data[i] - minV) / range);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Last point dot
    final lastX = size.width.toDouble();
    final lastY = size.height * (1 - (data.last - minV) / range);
    canvas.drawCircle(Offset(lastX, lastY), 3,
        Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.data != data || old.color != color;
}
