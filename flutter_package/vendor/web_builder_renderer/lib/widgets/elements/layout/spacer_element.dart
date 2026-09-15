import 'package:flutter/material.dart';
import '../../../models/page_element.dart';

class SpacerElement extends StatelessWidget {
  final PageElement element;

  const SpacerElement({super.key, required this.element});

  @override
  Widget build(BuildContext context) {
    final height = (element.config['height'] as num?)?.toDouble() ?? 32.0;
    return SizedBox(height: height);
  }
}
