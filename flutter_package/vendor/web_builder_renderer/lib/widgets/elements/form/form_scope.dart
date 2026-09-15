import 'package:flutter/widgets.dart';

/// InheritedWidget that propagates a value-reporting callback down the
/// form element tree. Form field widgets call [report] to push their current
/// value up to the parent [FormElement] so it can collect all field values
/// at submit time without modifying [ElementRenderer]'s API.
///
/// Usage in a form field:
/// ```dart
/// TextField(
///   onChanged: (v) => FormScope.maybeOf(context)?.report(element.id, v),
/// )
/// ```
class FormScope extends InheritedWidget {
  /// ID of the parent [FormElement] (used for keying if multiple forms exist).
  final String formId;

  /// Called by child field elements to report their current value.
  /// [fieldId] is the element's unique ID; [value] is the typed value
  /// (String, bool, double, List<String>, etc.).
  final void Function(String fieldId, dynamic value) report;

  /// Submit the enclosing form. A `formSubmitButton` child calls this so the
  /// page-authored button actually triggers the parent [FormElement]'s submit
  /// (PATCH/POST) instead of being an inert button.
  final Future<void> Function() submit;

  /// Whether the form is mid-submit (so the button can disable / show a spinner).
  final bool submitting;

  const FormScope({
    super.key,
    required this.formId,
    required this.report,
    required this.submit,
    this.submitting = false,
    required super.child,
  });

  /// Returns the nearest [FormScope] ancestor, or null if the field is not
  /// inside a Form element in preview mode.
  static FormScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FormScope>();

  @override
  bool updateShouldNotify(FormScope old) =>
      formId != old.formId || submitting != old.submitting;
}
