import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';

class PasswordFieldElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const PasswordFieldElement({super.key, required this.element, required this.mode});

  @override
  State<PasswordFieldElement> createState() => _PasswordFieldElementState();
}

class _PasswordFieldElementState extends State<PasswordFieldElement> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final label = widget.element.config['label'] as String? ?? 'Password';
    final placeholder = widget.element.config['placeholder'] as String? ?? 'Enter password';
    final required = widget.element.config['required'] as bool? ?? false;

    return FormFieldShell(
      label: label,
      required: required,
      child: TextField(
        enabled: widget.mode != RenderMode.builder,
        obscureText: _obscure,
        style: GoogleFonts.inter(fontSize: OTokens.textSm, color: pal.textPrimary),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: GoogleFonts.inter(fontSize: OTokens.textSm, color: pal.textMuted),
          suffixIcon: GestureDetector(
            onTap: () => setState(() => _obscure = !_obscure),
            child: Padding(
              padding: const EdgeInsets.only(right: OTokens.s3),
              child: Icon(
                _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                size: 16,
                color: pal.textMuted,
              ),
            ),
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          filled: true,
          fillColor: pal.bgSurface,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: OTokens.s3, vertical: OTokens.s3),
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
