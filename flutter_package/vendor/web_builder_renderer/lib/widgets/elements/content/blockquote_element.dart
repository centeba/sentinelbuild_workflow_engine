import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class BlockquoteElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const BlockquoteElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final text = element.config['text'] as String? ?? '';
    final attribution = element.config['attribution'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(OTokens.s5, OTokens.s4, OTokens.s4, OTokens.s4),
      decoration: BoxDecoration(
        color: pal.accentCyan.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(OTokens.radiusMd),
        border: Border(
          left: BorderSide(
            color: pal.accentCyan,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: OTokens.textBase,
              color: pal.textSecondary,
              height: 1.7,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (attribution.isNotEmpty) ...[
            const SizedBox(height: OTokens.s3),
            Text(
              '— $attribution',
              style: GoogleFonts.inter(
                fontSize: OTokens.textXs,
                color: pal.textMuted,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.04,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
