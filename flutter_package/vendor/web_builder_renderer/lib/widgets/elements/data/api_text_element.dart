import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/element_style.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../element_renderer.dart';
import 'data_fetch.dart';

/// Single text value bound to an API source. The `config.template` is a
/// format string with `{{value}}` substituted for the scalar at
/// `dataBinding.responsePath` (default $). When the response is an
/// object, additional `{{response.<field>}}` tokens substitute its
/// fields.
class ApiTextElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const ApiTextElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  ConsumerState<ApiTextElement> createState() => _ApiTextElementState();
}

class _ApiTextElementState extends ConsumerState<ApiTextElement> {
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
    final pal = OPaletteScope.of(context);
    final template = widget.element.config['template'] as String? ?? '{{value}}';
    final binding = widget.element.dataBinding;
    final style = widget.element.style;
    final ctxMap = ref.watch(bindingContextProvider);
    final ctx = ctxMap[widget.pageId];

    if (widget.mode == RenderMode.builder) {
      return Container(
        padding: const EdgeInsets.symmetric(
            horizontal: OTokens.s3, vertical: OTokens.s2),
        decoration: BoxDecoration(
          color: pal.accentCyan.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(OTokens.radiusSm),
          border: Border.all(color: pal.accentCyan.withValues(alpha: 0.2)),
        ),
        child: Text(
          template,
          style: GoogleFonts.jetBrainsMono(
            fontSize: OTokens.textSm,
            color: pal.accentCyan.withValues(alpha: 0.8),
          ),
        ),
      );
    }

    if (binding == null || ctx == null) {
      return _renderText(template, style, pal);
    }

    return FutureBuilder<dynamic>(
      key: ValueKey('apitext-${widget.element.id}-$_refreshTick'),
      future: fetchBindingValue(ctx, binding),
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _renderText('…', style, pal);
        }
        if (snap.hasError) return _renderText('(load failed)', style, pal);
        final value = snap.data;
        final rendered = _substitute(template, value);
        return _renderText(rendered, style, pal);
      },
    );
  }

  /// Substitute `{{value}}` with the scalar value, and `{{response.X}}`
  /// with fields of the response map (if it is one).
  String _substitute(String template, dynamic value) {
    var out = template.replaceAll('{{value}}', _str(value));
    if (value is Map) {
      out = out.replaceAllMapped(RegExp(r'\{\{response\.([^}]+)\}\}'), (m) {
        return _str(value[m.group(1)]);
      });
    }
    return out;
  }

  String _str(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return '$v';
  }

  Widget _renderText(String text, ElementStyle? style, OPaletteData pal) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: style?.fontSize ?? OTokens.textBase,
        color: style?.resolvedColor(pal) ?? pal.textPrimary,
        fontWeight: style?.resolvedFontWeight ?? FontWeight.w400,
      ),
      textAlign: style?.resolvedTextAlign ?? TextAlign.left,
    );
  }
}
