import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

class CheckboxGroupElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const CheckboxGroupElement(
      {super.key, required this.element, required this.mode});

  @override
  State<CheckboxGroupElement> createState() => _CheckboxGroupElementState();
}

class _CheckboxGroupElementState extends State<CheckboxGroupElement> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final label = widget.element.config['label'] as String? ?? 'Select all that apply';
    final rawOptions = widget.element.config['options'];
    final options =
        (rawOptions is List) ? rawOptions.map((e) => e.toString()).toList() : <String>[];
    final required = widget.element.config['required'] as bool? ?? false;
    final interactive = widget.mode != RenderMode.builder;

    return FormFieldShell(
      label: label,
      required: required,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: options
            .map((opt) => GestureDetector(
                  onTap: interactive
                      ? () {
                          setState(() {
                            if (_selected.contains(opt)) {
                              _selected.remove(opt);
                            } else {
                              _selected.add(opt);
                            }
                          });
                          FormScope.maybeOf(context)
                              ?.report(widget.element.id, _selected.toList());
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
                            color: _selected.contains(opt)
                                ? OPaletteScope.of(context).primaryBlue
                                : OPaletteScope.of(context).bgSurface,
                            borderRadius:
                                BorderRadius.circular(OTokens.radiusXs),
                            border: Border.all(
                              color: _selected.contains(opt)
                                  ? OPaletteScope.of(context).primaryBlue
                                  : OPaletteScope.of(context).borderStrong,
                              width: 1.5,
                            ),
                          ),
                          child: _selected.contains(opt)
                              ? const Icon(Icons.check,
                                  size: 12, color: Colors.white)
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
