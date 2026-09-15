import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

class RangeSliderElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const RangeSliderElement({super.key, required this.element, required this.mode});

  @override
  State<RangeSliderElement> createState() => _RangeSliderElementState();
}

class _RangeSliderElementState extends State<RangeSliderElement> {
  late double _value;

  @override
  void initState() {
    super.initState();
    final min = (widget.element.config['min'] as num?)?.toDouble() ?? 0.0;
    final max = (widget.element.config['max'] as num?)?.toDouble() ?? 100.0;
    _value = min + (max - min) / 2;
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.element.config['label'] as String? ?? 'Value';
    final min = (widget.element.config['min'] as num?)?.toDouble() ?? 0.0;
    final max = (widget.element.config['max'] as num?)?.toDouble() ?? 100.0;
    final divisions = (widget.element.config['divisions'] as num?)?.toInt();
    final suffix = widget.element.config['suffix'] as String? ?? '';
    final interactive = widget.mode != RenderMode.builder;

    return FormFieldShell(
      label: label,
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: OPaletteScope.of(context).primaryBlue,
              inactiveTrackColor: OPaletteScope.of(context).bgSurface,
              thumbColor: OPaletteScope.of(context).primaryBlue,
              overlayColor: OPaletteScope.of(context).primaryBlue.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              trackHeight: 4,
            ),
            child: Slider(
              value: _value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: interactive
                  ? (v) {
                      setState(() => _value = v);
                      FormScope.maybeOf(context)
                          ?.report(widget.element.id, v);
                    }
                  : null,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${min.toStringAsFixed(0)}$suffix',
                style: GoogleFonts.jetBrainsMono(fontSize: OTokens.textXs, color: OPaletteScope.of(context).textMuted),
              ),
              Text(
                '${_value.toStringAsFixed(0)}$suffix',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: OTokens.textSm,
                  fontWeight: FontWeight.w600,
                  color: OPaletteScope.of(context).primaryBlue,
                ),
              ),
              Text(
                '${max.toStringAsFixed(0)}$suffix',
                style: GoogleFonts.jetBrainsMono(fontSize: OTokens.textXs, color: OPaletteScope.of(context).textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
