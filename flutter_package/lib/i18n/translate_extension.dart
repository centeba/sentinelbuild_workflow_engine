// SPDX-License-Identifier: BUSL-1.1
//
// Phase L3 — translation lookup helper for the embedded mit_stack
// package.
//
// Mirror of the host app's helper at
// ``frontend/sentinel_build/lib/core/i18n/translate_extension.dart``.
// Lives inside the package so mit_stack screens stay self-contained.
// The Localizations widget at the host's MaterialApp root carries
// the active ``MultiLangLocalizations`` — sentinel_build's
// ``pubspec_overrides.yaml`` flattens both packages' vendored
// ``multi_lang_sdk`` paths to a single resolution so the
// ``MultiLangLocalizations`` type matches across the boundary.
//
// Returns the key itself when no translation is registered, matching
// the SDK's ``MultiLangLocalizations.translate`` fallback.

import 'package:flutter/widgets.dart';
import 'package:multi_lang_sdk/multi_lang_sdk.dart';

extension TranslateExtension on BuildContext {
  /// Look up a dot-namespaced translation key against the active
  /// ``MultiLangLocalizations``.
  String t(String key) =>
      MultiLangLocalizations.of(this)?.translate(key) ?? key;
}
