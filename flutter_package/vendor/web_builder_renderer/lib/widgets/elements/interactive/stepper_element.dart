import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../data/data_fetch.dart';
import '../element_renderer.dart';

class StepperElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const StepperElement({
    super.key,
    required this.element,
    required this.mode,
    this.pageId = '',
  });

  @override
  ConsumerState<StepperElement> createState() => _StepperElementState();
}

class _StepperElementState extends ConsumerState<StepperElement> {
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
    final rawSteps = widget.element.config['steps'];
    final steps = (rawSteps is List) ? rawSteps.cast<String>() : <String>[];
    final rawLabels = widget.element.config['stepLabels'];
    final labels = (rawLabels is List) ? rawLabels.cast<String>() : steps;
    final staticStep =
        (widget.element.config['currentStep'] as num?)?.toInt() ?? 0;
    final binding = widget.element.dataBinding;
    final ctxMap = ref.watch(bindingContextProvider);
    final ctx = ctxMap[widget.pageId];

    if (binding == null || widget.mode == RenderMode.builder || ctx == null) {
      return _renderBar(steps, labels, staticStep);
    }
    return FutureBuilder<dynamic>(
      key: ValueKey('stepper-${widget.element.id}-$_refreshTick'),
      future: fetchBindingBody(ctx, binding),
      builder: (_, snap) {
        int currentStep = staticStep;
        final body = snap.data;
        final currentStepFrom =
            widget.element.config['currentStepFrom'] as String?;
        if (body is Map && currentStepFrom != null) {
          final v = body[currentStepFrom];
          if (v != null) {
            final i = steps.indexOf('$v');
            if (i >= 0) currentStep = i;
          }
        }
        return _renderBar(steps, labels, currentStep);
      },
    );
  }

  Widget _renderBar(List<String> steps, List<String> labels, int currentStep) {
    final pal = OPaletteScope.of(context);
    const depth = 12.0; // chevron point/notch depth

    return SizedBox(
      height: 60,
      child: Row(
        children: steps.asMap().entries.map((entry) {
          final i = entry.key;
          final label = i < labels.length ? labels[i] : entry.value;
          final isDone = i < currentStep;
          final isCurrent = i == currentStep;
          final isFirst = i == 0;
          final isLast = i == steps.length - 1;

          // Mockup states: active = NAVY fill + white name + teal number;
          // done = teal-tint fill + teal text; pending = light grey + muted.
          final (Color bg, Color fg, Color numColor, String status) = isCurrent
              ? (pal.textBright, Colors.white, pal.primaryBlue, 'In progress')
              : isDone
                  ? (pal.primaryBlue.withValues(alpha: 0.12), pal.primaryBlue,
                      pal.primaryBlue, 'Complete')
                  : (pal.bgHover, pal.textMuted, pal.textMuted, 'Not started');

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: isLast ? 0 : 3),
              child: ClipPath(
                clipper: _ChevronClipper(
                    first: isFirst, last: isLast, depth: depth),
                child: Container(
                  color: bg,
                  padding: EdgeInsets.only(
                    left: isFirst ? 12 : depth + 8,
                    right: isLast ? 12 : depth + 4,
                    top: 8,
                    bottom: 8,
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '0${i + 1}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: numColor,
                        ),
                      ),
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: OTokens.textXs,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        status,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          color: isCurrent
                              ? Colors.white.withValues(alpha: 0.75)
                              : fg.withValues(alpha: 0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Clips a phase block into an interlocking right-pointing chevron. The first
/// block has a flat left edge; the last block a flat right edge.
class _ChevronClipper extends CustomClipper<Path> {
  final bool first;
  final bool last;
  final double depth;
  const _ChevronClipper(
      {required this.first, required this.last, this.depth = 12});

  @override
  Path getClip(Size s) {
    final p = Path();
    final d = depth;
    final midY = s.height / 2;
    p.moveTo(0, 0);
    if (last) {
      p.lineTo(s.width, 0);
      p.lineTo(s.width, s.height);
    } else {
      p.lineTo(s.width - d, 0);
      p.lineTo(s.width, midY); // right point
      p.lineTo(s.width - d, s.height);
    }
    p.lineTo(0, s.height);
    if (!first) {
      p.lineTo(d, midY); // left notch (receives previous block's point)
    }
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant _ChevronClipper old) =>
      old.first != first || old.last != last || old.depth != depth;
}
