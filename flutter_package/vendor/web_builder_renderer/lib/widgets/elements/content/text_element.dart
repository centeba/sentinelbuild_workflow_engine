import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../_value_format.dart';

class TextElement extends StatelessWidget {
  final PageElement element;

  const TextElement({super.key, required this.element});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    // Format any ISO timestamps in the (already token-resolved) text so e.g.
    // "… · DOL 2026-06-06T00:00:00Z" reads "… · DOL Jun 6, 2026".
    final text = formatIsoDatesIn(element.config['text'] as String? ?? 'Text');
    final style = element.style;

    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: style?.fontSize ?? OTokens.textBase,
        color: style?.resolvedColor(pal) ?? pal.textPrimary,
        fontWeight: style?.resolvedFontWeight ?? FontWeight.w400,
        height: 1.6,
      ),
      textAlign: style?.resolvedTextAlign ?? TextAlign.left,
    );
  }
}
