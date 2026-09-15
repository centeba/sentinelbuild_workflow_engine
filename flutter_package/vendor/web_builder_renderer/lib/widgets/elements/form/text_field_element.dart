import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

class TextFieldElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const TextFieldElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final label = element.config['label'] as String? ?? 'Label';
    final placeholder = element.config['placeholder'] as String? ?? '';
    final required = element.config['required'] as bool? ?? false;

    return FormFieldShell(
      label: label,
      required: required,
      child: TextField(
        enabled: mode != RenderMode.builder,
        onChanged: (v) => FormScope.maybeOf(context)?.report(element.id, v),
        style: GoogleFonts.inter(
          fontSize: OTokens.textSm,
          color: pal.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: GoogleFonts.inter(
            fontSize: OTokens.textSm,
            color: pal.textMuted,
          ),
          filled: true,
          fillColor: pal.bgSurface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: OTokens.s3,
            vertical: OTokens.s3,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(OTokens.radiusSm),
            borderSide: BorderSide(color: pal.borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(OTokens.radiusSm),
            borderSide: BorderSide(color: pal.borderSubtle),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(OTokens.radiusSm),
            borderSide: BorderSide(color: pal.primaryBlue, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(OTokens.radiusSm),
            borderSide: BorderSide(
                color: pal.borderSubtle.withValues(alpha: 0.5)),
          ),
        ),
      ),
    );
  }
}
