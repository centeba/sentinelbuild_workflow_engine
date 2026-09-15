// Multi-lang Phase 2 — verifies that ElementRenderer pre-resolves
// `{{i18n.*}}` and other binding tokens in element config before passing
// them to the underlying widget.
//
// Synchronous pumps only — runAsync would try to fetch GoogleFonts over
// the network. The renderer's i18n + session token paths are sync (only
// `api.*` is async).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_builder_renderer/web_builder_renderer.dart';

PageDefinition _pageWith(PageElement element) => PageDefinition(
      id: 'p1',
      title: 'Demo',
      slug: 'demo',
      sections: const [
        PageSection(id: 's1', pageId: 'p1', title: 'Main', order: 0),
      ],
      elements: [element],
    );

Widget _harness({
  required PageDefinition page,
  BindingContext? bindingContext,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: PageRendererWidget(
          page: page,
          bindingContext: bindingContext,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('text element resolves {{i18n.x}} in config[text]',
      (tester) async {
    final translator = StaticTranslator({
      'web-builder.lead.title': 'Hello translated world',
    });
    const element = PageElement(
      id: 'el1',
      type: PageElementType.text,
      sectionId: 's1',
      rowIndex: 0,
      config: {'text': '{{i18n.web-builder.lead.title}}'},
    );

    await tester.pumpWidget(_harness(
      page: _pageWith(element),
      bindingContext: BindingContext(translator: translator),
    ));
    await tester.pump();

    expect(find.text('Hello translated world'), findsOneWidget);
  });

  testWidgets('unresolved i18n key falls back to verbatim token',
      (tester) async {
    const element = PageElement(
      id: 'el1',
      type: PageElementType.text,
      sectionId: 's1',
      rowIndex: 0,
      config: {'text': '{{i18n.missing.key}}'},
    );
    await tester.pumpWidget(_harness(
      page: _pageWith(element),
      bindingContext: BindingContext(
          translator: const StaticTranslator({})),
    ));
    await tester.pump();

    expect(find.text('{{i18n.missing.key}}'), findsOneWidget);
  });

  testWidgets('non-i18n binding tokens (session.user.email) resolve too',
      (tester) async {
    const element = PageElement(
      id: 'el1',
      type: PageElementType.text,
      sectionId: 's1',
      rowIndex: 0,
      config: {'text': 'Hi {{session.user.email}}'},
    );
    await tester.pumpWidget(_harness(
      page: _pageWith(element),
      bindingContext: BindingContext(
        session: {
          'user': {'email': 'a@b.test'}
        },
      ),
    ));
    await tester.pump();

    expect(find.text('Hi a@b.test'), findsOneWidget);
  });

  testWidgets('without bindingContext, raw config is preserved (legacy)',
      (tester) async {
    const element = PageElement(
      id: 'el1',
      type: PageElementType.text,
      sectionId: 's1',
      rowIndex: 0,
      config: {'text': '{{i18n.greeting}}'},
    );
    await tester.pumpWidget(_harness(page: _pageWith(element)));
    await tester.pump();

    expect(find.text('{{i18n.greeting}}'), findsOneWidget);
  });
}
