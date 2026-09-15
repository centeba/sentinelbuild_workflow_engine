// mit_stack is a library-only package (no app entry point / no `main.dart`),
// so the original `flutter create` template test (which pumped `MyApp`) never
// applied. This smoke test imports the package's public surface — forcing the
// whole library to compile — and verifies a trivial widget renders.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// The import is intentional: pulling in the public surface forces the whole
// library to compile as part of this test, even though no symbol is referenced
// directly below.
// ignore: unused_import
import 'package:mit_stack/mit_stack.dart';

void main() {
  testWidgets('mit_stack package compiles and a widget renders',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('mit_stack'))),
    );
    expect(find.text('mit_stack'), findsOneWidget);
  });
}
