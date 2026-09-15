import 'package:flutter/material.dart';
import '../../../models/page_element.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

/// URL input — text field with URL-style keyboard. The renderer doesn't
/// validate strictly so designers can accept partial URLs (e.g.
/// `example.com` without a scheme). Reports the raw string to FormScope.
class UrlFieldElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const UrlFieldElement({
    super.key,
    required this.element,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final label = element.config['label'] as String? ?? 'URL';
    final placeholder =
        element.config['placeholder'] as String? ?? 'https://…';
    final required = element.config['required'] as bool? ?? false;
    final interactive = mode != RenderMode.builder;

    return FormFieldShell(
      label: label,
      required: required,
      child: TextField(
        enabled: interactive,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(hintText: placeholder),
        onChanged: (v) =>
            FormScope.maybeOf(context)?.report(element.id, v),
      ),
    );
  }
}
