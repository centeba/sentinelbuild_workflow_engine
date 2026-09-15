import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import 'form_scope.dart';

class SwitchFieldElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const SwitchFieldElement({super.key, required this.element, required this.mode});

  @override
  State<SwitchFieldElement> createState() => _SwitchFieldElementState();
}

class _SwitchFieldElementState extends State<SwitchFieldElement> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.element.config['defaultValue'] as bool? ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.element.config['label'] as String? ?? 'Enable feature';
    final interactive = widget.mode != RenderMode.builder;

    return Row(
      children: [
        Switch(
          value: _value,
          onChanged: interactive
              ? (v) {
                  setState(() => _value = v);
                  FormScope.maybeOf(context)
                      ?.report(widget.element.id, v);
                }
              : null,
          activeThumbColor: Colors.white,
          activeTrackColor: OPaletteScope.of(context).primaryBlue,
          inactiveThumbColor: OPaletteScope.of(context).textSecondary,
          inactiveTrackColor: OPaletteScope.of(context).bgSurface,
          trackOutlineColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return OPaletteScope.of(context).primaryBlue;
            }
            return OPaletteScope.of(context).borderStrong;
          }),
        ),
        const SizedBox(width: OTokens.s2),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: OTokens.textSm,
              color: OPaletteScope.of(context).textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
