import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class CandlestickElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const CandlestickElement({super.key, required this.element, required this.mode});

  @override
  State<CandlestickElement> createState() => _CandlestickElementState();
}

class _CandlestickElementState extends State<CandlestickElement> {
  late List<_Candle> _candles;
  int? _hovIndex;

  @override
  void initState() {
    super.initState();
    _candles = _generateDemo();
  }

  List<_Candle> _generateDemo() {
    final rng = math.Random(7);
    double price = 150.0;
    return List.generate(20, (i) {
      final open = price + (rng.nextDouble() - 0.5) * 4;
      final close = open + (rng.nextDouble() - 0.48) * 6;
      final high = math.max(open, close) + rng.nextDouble() * 3;
      final low = math.min(open, close) - rng.nextDouble() * 3;
      price = close;
      return _Candle(open: open, close: close, high: high, low: low);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final title = widget.element.config['title'] as String? ?? 'OHLC Chart';
    final symbol = widget.element.config['symbol'] as String? ?? '';
    final height = (widget.element.config['height'] as num?)?.toDouble() ?? 260.0;

    final last = _candles.last;
    final change = last.close - last.open;
    final changeColor = change >= 0 ? pal.gainGreen : pal.lossRed;

    return ClipRRect(
      borderRadius: BorderRadius.circular(OTokens.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(OTokens.s5),
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
                  Text(title, style: GoogleFonts.plusJakartaSans(
                      fontSize: OTokens.textBase, fontWeight: FontWeight.w600,
                      color: pal.textBright)),
                  const SizedBox(width: OTokens.s2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: OTokens.s2, vertical: 2),
                    decoration: BoxDecoration(
                      color: pal.bgSurface,
                      borderRadius: BorderRadius.circular(OTokens.radiusFull),
                    ),
                    child: Text(symbol, style: GoogleFonts.jetBrainsMono(
                        fontSize: OTokens.textXs, color: pal.textSecondary,
                        fontWeight: FontWeight.w600)),
                  ),
                  const Spacer(),
                  Text(
                    last.close.toStringAsFixed(2),
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: OTokens.textLg, fontWeight: FontWeight.w700,
                        color: pal.textBright),
                  ),
                  const SizedBox(width: OTokens.s2),
                  Text(
                    '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: OTokens.textSm, fontWeight: FontWeight.w600,
                        color: changeColor),
                  ),
                ],
              ),
              const SizedBox(height: OTokens.s4),
              SizedBox(
                height: height,
                child: CustomPaint(
                  painter: _CandlestickPainter(
                      candles: _candles, hovered: _hovIndex, pal: pal),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Candle {
  final double open, close, high, low;
  const _Candle({required this.open, required this.close, required this.high, required this.low});
}

class _CandlestickPainter extends CustomPainter {
  final List<_Candle> candles;
  final int? hovered;

  /// A painter has no BuildContext, so the scoped palette is passed in.
  final OPaletteData pal;

  const _CandlestickPainter(
      {required this.candles, required this.pal, this.hovered});

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final allPrices = candles.expand((c) => [c.high, c.low]).toList();
    final minP = allPrices.reduce(math.min) - 2;
    final maxP = allPrices.reduce(math.max) + 2;
    final range = maxP - minP;

    double toY(double price) => size.height * (1 - (price - minP) / range);

    final n = candles.length;
    final candleW = size.width / n;
    const bodyPad = 3.0;

    // Grid lines
    final gridPaint = Paint()
      ..color = pal.borderSubtle
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (int i = 0; i < n; i++) {
      final c = candles[i];
      final centerX = candleW * i + candleW / 2;
      final isGreen = c.close >= c.open;
      final color = isGreen ? pal.gainGreen : pal.lossRed;
      final isHov = hovered == i;

      final bodyPaint = Paint()
        ..color = isHov ? color : color.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;
      final wickPaint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      // Wick
      canvas.drawLine(
        Offset(centerX, toY(c.high)),
        Offset(centerX, toY(c.low)),
        wickPaint,
      );

      // Body
      final bodyTop = toY(math.max(c.open, c.close));
      final bodyBottom = toY(math.min(c.open, c.close));
      final bodyHeight = (bodyBottom - bodyTop).clamp(2.0, double.infinity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              centerX - candleW / 2 + bodyPad, bodyTop, candleW - bodyPad * 2, bodyHeight),
          const Radius.circular(2),
        ),
        bodyPaint,
      );

      if (isHov) {
        final glowPaint = Paint()
          ..color = color.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
                centerX - candleW / 2 + bodyPad, bodyTop, candleW - bodyPad * 2, bodyHeight),
            const Radius.circular(2),
          ),
          glowPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CandlestickPainter old) =>
      old.hovered != hovered || old.candles != candles;
}
