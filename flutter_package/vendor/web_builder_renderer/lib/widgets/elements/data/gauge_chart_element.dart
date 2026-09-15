import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../element_renderer.dart';
import 'data_fetch.dart';

/// Coerce a config/binding value to a double. Accepts num or numeric String
/// (page JSON often authors `"value": "0"`); anything else → null.
double? _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

class GaugeChartElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const GaugeChartElement({
    super.key,
    required this.element,
    required this.mode,
    this.pageId = '',
  });

  @override
  ConsumerState<GaugeChartElement> createState() => _GaugeChartElementState();
}

class _GaugeChartElementState extends ConsumerState<GaugeChartElement> {
  void Function()? _cancelRefresh;
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    final binding = widget.element.dataBinding;
    if (binding == null || widget.mode == RenderMode.builder) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = ref.read(bindingContextProvider)[widget.pageId];
      if (ctx == null) return;
      _cancelRefresh = bindRefreshOn(ctx, binding, () async {
        if (mounted) setState(() => _refreshTick++);
      });
    });
  }

  @override
  void dispose() {
    _cancelRefresh?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final binding = widget.element.dataBinding;
    final ctxMap = ref.watch(bindingContextProvider);
    final ctx = ctxMap[widget.pageId];

    final staticValue = _asDouble(widget.element.config['value']) ?? 0.0;

    if (binding == null || widget.mode == RenderMode.builder || ctx == null) {
      return _shell(staticValue);
    }
    return FutureBuilder<dynamic>(
      key: ValueKey('gauge-${widget.element.id}-$_refreshTick'),
      future: fetchBindingValue(ctx, binding),
      builder: (_, snap) {
        final v = _asDouble(snap.data) ?? staticValue;
        return _shell(v);
      },
    );
  }

  Widget _shell(double value) {
    final label = widget.element.config['label'] as String? ?? 'Score';
    final min = _asDouble(widget.element.config['min']) ?? 0.0;
    final max = _asDouble(widget.element.config['max']) ?? 100.0;
    final suffix = widget.element.config['suffix'] as String? ?? '';
    final colorKey = widget.element.config['color'] as String? ?? 'blue';

    final gaugeColor = switch (colorKey) {
      'green' => OPaletteScope.of(context).gainGreen,
      'red' => OPaletteScope.of(context).lossRed,
      'amber' => OPaletteScope.of(context).warningAmber,
      'violet' => OPaletteScope.of(context).accentViolet,
      'cyan' => OPaletteScope.of(context).accentCyan,
      _ => OPaletteScope.of(context).primaryBlue,
    };

    final progress = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(OTokens.s5),
      decoration: BoxDecoration(
        color: OPaletteScope.of(context).bgGlass,
        borderRadius: BorderRadius.circular(OTokens.radiusLg),
        border: Border.all(color: OPaletteScope.of(context).bgGlassBorder),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 108,
            child: CustomPaint(
              painter: _GaugePainter(
                progress: progress,
                color: gaugeColor,
                track: OPaletteScope.of(context).borderSubtle,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}$suffix',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: OTokens.text2xl,
                        fontWeight: FontWeight.w700,
                        color: gaugeColor,
                      ),
                    ),
                    const SizedBox(height: OTokens.s1),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: OTokens.s2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: OTokens.textSm,
              fontWeight: FontWeight.w500,
              color: OPaletteScope.of(context).textSecondary,
              letterSpacing: 0.04,
            ),
          ),
          const SizedBox(height: OTokens.s3),
          // Min/max labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$min$suffix',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: OTokens.textXs, color: OPaletteScope.of(context).textMuted)),
              Text('$max$suffix',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: OTokens.textXs, color: OPaletteScope.of(context).textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  const _GaugePainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.92);
    // Cap by height so the semicircle fits the (now compact) box instead of
    // overflowing/clipping.
    final radius = math.min(size.width * 0.42, size.height * 0.80);
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    // Track — a light grey so it's visible on the white card (was white,
    // making the gauge read as a big empty box).
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Fill gradient
    final fillPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: math.pi,
        endAngle: math.pi * 2,
        colors: [color.withValues(alpha: 0.5), color],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * progress,
        false,
        fillPaint,
      );
    }

    // Glow at tip
    if (progress > 0.02) {
      final tipAngle = startAngle + sweepAngle * progress;
      final tipX = center.dx + radius * math.cos(tipAngle);
      final tipY = center.dy + radius * math.sin(tipAngle);
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(tipX, tipY), 8, glowPaint);
      canvas.drawCircle(Offset(tipX, tipY), 5,
          Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress || old.color != color;
}
