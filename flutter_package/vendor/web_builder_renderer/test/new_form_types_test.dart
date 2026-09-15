// Smoke test for the 8 form-field types added for parity with the
// mit_stack form_builder's kFieldTypes catalog. Verifies each new
// PageElementType resolves to a real widget in the renderer's switch
// (not the unregistered-element placeholder) and pumps cleanly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_builder_renderer/web_builder_renderer.dart';

const _newTypes = <PageElementType>[
  PageElementType.currency,
  PageElementType.urlField,
  PageElementType.timeField,
  PageElementType.dateTimeField,
  PageElementType.rating,
  PageElementType.hiddenField,
  PageElementType.dataGrid,
  PageElementType.computed,
];

PageDefinition _pageWith(PageElementType type) {
  return PageDefinition(
    id: 'p1',
    title: 'Demo',
    slug: 'demo',
    sections: const [
      PageSection(id: 's1', pageId: 'p1', title: 'Main', order: 0),
    ],
    elements: [
      PageElement(
        id: 'el-${type.name}',
        type: type,
        sectionId: 's1',
        rowIndex: 0,
        colWidth: 12,
      ),
    ],
  );
}

void main() {
  for (final t in _newTypes) {
    testWidgets('renders ${t.name} without throwing', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: PageRendererWidget(page: _pageWith(t))),
          ),
        ),
      );
      await tester.pump();
      // No exception ⇒ the renderer's switch handled the new enum
      // value (rather than falling through to _UnregisteredElement).
      expect(tester.takeException(), isNull);
    });
  }

  test('all 8 new types appear in kElementRegistry', () {
    for (final t in _newTypes) {
      final hit = kElementRegistry.where((m) => m.type == t).firstOrNull;
      expect(hit, isNotNull, reason: '${t.name} must be in kElementRegistry');
    }
  });
}
