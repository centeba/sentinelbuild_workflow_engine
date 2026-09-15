import 'package:flutter/material.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

/// Star rating. Default 5 stars; configurable via `config['max']`.
/// Tapping a star sets the rating to that value; the active value is
/// reported to the FormScope as an integer.
class RatingElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const RatingElement({
    super.key,
    required this.element,
    required this.mode,
  });

  @override
  State<RatingElement> createState() => _RatingElementState();
}

class _RatingElementState extends State<RatingElement> {
  int _value = 0;

  @override
  Widget build(BuildContext context) {
    final label = widget.element.config['label'] as String? ?? 'Rating';
    final required = widget.element.config['required'] as bool? ?? false;
    final max = (widget.element.config['max'] as num?)?.toInt() ?? 5;
    final interactive = widget.mode != RenderMode.builder;

    return FormFieldShell(
      label: label,
      required: required,
      child: Row(
        children: [
          for (var i = 1; i <= max; i++)
            IconButton(
              padding: const EdgeInsets.all(2),
              constraints: const BoxConstraints(),
              icon: Icon(
                i <= _value ? Icons.star : Icons.star_border,
                color: i <= _value
                    ? OPaletteScope.of(context).warningAmber
                    : OPaletteScope.of(context).textMuted,
                size: 22,
              ),
              onPressed: interactive
                  ? () {
                      setState(() => _value = i);
                      FormScope.maybeOf(context)
                          ?.report(widget.element.id, i);
                    }
                  : null,
            ),
        ],
      ),
    );
  }
}
