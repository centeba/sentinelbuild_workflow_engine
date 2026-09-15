import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import 'form_scope.dart';

class FormSubmitButtonElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const FormSubmitButtonElement(
      {super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    final label = element.config['label'] as String? ?? 'Submit';
    final interactive = mode != RenderMode.builder;
    // Trigger the enclosing form's submit. Previously this was a no-op `(){}`,
    // so authored submit buttons (project edit, notes, action items, …) did
    // nothing and those forms appeared read-only.
    final scope = FormScope.maybeOf(context);
    final submitting = scope?.submitting ?? false;
    final onTap = (!interactive || scope == null || submitting)
        ? null
        : () => scope.submit();

    // Explicit ElevatedButton with hardcoded colors. The themed FilledButton
    // path renders invisibly in some host themes (e.g. restoration), making the
    // Save button white-on-white so forms looked read-only. An ElevatedButton
    // with an explicit fill is guaranteed visible. minimumSize gives it a solid
    // tap target even when the label is short.
    const accent = Color(0xFF2563EB);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF93A8E8),
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
          padding: const EdgeInsets.symmetric(
              horizontal: OTokens.s6, vertical: OTokens.s3),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OTokens.radiusSm)),
        ),
        child: submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: OTokens.textSm,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
