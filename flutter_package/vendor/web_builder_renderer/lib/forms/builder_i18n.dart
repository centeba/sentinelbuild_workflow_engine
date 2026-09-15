// Phase WB2 — translation extension for the form builder.
//
// The form-builder UI was originally written against
// `frontend/mit_stack/lib/i18n/translate_extension.dart`, which is a
// thin wrapper over `MultiLangLocalizations.of(context)?.translate(key)`
// from the `multi_lang_sdk`. To keep the package free of a hard
// dependency on the SDK (the SDK is currently vendored separately
// under each consumer app), the resolution is registered by the host
// at startup:
//
//   import 'package:web_builder_renderer/web_builder_renderer.dart';
//   import 'package:multi_lang_sdk/multi_lang_sdk.dart';
//
//   void main() {
//     registerBuilderTranslator((ctx, key) =>
//         MultiLangLocalizations.of(ctx)?.translate(key) ?? key);
//     runApp(...);
//   }
//
// If a host doesn't register a translator, `context.t('key')` returns
// the key verbatim — same fallback shape as the SDK's `translate`.
import 'package:flutter/widgets.dart';

/// Resolves a translation key against the host's locale. Hosts wire
/// this once at startup via [registerBuilderTranslator].
typedef BuilderTranslator = String Function(BuildContext context, String key);

String _identityTranslator(BuildContext _, String key) => key;

BuilderTranslator _translator = _identityTranslator;

/// Register the host's translator. Subsequent calls overwrite the
/// previous registration — typically called once in `main()`.
void registerBuilderTranslator(BuilderTranslator translator) {
  _translator = translator;
}

/// `context.t('key')` — drop-in equivalent of mit_stack's
/// `translate_extension`. Always returns a non-null string;
/// fallback is the key itself.
extension BuilderTranslateExtension on BuildContext {
  String t(String key) => _translator(this, key);
}
