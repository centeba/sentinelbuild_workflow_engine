import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class BulletListElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const BulletListElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final rawItems = element.config['items'];
    final items = (rawItems is List) ? rawItems.cast<String>() : <String>[];
    final style = element.config['style'] as String? ?? 'disc';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: OTokens.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: style == 'check'
                    ? Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.check, size: 14, color: pal.gainGreen),
                      )
                    : style == 'arrow'
                        ? Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(Icons.chevron_right, size: 14,
                                color: pal.primaryBlue),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: pal.textMuted,
                              ),
                            ),
                          ),
              ),
              Expanded(
                child: Text(
                  item,
                  style: GoogleFonts.inter(
                    fontSize: OTokens.textSm,
                    color: pal.textPrimary,
                    height: 1.6,
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
