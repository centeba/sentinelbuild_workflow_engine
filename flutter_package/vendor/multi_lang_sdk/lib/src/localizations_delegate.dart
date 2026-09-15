import 'package:flutter/widgets.dart';
import 'localizations.dart';
import 'api_client.dart';

/// LocalizationsDelegate that fetches translations from the multi-lang
/// service at runtime.
///
/// Phase L1: ``shouldReload`` correctly returns ``true`` when the
/// active locale, namespace, or userId changes so that swapping the
/// app's locale at runtime causes Flutter to re-call ``load`` and
/// the UI re-renders in the new language. The old static
/// ``_preloadedStrings`` cache was removed because it pinned strings
/// to the *first* locale fetched and silently ignored subsequent
/// locale changes — exactly the behaviour we want to undo.
///
/// Per-(locale, namespace) caching is still useful — it avoids
/// hitting the multi-lang service on every Flutter rebuild — so we
/// keep an instance-level map keyed by ``"$locale|$namespace"``.
class MultiLangDelegate extends LocalizationsDelegate<MultiLangLocalizations> {
  final MultiLangApiClient apiClient;
  final String namespace;
  final String? userId;

  /// Per-(locale, namespace) cache. Kept on the instance so a stale
  /// delegate's cache does not leak into a new one.
  final Map<String, Map<String, dynamic>> _cache = {};

  MultiLangDelegate({
    required this.apiClient,
    required this.namespace,
    this.userId,
  });

  @override
  bool isSupported(Locale locale) => true; // Fully dynamic back-end driven

  String _localeKey(Locale locale) =>
      '${locale.languageCode}${locale.countryCode != null ? '-${locale.countryCode!}' : ''}';

  @override
  Future<MultiLangLocalizations> load(Locale locale) async {
    final targetLocale = _localeKey(locale);
    final cacheKey = '$targetLocale|$namespace';
    final cached = _cache[cacheKey];
    if (cached != null) {
      return MultiLangLocalizations(cached);
    }
    final strings =
        await apiClient.fetchTranslations(namespace, locale: targetLocale);
    _cache[cacheKey] = strings;
    return MultiLangLocalizations(strings);
  }

  @override
  bool shouldReload(MultiLangDelegate old) =>
      old.namespace != namespace || old.userId != userId;
}
