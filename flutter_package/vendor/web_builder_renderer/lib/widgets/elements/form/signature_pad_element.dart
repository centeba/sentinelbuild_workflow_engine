import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

class SignaturePadElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const SignaturePadElement(
      {super.key, required this.element, required this.mode});

  @override
  State<SignaturePadElement> createState() => _SignaturePadElementState();
}

class _SignaturePadElementState extends State<SignaturePadElement> {
  /// Each stroke is a list of Offsets drawn by a single pointer-down → move → up
  final List<List<Offset>> _strokes = [];
  List<Offset>? _currentStroke;
  String? _svgExport;

  /// Key used to measure the canvas render size for SVG export.
  final _canvasKey = GlobalKey();

  bool get _isEmpty => _strokes.isEmpty;

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final label = widget.element.config['label'] as String? ?? 'Signature';
    final strokeWidth =
        (widget.element.config['strokeWidth'] as num?)?.toDouble() ?? 2.0;
    final strokeColorHex =
        widget.element.config['strokeColor'] as String? ?? '#1e293b';
    final strokeColor = _hexToColor(strokeColorHex);

    if (widget.mode == RenderMode.builder) {
      // Builder: static dashed placeholder
      return FormFieldShell(
        label: label,
        child: _BuilderPlaceholder(height: 120),
      );
    }

    // Preview / published: fully interactive
    return FormFieldShell(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(OTokens.radiusSm),
              border: Border.all(
                color: _isEmpty
                    ? pal.borderSubtle
                    : pal.primaryBlue.withValues(alpha: 0.4),
                width: _isEmpty ? 1 : 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(OTokens.radiusSm - 1),
              child: Listener(
                onPointerDown: (e) {
                  setState(() {
                    _currentStroke = [e.localPosition];
                    _svgExport = null;
                  });
                },
                onPointerMove: (e) {
                  if (_currentStroke != null) {
                    setState(() {
                      _currentStroke!.add(e.localPosition);
                    });
                  }
                },
                onPointerUp: (_) {
                  if (_currentStroke != null && _currentStroke!.isNotEmpty) {
                    setState(() {
                      _strokes.add(List.from(_currentStroke!));
                      _currentStroke = null;
                    });
                    _reportSvg();
                  }
                },
                onPointerCancel: (_) {
                  setState(() => _currentStroke = null);
                },
                child: CustomPaint(
                  key: _canvasKey,
                  painter: _SignaturePainter(
                    strokes: _strokes,
                    currentStroke: _currentStroke,
                    strokeColor: strokeColor,
                    strokeWidth: strokeWidth,
                  ),
                  child: _isEmpty && _currentStroke == null
                      ? Center(
                          child: Text(
                            'Sign here',
                            style: GoogleFonts.inter(
                              fontSize: OTokens.textSm,
                              color: pal.textMuted,
                            ),
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
            ),
          ),
          const SizedBox(height: OTokens.s2),
          Row(
            children: [
              if (!_isEmpty)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _strokes.clear();
                      _currentStroke = null;
                      _svgExport = null;
                    });
                    FormScope.maybeOf(context)?.report(widget.element.id, null);
                  },
                  icon: Icon(LucideIcons.trash2,
                      size: 13, color: pal.lossRed),
                  label: Text(
                    'Clear',
                    style: GoogleFonts.inter(
                      fontSize: OTokens.textXs,
                      color: pal.lossRed,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: OTokens.s2, vertical: OTokens.s1),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              const Spacer(),
              if (!_isEmpty)
                Text(
                  'Signature captured',
                  style: GoogleFonts.inter(
                    fontSize: OTokens.textXs,
                    color: pal.gainGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Reports the current SVG to the parent FormScope (if any).
  void _reportSvg() {
    final renderBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(400, 160);
    final svg = exportSvg(width: size.width, height: size.height);
    FormScope.maybeOf(context)?.report(widget.element.id, svg);
  }

  /// Exports all strokes as an SVG string.
  String exportSvg({required double width, required double height}) {
    final strokeColorHex =
        widget.element.config['strokeColor'] as String? ?? '#1e293b';
    final strokeWidth =
        (widget.element.config['strokeWidth'] as num?)?.toDouble() ?? 2.0;

    final buffer = StringBuffer();
    buffer.write(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height">');

    for (final stroke in _strokes) {
      if (stroke.isEmpty) continue;
      buffer.write('<path d="M ${stroke[0].dx} ${stroke[0].dy}');
      for (var i = 1; i < stroke.length; i++) {
        buffer.write(' L ${stroke[i].dx} ${stroke[i].dy}');
      }
      buffer.write(
          '" fill="none" stroke="$strokeColorHex" stroke-width="$strokeWidth" stroke-linecap="round" stroke-linejoin="round"/>');
    }

    buffer.write('</svg>');
    return buffer.toString();
  }

  static Color _hexToColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return const Color(0xFF1E293B);
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset>? currentStroke;
  final Color strokeColor;
  final double strokeWidth;

  const _SignaturePainter({
    required this.strokes,
    required this.currentStroke,
    required this.strokeColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = strokeColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    void drawStroke(List<Offset> pts) {
      if (pts.isEmpty) return;
      if (pts.length == 1) {
        canvas.drawCircle(pts[0], strokeWidth / 2, paint);
        return;
      }
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (var i = 1; i < pts.length - 1; i++) {
        final mid = Offset(
          (pts[i].dx + pts[i + 1].dx) / 2,
          (pts[i].dy + pts[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(pts.last.dx, pts.last.dy);
      canvas.drawPath(path, paint);
    }

    for (final stroke in strokes) {
      drawStroke(stroke);
    }
    if (currentStroke != null) {
      drawStroke(currentStroke!);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) =>
      old.strokes != strokes ||
      old.currentStroke != currentStroke ||
      old.strokeColor != strokeColor ||
      old.strokeWidth != strokeWidth;
}

class _BuilderPlaceholder extends StatelessWidget {
  final double height;
  const _BuilderPlaceholder({this.height = 120});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    return CustomPaint(
      painter: _DashedBorderPainter(pal.borderSubtle),
      child: SizedBox(
        height: height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.penTool,
                  size: 24, color: pal.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 6),
              Text(
                'Signature Pad',
                style: GoogleFonts.inter(
                  fontSize: OTokens.textXs,
                  color: pal.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter(this.borderColor);

  /// A painter has no BuildContext, so the scoped colour is passed in.
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
      const Radius.circular(OTokens.radiusSm),
    );
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final end = math.min(d + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter _) => false;
}
