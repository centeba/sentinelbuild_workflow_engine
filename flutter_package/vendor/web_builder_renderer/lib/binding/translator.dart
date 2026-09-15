/// Multi-lang integration — minimal contract the renderer uses to resolve
/// `{{i18n.<dotted.key>}}` tokens at render time.
///
/// The renderer package never imports `multi_lang_sdk` directly. Host apps
/// using SentinelBuild's multi-lang service construct a one-line adapter
/// (see `frontend/web_builder/lib/services/multi_lang_translator_adapter.dart`)
/// and inject it via `BindingContext.translator`. Apps without multi-lang
/// fall back to [NoopTranslator] and `i18n.*` tokens render the verbatim
/// token (matching multi-lang's own "return key on miss" convention).

library;

abstract class Translator {
  /// Returns the translated string for [key], or null when missing.
  /// Convention matches `multi_lang_sdk`: dot-path keys, namespace-prefixed
  /// (e.g. `"web-builder.lead.submit_button"`).
  String? translate(String key);
}

/// Default implementation when no translator is supplied. Every lookup
/// returns null so the resolver leaves the `{{i18n.x}}` token verbatim and
/// designers can spot unbound keys.
class NoopTranslator implements Translator {
  const NoopTranslator();
  @override
  String? translate(String key) => null;
}

/// Convenience implementation for tests and host apps that ship a static
/// translation map (no service round-trip).
class StaticTranslator implements Translator {
  final Map<String, String> entries;
  const StaticTranslator(this.entries);

  @override
  String? translate(String key) => entries[key];
}
