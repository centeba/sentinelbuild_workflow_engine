import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import 'form_scope.dart';

class CheckboxFieldElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const CheckboxFieldElement({super.key, required this.element, required this.mode});

  @override
  State<CheckboxFieldElement> createState() => _CheckboxFieldElementState();
}

class _CheckboxFieldElementState extends State<CheckboxFieldElement> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.element.config['label'] as String? ?? 'Checkbox';
    final interactive = widget.mode != RenderMode.builder;

    return GestureDetector(
      onTap: interactive
          ? () {
              setState(() => _checked = !_checked);
              FormScope.maybeOf(context)
                  ?.report(widget.element.id, _checked);
            }
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: _checked
                  ? OPaletteScope.of(context).primaryBlue
                  : OPaletteScope.of(context).bgSurface,
              borderRadius: BorderRadius.circular(OTokens.radiusXs),
              border: Border.all(
                color: _checked
                    ? OPaletteScope.of(context).primaryBlue
                    : OPaletteScope.of(context).borderStrong,
                width: 1.5,
              ),
            ),
            child: _checked
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : null,
          ),
          const SizedBox(width: OTokens.s2),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: OTokens.textSm,
                color: OPaletteScope.of(context).textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
