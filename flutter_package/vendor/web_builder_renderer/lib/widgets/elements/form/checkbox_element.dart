// Checkbox is functionally identical to CheckboxField.
// Delegates to CheckboxFieldElement.
import 'package:flutter/material.dart';
import '../../../models/page_element.dart';
import '../element_renderer.dart';
import 'checkbox_field_element.dart';

class CheckboxElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const CheckboxElement(
      {super.key, required this.element, required this.mode});

  @override
  Widget build(BuildContext context) {
    return CheckboxFieldElement(element: element, mode: mode);
  }
}
