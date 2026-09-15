import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class SearchFieldElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const SearchFieldElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final placeholder = element.config['placeholder'] as String? ?? 'Search...';

    return TextField(
      enabled: mode != RenderMode.builder,
      style: GoogleFonts.inter(fontSize: OTokens.textSm, color: pal.textPrimary),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: GoogleFonts.inter(fontSize: OTokens.textSm, color: pal.textMuted),
        prefixIcon: Padding(
          padding: EdgeInsets.only(left: OTokens.s3, right: OTokens.s2),
          child: Icon(LucideIcons.search, size: 16, color: pal.textMuted),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        filled: true,
        fillColor: pal.bgSurface,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: OTokens.s3, vertical: OTokens.s3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OTokens.radiusFull),
          borderSide: BorderSide(color: pal.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OTokens.radiusFull),
          borderSide: BorderSide(color: pal.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OTokens.radiusFull),
          borderSide: BorderSide(color: pal.primaryBlue, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OTokens.radiusFull),
          borderSide: BorderSide(color: pal.borderSubtle.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}
