import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

class DatePickerElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const DatePickerElement({super.key, required this.element, required this.mode});

  @override
  State<DatePickerElement> createState() => _DatePickerElementState();
}

class _DatePickerElementState extends State<DatePickerElement> {
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final label = widget.element.config['label'] as String? ?? 'Date';
    final placeholder = widget.element.config['placeholder'] as String? ?? 'Select a date';
    final required = widget.element.config['required'] as bool? ?? false;
    final interactive = widget.mode != RenderMode.builder;

    final displayText = _selected != null
        ? '${_selected!.day}/${_selected!.month}/${_selected!.year}'
        : placeholder;

    return FormFieldShell(
      label: label,
      required: required,
      child: GestureDetector(
        onTap: interactive ? () => _pickDate(context) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: OTokens.s3, vertical: OTokens.s3),
          decoration: BoxDecoration(
            color: pal.bgSurface,
            borderRadius: BorderRadius.circular(OTokens.radiusSm),
            border: Border.all(
              color: _selected != null
                  ? pal.primaryBlue.withValues(alpha: 0.5)
                  : pal.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.calendar,
                  size: 14,
                  color: _selected != null
                      ? pal.primaryBlue
                      : pal.textMuted),
              const SizedBox(width: OTokens.s2),
              Expanded(
                child: Text(
                  displayText,
                  style: GoogleFonts.inter(
                    fontSize: OTokens.textSm,
                    color: _selected != null
                        ? pal.textPrimary
                        : pal.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final pal = OPaletteScope.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
            primary: pal.primaryBlue,
            surface: pal.bgSurface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selected = picked);
      FormScope.maybeOf(context)
          ?.report(widget.element.id, picked.toIso8601String());
    }
  }
}
