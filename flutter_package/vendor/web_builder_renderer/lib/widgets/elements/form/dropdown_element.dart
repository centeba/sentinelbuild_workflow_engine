// Dropdown is functionally identical to SelectField.
// Delegates to SelectFieldElement so we share the interaction logic.
export 'select_field_element.dart' show SelectFieldElement;

import 'package:flutter/material.dart';
import '../../../models/page_element.dart';
import '../element_renderer.dart';
import 'select_field_element.dart';

class DropdownElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const DropdownElement(
      {super.key, required this.element, required this.mode, this.pageId = ''});

  @override
  Widget build(BuildContext context) {
    return SelectFieldElement(element: element, mode: mode, pageId: pageId);
  }
}
