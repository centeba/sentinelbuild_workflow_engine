import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../element_renderer.dart';
import 'data_fetch.dart';
import 'value_from_evaluator.dart';

/// KPI tile. When `element.dataBinding` is set:
///   - fetches the bound response
///   - if `config.valueFrom` is set, runs it through `evaluateValueFrom`
///   - otherwise reads the scalar at `dataBinding.responsePath`
///   - displays the result as `value`
///   - subscribes to `refreshOn` events; on emit re-fetches
class StatCardElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const StatCardElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  ConsumerState<StatCardElement> createState() => _StatCardElementState();
}

class _StatCardElementState extends ConsumerState<StatCardElement> {
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
    final config = widget.element.config;
    final binding = widget.element.dataBinding;
    final ctxMap = ref.watch(bindingContextProvider);
    final ctx = ctxMap[widget.pageId];

    if (binding == null || widget.mode == RenderMode.builder || ctx == null) {
      return _shell(config, (config['value'] as String?) ?? '—');
    }

    return FutureBuilder<dynamic>(
      // Re-key on _refreshTick so refreshOn forces a fresh future.
      key: ValueKey('statcard-${widget.element.id}-$_refreshTick'),
      future: fetchBindingBody(ctx, binding),
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _shell(config, '…');
        }
        if (snap.hasError) return _shell(config, '!');
        final body = snap.data;
        final valueFrom = config['valueFrom'] as String?;
        dynamic derived;
        if (valueFrom != null && valueFrom.isNotEmpty) {
          derived = evaluateValueFrom(valueFrom, body);
        } else {
          final rp = binding.responsePath.isEmpty ? r'$' : binding.responsePath;
          if (rp == r'$') {
            derived = body;
          } else {
            // Path drill via the response-token helper in fetchBindingValue
            // is overkill here — just call it directly with explicit path.
            derived = _drill(body, rp);
          }
        }
        final shown = derived == null ? '—' : '$derived';
        return _shell(config, shown);
      },
    );
  }

  /// Map a light tint background (tailwind *-50) → a saturated semantic accent
  /// for the card's left bar. Unknown/none → brand teal.
  static Color _accentFromTint(Color? bg, OPaletteData pal) {
    if (bg == null) return pal.primaryBlue;
    switch (bg.toARGB32() & 0xFFFFFF) {
      case 0xEFF6FF:
        return pal.neutralBlue; // blue-50
      case 0xFFFBEB:
        return pal.warningAmber; // amber-50
      case 0xFEF2F2:
        return pal.lossRed; // red-50
      case 0xECFDF5:
        return pal.gainGreen; // green-50
      default:
        return pal.primaryBlue; // teal
    }
  }

  static dynamic _drill(dynamic body, String path) {
    final segs = path
        .replaceAllMapped(RegExp(r'\[(\d+)\]'), (m) => '.${m.group(1)}')
        .split('.')
        .where((s) => s.isNotEmpty && s != r'$')
        .toList();
    dynamic current = body;
    for (final s in segs) {
      if (current is Map) {
        current = current[s];
      } else if (current is List) {
        final i = int.tryParse(s);
        if (i == null || i < 0 || i >= current.length) return null;
        current = current[i];
      } else {
        return null;
      }
    }
    return current;
  }

  Widget _shell(Map<String, dynamic> config, String value) {
    final label = config['label'] as String? ?? 'Metric';
    final prefix = config['prefix'] as String? ?? '';
    final suffix = config['suffix'] as String? ?? '';
    final delta = config['delta'] as String?;
    final deltaPositive = config['deltaPositive'] as bool? ?? true;
    final pal = OPaletteScope.of(context);
    // Left-accent colour: an explicit page borderColor wins; otherwise derive a
    // saturated accent from the page-authored tint background (cards historically
    // carried a *-50 tint), mapping to the semantic palette. Clean white surface.
    final accentColor = widget.element.style?.resolvedBorderColor(pal) ??
        _accentFromTint(widget.element.style?.resolvedBackgroundColor(pal), pal);

    final side = BorderSide(color: pal.borderSubtle);
    return Container(
      padding: const EdgeInsets.all(OTokens.s5),
      decoration: BoxDecoration(
        color: pal.bgSurface,
        borderRadius: BorderRadius.circular(OTokens.radiusLg),
        // Colored left-accent bar (mockup summary-card style).
        border: Border(
          left: BorderSide(color: accentColor, width: 4),
          top: side,
          right: side,
          bottom: side,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: OTokens.textXs,
              fontWeight: FontWeight.w600,
              color: pal.textMuted,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: OTokens.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (prefix.isNotEmpty)
                Text(prefix,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: OTokens.textMd,
                      fontWeight: FontWeight.w500,
                      color: accentColor,
                    )),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: OTokens.text2xl,
                    fontWeight: FontWeight.w700,
                    color: pal.textBright,
                    letterSpacing: -0.02,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
                  if (suffix.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(suffix,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: OTokens.textMd,
                            color: OPaletteScope.of(context).textSecondary,
                          )),
                    ),
                ],
              ),
              if (delta != null && delta.isNotEmpty) ...[
                const SizedBox(height: OTokens.s2),
                Row(
                  children: [
                    Icon(
                      deltaPositive ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                      size: 13,
                      color: deltaPositive ? OPaletteScope.of(context).gainGreen : OPaletteScope.of(context).lossRed,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      delta,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: OTokens.textXs,
                        fontWeight: FontWeight.w600,
                        color: deltaPositive ? OPaletteScope.of(context).gainGreen : OPaletteScope.of(context).lossRed,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
  }
}
