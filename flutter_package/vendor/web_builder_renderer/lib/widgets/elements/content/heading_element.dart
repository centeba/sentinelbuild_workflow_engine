import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';

class HeadingElement extends StatelessWidget {
  final PageElement element;

  const HeadingElement({super.key, required this.element});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final text = element.config['text'] as String? ?? 'Heading';
    final level = element.config['level'] as int? ?? 2;
    final style = element.style;

    final fontSize = style?.fontSize ??
        switch (level) {
          1 => OTokens.text4xl,
          2 => OTokens.text3xl,
          3 => OTokens.text2xl,
          4 => OTokens.textXl,
          5 => OTokens.textLg,
          _ => OTokens.textMd,
        };

    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: fontSize,
        fontWeight: style?.resolvedFontWeight ?? FontWeight.w700,
        color: style?.resolvedColor(pal) ?? pal.textBright,
        height: 1.2,
        letterSpacing: level <= 2 ? -0.02 : 0,
      ),
      textAlign: style?.resolvedTextAlign ?? TextAlign.left,
    );
  }
}
