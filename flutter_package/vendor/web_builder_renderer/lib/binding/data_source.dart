import 'dart:convert';

import 'package:dio/dio.dart';

/// A registered HTTP data source the binding runtime can address by name.
///
/// Pages express remote data via `{{api.<source>.<jsonpath>}}` expressions —
/// the resolver looks up the source by `<source>`, calls [fetch], evaluates
/// `<jsonpath>` against the result, and substitutes the value into the
/// rendered string.
///
/// Vertical apps register sources at `PageRendererWidget.initialContext`
/// time:
///
/// ```dart
/// PageRendererWidget(
///   page: page,
///   bindingContext: BindingContext(
///     dataSources: {
///       'crm': HttpDataSource(
///         baseUrl: 'https://api.example.com',
///         authTokenProvider: () => session.token,
///       ),
///     },
///     ...
///   ),
/// )
/// ```
///
/// Caching: identical (path, params) pairs return the same value within the
/// element's lifetime. Call [invalidate] to bust the cache when the
/// underlying data changes (typically on a `refreshOn` event firing).
class HttpDataSource {
  /// Optional base URL — when present, [fetch] paths are appended.
  final String? baseUrl;

  /// Optional auth-token provider. Called per-request so token rotations are
  /// picked up without rebuilding the data source.
  final String? Function()? authTokenProvider;

  /// Static headers always included in every request.
  final Map<String, String> staticHeaders;

  late final Dio _dio;
  final _cache = <String, dynamic>{};

  HttpDataSource({
    this.baseUrl,
    this.authTokenProvider,
    this.staticHeaders = const {},
    Dio? dio,
  }) {
    _dio = dio ??
        Dio(BaseOptions(
          baseUrl: baseUrl ?? '',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        ));
  }

  /// Fetches `path` (joined with [baseUrl] if relative). Returns the parsed
  /// JSON body. Cached by `(path, params)`.
  Future<dynamic> fetch(
    String path, {
    Map<String, dynamic>? queryParams,
  }) async {
    final cacheKey = _key(path, queryParams);
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    final headers = <String, String>{...staticHeaders};
    final token = authTokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final resp = await _dio.get(
      path,
      queryParameters: queryParams,
      options: Options(headers: headers),
    );
    _cache[cacheKey] = resp.data;
    return resp.data;
  }

  /// Drops cached entries. Optionally limited to a `path` prefix; otherwise
  /// flushes everything.
  void invalidate({String? pathPrefix}) {
    if (pathPrefix == null) {
      _cache.clear();
      return;
    }
    _cache.removeWhere((k, _) => k.startsWith('$pathPrefix:'));
  }

  String _key(String path, Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return '$path:';
    return '$path:${jsonEncode(params)}';
  }
}
