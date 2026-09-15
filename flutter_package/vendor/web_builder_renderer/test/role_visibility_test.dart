// Phase 6 of documents/platform/web-builder-roadmap.md — element-level role-visibility filtering.
//
// Verifies that PageRendererWidget hides elements whose `roleVisibility`
// list doesn't intersect the active session's roles.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_builder_renderer/web_builder_renderer.dart';

PageDefinition _twoElementPage({
  List<String>? gateAdminOnly,
}) {
  return PageDefinition(
    id: 'p1',
    title: 'Demo',
    slug: 'demo',
    sections: const [PageSection(id: 's1', pageId: 'p1', title: 'Main', order: 0)],
    elements: [
      PageElement(
        id: 'always',
        type: PageElementType.text,
        sectionId: 's1',
        rowIndex: 0,
        config: const {'text': 'ALWAYS_VISIBLE'},
      ),
      PageElement(
        id: 'admin-only',
        type: PageElementType.text,
        sectionId: 's1',
        rowIndex: 1,
        config: const {'text': 'ADMIN_ONLY'},
        roleVisibility: gateAdminOnly,
      ),
    ],
  );
}

Widget _harness({required PageDefinition page, Map<String, dynamic>? ctx}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: PageRendererWidget(
          page: page,
          initialContext: ctx ?? const {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'element with no roleVisibility is visible regardless of session roles',
      (tester) async {
    await tester.pumpWidget(_harness(
      page: _twoElementPage(gateAdminOnly: null),
      ctx: {
        'session': {
          'roles': <String>['member'],
        },
      },
    ));
    await tester.pump();
    expect(find.textContaining('ALWAYS_VISIBLE'), findsOneWidget);
    expect(find.textContaining('ADMIN_ONLY'), findsOneWidget);
  });

  testWidgets(
      'element with roleVisibility hidden when user roles do not intersect',
      (tester) async {
    await tester.pumpWidget(_harness(
      page: _twoElementPage(gateAdminOnly: ['admin', 'system_admin']),
      ctx: {
        'session': {
          'roles': <String>['member'],
        },
      },
    ));
    await tester.pump();
    expect(find.textContaining('ALWAYS_VISIBLE'), findsOneWidget);
    expect(find.textContaining('ADMIN_ONLY'), findsNothing);
  });

  testWidgets(
      'element with roleVisibility shown when user roles intersect',
      (tester) async {
    await tester.pumpWidget(_harness(
      page: _twoElementPage(gateAdminOnly: ['admin', 'system_admin']),
      ctx: {
        'session': {
          'roles': <String>['system_admin'],
        },
      },
    ));
    await tester.pump();
    expect(find.textContaining('ALWAYS_VISIBLE'), findsOneWidget);
    expect(find.textContaining('ADMIN_ONLY'), findsOneWidget);
  });

  testWidgets(
      'no session.roles in context → role-gated element hidden (fail closed)',
      (tester) async {
    await tester.pumpWidget(_harness(
      page: _twoElementPage(gateAdminOnly: ['member']),
      // No session at all
      ctx: const {},
    ));
    await tester.pump();
    expect(find.textContaining('ALWAYS_VISIBLE'), findsOneWidget);
    expect(find.textContaining('ADMIN_ONLY'), findsNothing);
  });

  test('PageElement.toJson roundtrips roleVisibility', () {
    const original = PageElement(
      id: 'x',
      type: PageElementType.text,
      roleVisibility: ['admin', 'platform_admin'],
    );
    final json = original.toJson();
    expect(json['roleVisibility'], ['admin', 'platform_admin']);
    final round = PageElement.fromJson(json);
    expect(round.roleVisibility, ['admin', 'platform_admin']);
  });

  test('PageElement.fromJson accepts snake_case role_visibility', () {
    final round = PageElement.fromJson({
      'id': 'x',
      'type': 'text',
      'role_visibility': ['admin'],
    });
    expect(round.roleVisibility, ['admin']);
  });
}
