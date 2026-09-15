/// CI drift guard + regenerator for the element catalog the AI page
/// builder ships to Claude.
///
/// **Why this test exists.** Before May 2026 the catalog at
/// `services/pages-api/src/pages_api/ai/schema/element_types.json` was
/// hand-written and quietly drifted from `kElementRegistry` in this
/// package. Adding a new `ElementMeta` without touching the JSON
/// silently shrank the LLM's vocabulary (it never learned the new
/// type); removing one in the registry left the LLM emitting a type
/// the renderer no longer knew about. This test makes the registry the
/// single source of truth.
///
/// **How it works.**
///   * Default mode (`WRITE_CATALOG` env unset) — generates the
///     expected catalog in-memory by walking `kElementRegistry`, reads
///     the checked-in JSON, byte-compares them. Mismatch → test fails
///     with instructions for regen.
///   * Write mode (`WRITE_CATALOG=1`) — generates the catalog and
///     overwrites the JSON file. Run this after adding/removing an
///     element type in the Dart registry, then commit both files.
///
/// **Usage.**
///   # verify (CI):
///   flutter test test/element_catalog_sync_test.dart
///   # regenerate after registry change:
///   WRITE_CATALOG=1 flutter test test/element_catalog_sync_test.dart
///
/// **Cross-package output path** — the JSON lives in
/// `services/pages-api/` because Python is the consumer. The Dart side
/// here owns the contract; the file is just the wire format. The
/// relative path below assumes the conventional monorepo layout.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_builder_renderer/constants/element_registry.dart';

void main() {
  test('element_types.json matches kElementRegistry (drift guard)', () {
    final expected = _buildCatalog();
    final expectedText = _encode(expected);

    final jsonFile = _findCatalogFile();
    if (!jsonFile.existsSync()) {
      fail('Expected catalog file at ${jsonFile.path} but it does not '
          'exist. Run `WRITE_CATALOG=1 flutter test '
          'test/element_catalog_sync_test.dart` from this package to '
          'generate it.');
    }

    if (Platform.environment['WRITE_CATALOG'] == '1') {
      jsonFile.writeAsStringSync('$expectedText\n');
      // ignore: avoid_print
      print('Wrote ${jsonFile.path} (${expected.length - 1} elements)');
      return;
    }

    final actualText = jsonFile.readAsStringSync().trimRight();
    if (actualText != expectedText) {
      // Surface a useful diff hint. The full JSONs would be too noisy
      // in test output; report the symmetric difference of keys instead
      // since "added/removed an element type" is the dominant case.
      Map<String, dynamic> _decode(String s) {
        try {
          return jsonDecode(s) as Map<String, dynamic>;
        } catch (_) {
          return const {};
        }
      }

      final actualMap = _decode(actualText);
      final expectedKeys = expected.keys.where((k) => !k.startsWith('_')).toSet();
      final actualKeys =
          actualMap.keys.where((k) => !k.startsWith('_')).toSet();
      final onlyExpected = expectedKeys.difference(actualKeys);
      final onlyActual = actualKeys.difference(expectedKeys);

      final hints = <String>[];
      if (onlyExpected.isNotEmpty) {
        hints.add('  added to registry but missing from JSON: $onlyExpected');
      }
      if (onlyActual.isNotEmpty) {
        hints.add(
            '  removed from registry but still in JSON: $onlyActual');
      }
      if (hints.isEmpty) {
        hints.add('  same keys but one or more entries (label / '
            'category / description / defaultConfig) differ');
      }

      fail('element_types.json is out of sync with kElementRegistry.\n'
          '${hints.join('\n')}\n\n'
          'Regenerate with:\n'
          '  WRITE_CATALOG=1 flutter test test/element_catalog_sync_test.dart\n'
          '(run from packages/web_builder_renderer/), then commit both '
          'this Dart change and the regenerated JSON.');
    }
  });
}

/// Builds the catalog the pages-api LLM prompt expects. Header `_doc`
/// matches `tool/dump_element_catalog.dart`'s old format so the file
/// stays self-documenting.
Map<String, dynamic> _buildCatalog() {
  final entries = <String, Map<String, dynamic>>{};
  for (final meta in kElementRegistry) {
    entries[meta.type.name] = {
      'label': meta.label,
      'category': meta.category.name,
      'description': meta.description,
      'defaultConfig': meta.defaultConfig,
    };
  }
  return {
    '_doc': 'GENERATED from packages/web_builder_renderer/lib/constants/'
        'element_registry.dart by '
        'packages/web_builder_renderer/test/element_catalog_sync_test.dart. '
        'Do NOT edit by hand — re-run the regenerator with '
        'WRITE_CATALOG=1. pages-api filters keys starting with "_" before '
        'sending to the LLM.',
    ...entries,
  };
}

String _encode(Map<String, dynamic> catalog) {
  return const JsonEncoder.withIndent('  ').convert(catalog);
}

/// Walks up from the test file looking for the SentinelBuild repo root
/// (identified by `infrastructure/docker-compose.yml`), then resolves
/// the catalog file relative to it. Falls back to a hard-coded relative
/// path if the heuristic doesn't find a root — covers shallow checkouts
/// or unusual cwds.
File _findCatalogFile() {
  // Repo-relative path; the OS-native separator gets normalized by File().
  const rel = 'services/pages-api/src/pages_api/ai/schema/element_types.json';
  final sep = Platform.pathSeparator;
  final relNative = rel.replaceAll('/', sep);
  Directory? dir = Directory.current;
  for (var i = 0; i < 8 && dir != null; i++) {
    final marker = File('${dir.path}${sep}infrastructure${sep}docker-compose.yml');
    if (marker.existsSync()) {
      return File('${dir.path}$sep$relNative');
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  // Fallback: assume the test is being run from packages/web_builder_renderer/.
  return File('..${sep}..${sep}$relNative');
}
