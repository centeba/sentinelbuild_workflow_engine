import 'package:flutter/material.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';

class ImageElement extends StatelessWidget {
  final PageElement element;

  const ImageElement({super.key, required this.element});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final src = element.config['src'] as String? ?? '';
    final alt = element.config['alt'] as String? ?? '';
    final fitStr = element.config['fit'] as String? ?? 'cover';
    final fit = switch (fitStr) {
      'contain' => BoxFit.contain,
      'fill' => BoxFit.fill,
      _ => BoxFit.cover,
    };
    final borderRadius = element.style?.borderRadius ?? 0.0;

    if (src.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: pal.bgRaised,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: pal.borderSubtle),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined,
                size: 28, color: pal.textMuted),
            const SizedBox(height: 6),
            Text(
              alt.isEmpty ? 'Image' : alt,
              style: TextStyle(
                  fontSize: OTokens.textXs, color: pal.textMuted),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        src,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(
          height: 120,
          color: pal.bgRaised,
          child: Center(
            child: Icon(Icons.broken_image_outlined,
                size: 28, color: pal.textMuted),
          ),
        ),
      ),
    );
  }
}
