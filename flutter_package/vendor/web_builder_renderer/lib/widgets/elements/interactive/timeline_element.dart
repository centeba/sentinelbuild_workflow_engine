import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class TimelineElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const TimelineElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final rawItems = element.config['items'];
    final items = (rawItems is List) ? rawItems.cast<Map>() : <Map>[];

    return Column(
      children: items.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value;
        final isLast = i == items.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: OPaletteScope.of(context).primaryBlue,
                        boxShadow: [
                          BoxShadow(
                            color: OPaletteScope.of(context).primaryBlue.withValues(alpha: 0.4),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 1,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: OPaletteScope.of(context).borderSubtle,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      left: OTokens.s3,
                      bottom: isLast ? 0 : OTokens.s5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['title'] as String? ?? '',
                              style: GoogleFonts.inter(
                                fontSize: OTokens.textSm,
                                fontWeight: FontWeight.w600,
                                color: OPaletteScope.of(context).textBright,
                              ),
                            ),
                          ),
                          if ((item['date'] as String? ?? '').isNotEmpty)
                            Text(
                              item['date'] as String,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: OTokens.textXs,
                                color: OPaletteScope.of(context).textMuted,
                              ),
                            ),
                        ],
                      ),
                      if ((item['description'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: OTokens.s1),
                        Text(
                          item['description'] as String,
                          style: GoogleFonts.inter(
                            fontSize: OTokens.textXs,
                            color: OPaletteScope.of(context).textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
