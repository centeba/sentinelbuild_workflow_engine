import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';

/// Stub renderer for the `computed` field type. Full expression
/// evaluation (e.g. `{qty} * {price}`) lands as a follow-up — when
/// `ExpressionResolver` gains a math/formula evaluator we wire this
/// to compute the value reactively against `formValues`.
///
/// For now we surface the configured formula as read-only text in
/// builder mode + a labelled placeholder in preview / published modes,
/// so designers can configure the field and forms still serialise
/// correctly.
class ComputedElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const ComputedElement({
    super.key,
    required this.element,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final label = element.config['label'] as String? ?? 'Computed';
    final formula = element.config['formula'] as String? ?? '';

    return FormFieldShell(
      label: label,
      required: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: OTokens.s3, vertical: OTokens.s3),
        decoration: BoxDecoration(
          color: pal.bgRaised,
          border: Border.all(color: pal.borderSubtle),
          borderRadius: BorderRadius.circular(OTokens.radiusSm),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.calculator,
                size: 14, color: pal.textMuted),
            const SizedBox(width: OTokens.s2),
            Expanded(
              child: Text(
                formula.isEmpty
                    ? (mode == RenderMode.builder
                        ? 'Set a formula in the config panel.'
                        : '—')
                    : formula,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: OTokens.textSm,
                  color: formula.isEmpty
                      ? pal.textMuted
                      : pal.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
