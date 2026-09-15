import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class OrderedListElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const OrderedListElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final rawItems = element.config['items'];
    final items = (rawItems is List) ? rawItems.cast<String>() : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: OTokens.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${i + 1}.',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: OTokens.textSm,
                    fontWeight: FontWeight.w600,
                    color: OPaletteScope.of(context).primaryBlue,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  item,
                  style: GoogleFonts.inter(
                    fontSize: OTokens.textSm,
                    color: OPaletteScope.of(context).textPrimary,
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
