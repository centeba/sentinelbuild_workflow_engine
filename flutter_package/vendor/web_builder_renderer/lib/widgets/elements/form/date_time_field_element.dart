import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

/// Combined date + time picker. Tap chains `showDatePicker` then
/// `showTimePicker`; the value is reported as ISO-8601 to the FormScope.
class DateTimeFieldElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const DateTimeFieldElement({
    super.key,
    required this.element,
    required this.mode,
  });

  @override
  State<DateTimeFieldElement> createState() => _DateTimeFieldElementState();
}

class _DateTimeFieldElementState extends State<DateTimeFieldElement> {
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final label = widget.element.config['label'] as String? ?? 'Date & Time';
    final placeholder = widget.element.config['placeholder'] as String? ??
        'Select a date and time';
    final required = widget.element.config['required'] as bool? ?? false;
    final interactive = widget.mode != RenderMode.builder;

    String displayText;
    if (_selected == null) {
      displayText = placeholder;
    } else {
      final d = _selected!;
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      displayText = '${d.day}/${d.month}/${d.year}  $hh:$mm';
    }

    return FormFieldShell(
      label: label,
      required: required,
      child: GestureDetector(
        onTap: interactive ? () => _pick(context) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: OTokens.s3, vertical: OTokens.s3),
          decoration: BoxDecoration(
            color: OPaletteScope.of(context).bgSurface,
            borderRadius: BorderRadius.circular(OTokens.radiusSm),
            border: Border.all(
              color: _selected != null
                  ? OPaletteScope.of(context).primaryBlue.withValues(alpha: 0.5)
                  : OPaletteScope.of(context).borderSubtle,
            ),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.calendarClock,
                  size: 14,
                  color: _selected != null
                      ? OPaletteScope.of(context).primaryBlue
                      : OPaletteScope.of(context).textMuted),
              const SizedBox(width: OTokens.s2),
              Expanded(
                child: Text(
                  displayText,
                  style: GoogleFonts.inter(
                    fontSize: OTokens.textSm,
                    color: _selected != null
                        ? OPaletteScope.of(context).textPrimary
                        : OPaletteScope.of(context).textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final initial = _selected ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    // ignore: use_build_context_synchronously
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() => _selected = combined);
    // ignore: use_build_context_synchronously
    FormScope.maybeOf(context)
        ?.report(widget.element.id, combined.toIso8601String());
  }
}
