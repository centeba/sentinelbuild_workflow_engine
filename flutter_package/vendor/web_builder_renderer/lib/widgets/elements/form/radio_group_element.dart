import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

class RadioGroupElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const RadioGroupElement({super.key, required this.element, required this.mode});

  @override
  State<RadioGroupElement> createState() => _RadioGroupElementState();
}

class _RadioGroupElementState extends State<RadioGroupElement> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final label = widget.element.config['label'] as String? ?? 'Choose one';
    final rawOptions = widget.element.config['options'];
    final options = (rawOptions is List) ? rawOptions.cast<String>() : <String>[];
    final required = widget.element.config['required'] as bool? ?? false;
    final interactive = widget.mode != RenderMode.builder;

    return FormFieldShell(
      label: label,
      required: required,
      child: Column(
        children: options
            .map((opt) => GestureDetector(
                  onTap: interactive
                      ? () {
                          setState(() => _selected = opt);
                          FormScope.maybeOf(context)
                              ?.report(widget.element.id, opt);
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: OTokens.s2),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _selected == opt
                                ? OPaletteScope.of(context).primaryBlue
                                : OPaletteScope.of(context).bgSurface,
                            border: Border.all(
                              color: _selected == opt
                                  ? OPaletteScope.of(context).primaryBlue
                                  : OPaletteScope.of(context).borderStrong,
                              width: 1.5,
                            ),
                          ),
                          child: _selected == opt
                              ? Center(
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: OTokens.s2),
                        Text(
                          opt,
                          style: GoogleFonts.inter(
                            fontSize: OTokens.textSm,
                            color: OPaletteScope.of(context).textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
