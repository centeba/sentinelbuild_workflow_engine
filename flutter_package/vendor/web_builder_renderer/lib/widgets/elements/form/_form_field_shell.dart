import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';

class FormFieldShell extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;
  final String? helperText;

  const FormFieldShell({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      // stretch so children (drop zones, multi-line fields) take the
      // full available width instead of shrinking to their intrinsic
      // size, which would leave most of the row un-tappable.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: OTokens.textXs,
                fontWeight: FontWeight.w500,
                color: OPaletteScope.of(context).textSecondary,
                letterSpacing: 0.04,
              ),
            ),
            if (required) ...[
              const SizedBox(width: 3),
              Text(
                '*',
                style: TextStyle(
                  fontSize: OTokens.textXs,
                  color: OPaletteScope.of(context).lossRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: OTokens.s2),
        child,
        if (helperText != null) ...[
          const SizedBox(height: OTokens.s1),
          Text(
            helperText!,
            style: GoogleFonts.inter(
              fontSize: OTokens.textXs,
              color: OPaletteScope.of(context).textMuted,
            ),
          ),
        ],
      ],
    );
  }
}
