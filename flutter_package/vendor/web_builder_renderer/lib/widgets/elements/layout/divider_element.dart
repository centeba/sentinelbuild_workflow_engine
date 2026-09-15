import 'package:flutter/material.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';

class DividerElement extends StatelessWidget {
  final PageElement element;

  const DividerElement({super.key, required this.element});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final color =
        element.style?.resolvedBorderColor(pal) ?? pal.borderSubtle;
    final thickness =
        (element.config['thickness'] as num?)?.toDouble() ?? 1.0;

    return Divider(
      color: color,
      thickness: thickness,
      height: thickness + 16,
    );
  }
}
