import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class CalloutElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const CalloutElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final variant = element.config['variant'] as String? ?? 'info';
    final title = element.config['title'] as String? ?? '';
    final body = element.config['body'] as String? ?? '';

    final (color, icon) = switch (variant) {
      'warning' => (OPaletteScope.of(context).warningAmber, LucideIcons.alertTriangle),
      'error' => (OPaletteScope.of(context).lossRed, LucideIcons.xCircle),
      'success' => (OPaletteScope.of(context).gainGreen, LucideIcons.checkCircle),
      _ => (OPaletteScope.of(context).neutralBlue, LucideIcons.info),
    };

    return Container(
      padding: const EdgeInsets.all(OTokens.s4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(OTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: OTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: OTokens.textSm,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                if (title.isNotEmpty && body.isNotEmpty)
                  const SizedBox(height: OTokens.s1),
                if (body.isNotEmpty)
                  Text(
                    body,
                    style: GoogleFonts.inter(
                      fontSize: OTokens.textSm,
                      color: OPaletteScope.of(context).textPrimary,
                      height: 1.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
