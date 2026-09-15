import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../binding/expression_resolver.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../../page_renderer_widget.dart';
import '../element_renderer.dart';

class ButtonElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const ButtonElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  ConsumerState<ButtonElement> createState() => _ButtonElementState();
}

class _ButtonElementState extends ConsumerState<ButtonElement> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final label =
        widget.element.config['label'] as String? ?? 'Button';
    final variant =
        widget.element.config['variant'] as String? ?? 'primary';
    final iconData = _iconFor(widget.element.config['icon'] as String?);
    final pal = OPaletteScope.of(context);

    // `primary` = solid brand with WHITE (inverse) text for contrast.
    // `secondary` = subtle tonal (light brand fill + brand text/border) — reads
    // as a clear-but-quiet action, not a second loud primary.
    // `outline`/`ghost` unchanged.
    final (bg, fg, borderColor) = switch (variant) {
      'primary' => (pal.primaryBlue, pal.textInverse, pal.primaryBlue),
      'secondary' => (
          pal.primaryBlue.withValues(alpha: 0.10),
          pal.primaryBlue,
          pal.primaryBlue.withValues(alpha: 0.30),
        ),
      'outline' => (Colors.transparent, pal.primaryBlue, pal.primaryBlue),
      'ghost' => (Colors.transparent, pal.textPrimary, Colors.transparent),
      _ => (pal.primaryBlue, pal.textInverse, pal.primaryBlue),
    };
    final solid = variant == 'primary';

    // Align left + size to content so the button hugs its label instead of
    // stretching to fill the grid cell (the page grid wraps each element in a
    // fixed-width SizedBox, which otherwise made a colWidth-12 button a
    // full-width bar).
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.mode != RenderMode.builder
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.mode == RenderMode.builder ? null : _executeAction,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(
                horizontal: OTokens.s5, vertical: OTokens.s3),
            decoration: BoxDecoration(
              color: solid ? bg.withValues(alpha: _hovered ? 1.0 : 0.92) : bg,
              borderRadius: BorderRadius.circular(OTokens.radiusFull),
              border: Border.all(
                color: borderColor.withValues(alpha: solid ? 0.8 : 1.0),
                width: 1,
              ),
              boxShadow: solid && _hovered
                  ? [
                      BoxShadow(
                        color: bg.withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: -4,
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (iconData != null) ...[
                  Icon(iconData, size: 16, color: fg),
                  const SizedBox(width: OTokens.s2),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: OTokens.textBase,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.01,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  /// Map a page-author icon name to a Material icon. Unknown/empty → no icon.
  IconData? _iconFor(String? name) {
    switch (name) {
      case 'edit':
        return Icons.edit_outlined;
      case 'add':
      case 'plus':
        return Icons.add;
      case 'save':
        return Icons.save_outlined;
      case 'delete':
      case 'trash':
        return Icons.delete_outline;
      case 'share':
        return Icons.share_outlined;
      case 'download':
        return Icons.download_outlined;
      case 'upload':
        return Icons.upload_outlined;
      case 'check':
        return Icons.check;
      case 'arrow-right':
      case 'chevron-right':
        return Icons.arrow_forward;
      default:
        return null;
    }
  }

  void _executeAction() {
    if (widget.mode == RenderMode.builder) return;
    final action = widget.element.action;
    if (action == null || action.targetPageId.isEmpty) return;
    final registry = ref.read(pageRendererCallbacksProvider);
    final cb = registry[widget.pageId];
    if (cb is! PageRendererCallbacks) return;
    // Resolve `{{route.id}}` etc. in the navigation target — page
    // authors typically write `to: "/projects/{{route.id}}/edit"`
    // expecting the route token to substitute before the URL hits the
    // host's router. Without this the host's GoRouter receives the
    // literal placeholder and can't find a matching route.
    String target = action.targetPageId;
    final bindingCtx =
        ref.read(bindingContextProvider)[widget.pageId];
    if (bindingCtx != null && target.contains('{{')) {
      try {
        final resolver = ExpressionResolver(bindingCtx);
        target = resolver.resolveValueSync(target).toString();
      } catch (_) {/* leave the literal if the sync resolver throws */}
    }
    // Debug log makes "no routes for location" errors trivially
    // diagnosable: developer sees both the template and the resolved
    // target in the browser console.
    // ignore: avoid_print
    print('[ButtonNavigate] template=${action.targetPageId} resolved=$target');
    cb.onNavigate?.call(target, action.params.map(
      (k, v) => MapEntry(k, v.resolve({})),
    ));
  }
}
