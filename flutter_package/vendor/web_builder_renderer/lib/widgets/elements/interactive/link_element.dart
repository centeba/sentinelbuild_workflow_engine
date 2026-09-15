import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class LinkElement extends ConsumerWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const LinkElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = OPaletteScope.of(context);
    final label = element.config['label'] as String? ?? 'Link';

    return InkWell(
      onTap: mode == RenderMode.builder ? null : () {},
      child: Text(
        label,
        style: TextStyle(
          fontSize: element.style?.fontSize ?? OTokens.textBase,
          color: element.style?.resolvedColor(pal) ?? pal.accentCyan,
          decoration: TextDecoration.underline,
          decorationColor: pal.accentCyan.withValues(alpha: 0.5),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
