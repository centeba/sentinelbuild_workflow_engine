import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

/// Time-of-day picker. Tap opens `showTimePicker`; the value is stored
/// + reported as `HH:MM` (24h). Mirrors `DatePickerElement`'s shape.
class TimeFieldElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const TimeFieldElement({
    super.key,
    required this.element,
    required this.mode,
  });

  @override
  State<TimeFieldElement> createState() => _TimeFieldElementState();
}

class _TimeFieldElementState extends State<TimeFieldElement> {
  TimeOfDay? _selected;

  @override
  Widget build(BuildContext context) {
    final label = widget.element.config['label'] as String? ?? 'Time';
    final placeholder =
        widget.element.config['placeholder'] as String? ?? 'Select a time';
    final required = widget.element.config['required'] as bool? ?? false;
    final interactive = widget.mode != RenderMode.builder;

    final displayText = _selected != null
        ? _selected!.format(context)
        : placeholder;

    return FormFieldShell(
      label: label,
      required: required,
      child: GestureDetector(
        onTap: interactive ? () => _pickTime(context) : null,
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
              Icon(LucideIcons.clock,
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

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selected ?? TimeOfDay.now(),
    );
    if (picked != null && mounted) {
      setState(() => _selected = picked);
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      // ignore: use_build_context_synchronously
      FormScope.maybeOf(context)
          ?.report(widget.element.id, '$hh:$mm');
    }
  }
}
