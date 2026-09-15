import 'package:flutter/material.dart';

import '../../../models/page_element.dart';
import 'form_scope.dart';

/// Visually-hidden honeypot input. Real users never see it; bots that fill
/// every field they encounter will populate it and get silently dropped by
/// `pages-api`'s public-submit endpoint.
///
/// Form value key defaults to `_hp` — must match the constant in
/// `services/pages-api/src/pages_api/api/routes/public.py`.
class HoneypotElement extends StatelessWidget {
  final PageElement element;
  const HoneypotElement({super.key, required this.element});

  @override
  Widget build(BuildContext context) {
    final fieldName = element.config['name'] as String? ?? '_hp';
    final scope = FormScope.maybeOf(context);

    // We render a 1x1 transparent input that sits behind everything. CSS
    // tricks (display:none) trip some bots' detection; an off-screen real
    // input is the most reliable shape.
    return ExcludeSemantics(
      child: SizedBox(
        width: 1,
        height: 1,
        child: Opacity(
          opacity: 0.0,
          child: TextField(
            autofillHints: const [],
            // Bots autofill on `name` like "url", "email", "address" — pick
            // a name that looks plausible. The form scope writes whatever
            // they type into the `_hp` slot regardless of the visible name.
            decoration: InputDecoration(
              labelText: element.config['label'] as String? ?? 'Website',
              hintText: 'Leave blank',
              border: InputBorder.none,
            ),
            onChanged: (v) => scope?.report(fieldName, v),
          ),
        ),
      ),
    );
  }
}
