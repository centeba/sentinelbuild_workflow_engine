import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

class NumberFieldElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const NumberFieldElement({super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final label = element.config['label'] as String? ?? 'Amount';
    final placeholder = element.config['placeholder'] as String? ?? '0.00';
    final prefix = element.config['prefix'] as String? ?? '';
    final suffix = element.config['suffix'] as String? ?? '';
    final required = element.config['required'] as bool? ?? false;

    return FormFieldShell(
      label: label,
      required: required,
      child: TextField(
        enabled: mode != RenderMode.builder,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (v) => FormScope.maybeOf(context)?.report(
            element.id, num.tryParse(v.replaceAll(',', '')) ?? v),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
        ],
        style: GoogleFonts.jetBrainsMono(
          fontSize: OTokens.textSm,
          color: pal.textBright,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: GoogleFonts.jetBrainsMono(
            fontSize: OTokens.textSm,
            color: pal.textMuted,
          ),
          prefixText: prefix.isNotEmpty ? prefix : null,
          prefixStyle: GoogleFonts.jetBrainsMono(
            fontSize: OTokens.textSm,
            color: pal.textSecondary,
          ),
          suffixText: suffix.isNotEmpty ? suffix : null,
          suffixStyle: GoogleFonts.jetBrainsMono(
            fontSize: OTokens.textSm,
            color: pal.textSecondary,
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
            borderSide: BorderSide(color: pal.borderSubtle.withValues(alpha: 0.5)),
          ),
        ),
      ),
    );
  }
}
