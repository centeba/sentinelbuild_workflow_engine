// Self-contained translations for mit_stack — no external i18n SDK.
//
// English strings are bundled as a package asset and loaded once at startup via
// [Translations.ensureLoaded]. `context.t('a.b.c')` does a nested lookup and,
// when a string is missing, falls back to a humanized key (``snake_case`` →
// "Sentence case") so labels never render raw dot-keys.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

class Translations {
  Translations._();

  static final Translations instance = Translations._();

  // Package assets are addressed as packages/<pkg>/<path> from any host app.
  static const String _assetPath =
      'packages/mit_stack/assets/i18n/mit_stack_en.json';

  Map<String, dynamic> _data = const {};
  bool _loaded = false;

  /// Loads the bundled catalog once. Safe to call multiple times. On failure
  /// the catalog stays empty and every key humanizes.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      _data = json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      _data = const {};
    }
    _loaded = true;
  }

  String lookup(String key) {
    dynamic current = _data;
    for (final segment in key.split('.')) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return _humanizeKey(key);
      }
    }
    return current is String ? current : _humanizeKey(key);
  }
}

String _humanizeKey(String key) {
  final segment = key.split('.').last.trim();
  // Interpolation placeholders (``$foo``) and empty segments aren't labels.
  if (segment.isEmpty || segment.startsWith(r'$')) return key;
  final words = segment.replaceAll('_', ' ').trim();
  if (words.isEmpty) return key;
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

extension TranslateExtension on BuildContext {
  /// Look up a dot-namespaced translation key in the bundled catalog.
  String t(String key) => Translations.instance.lookup(key);
}
