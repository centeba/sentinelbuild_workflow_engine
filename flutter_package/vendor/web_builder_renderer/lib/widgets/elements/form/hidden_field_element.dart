import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import 'form_scope.dart';

/// Hidden form field — never visible to the end user but its
/// `defaultValue` is reported to the FormScope so the value lands in
/// the submission payload. In builder mode we render a dashed
/// placeholder so designers can still select / configure it.
class HiddenFieldElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const HiddenFieldElement({
    super.key,
    required this.element,
    required this.mode,
  });

  @override
  State<HiddenFieldElement> createState() => _HiddenFieldElementState();
}

class _HiddenFieldElementState extends State<HiddenFieldElement> {
  bool _reported = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reported) return;
    final value = widget.element.config['defaultValue'];
    if (value != null) {
      // Defer to a microtask so we don't mutate during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FormScope.maybeOf(context)?.report(widget.element.id, value);
          _reported = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    if (widget.mode == RenderMode.builder) {
      final name = widget.element.config['name'] as String? ?? 'hidden';
      return Container(
        padding: const EdgeInsets.symmetric(
            horizontal: OTokens.s3, vertical: OTokens.s2),
        decoration: BoxDecoration(
          color: pal.bgRaised,
          border: Border.all(
              color: pal.borderSubtle, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(OTokens.radiusSm),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.eyeOff,
                size: 14, color: pal.textMuted),
            const SizedBox(width: OTokens.s2),
            Text(
              'Hidden field · $name',
              style: GoogleFonts.inter(
                fontSize: OTokens.textXs,
                color: pal.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }
    // Preview / published — render nothing visible. Value still
    // reports to the form scope via didChangeDependencies above.
    return const SizedBox.shrink();
  }
}
