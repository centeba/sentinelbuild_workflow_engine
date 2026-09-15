import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class RichTextElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const RichTextElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final html = element.config['html'] as String? ?? '';

    // Simple HTML stripping for display — full rendering would use flutter_html
    final plain = html
        .replaceAll(RegExp(r'<strong>(.*?)</strong>'), r'$1')
        .replaceAll(RegExp(r'<em>(.*?)</em>'), r'$1')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();

    if (mode == RenderMode.builder) {
      return Container(
        padding: const EdgeInsets.all(OTokens.s3),
        decoration: BoxDecoration(
          color: pal.bgSurface,
          borderRadius: BorderRadius.circular(OTokens.radiusSm),
          border: Border.all(color: pal.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.code, size: 11, color: pal.textMuted),
              const SizedBox(width: 4),
              Text('Rich Text',
                  style: TextStyle(fontSize: OTokens.textXs, color: pal.textMuted)),
            ]),
            const SizedBox(height: OTokens.s2),
            Text(
              plain,
              style: GoogleFonts.inter(fontSize: OTokens.textSm, color: pal.textPrimary, height: 1.6),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    return Text(
      plain,
      style: GoogleFonts.inter(fontSize: OTokens.textSm, color: pal.textPrimary, height: 1.6),
    );
  }
}
