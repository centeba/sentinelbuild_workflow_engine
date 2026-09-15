import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class VideoElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const VideoElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final url = element.config['url'] as String? ?? '';
    final aspectRatio = element.config['aspectRatio'] as String? ?? '16:9';
    final parts = aspectRatio.split(':');
    final ratio = parts.length == 2
        ? (double.tryParse(parts[0]) ?? 16) / (double.tryParse(parts[1]) ?? 9)
        : 16 / 9;

    return AspectRatio(
      aspectRatio: ratio,
      child: Container(
        decoration: BoxDecoration(
          color: pal.bgSurface,
          borderRadius: BorderRadius.circular(OTokens.radiusMd),
          border: Border.all(color: pal.borderSubtle),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: pal.lossRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.video, size: 24, color: pal.lossRed),
            ),
            const SizedBox(height: OTokens.s3),
            Text(
              url.isNotEmpty ? url : 'No video URL configured',
              style: GoogleFonts.inter(fontSize: OTokens.textXs, color: pal.textMuted),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: OTokens.s1),
            Text(
              'Aspect ratio $aspectRatio',
              style: GoogleFonts.inter(fontSize: OTokens.textXs, color: pal.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
