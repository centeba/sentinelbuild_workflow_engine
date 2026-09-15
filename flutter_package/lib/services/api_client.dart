import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();

/// Resolves the API base URL.
///
/// Priority:
/// 1. `--dart-define=API_BASE_URL=https://...` at build time (full URL).
/// 2. When running Flutter Web behind nginx (same origin), the compile-time
///    value will be set to `/api/v1` — we expand it using `Uri.base`.
/// 3. Fallback to localhost for local development.
String _resolveBaseUrl() {
  const defined = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  if (defined.isEmpty) return 'http://localhost:8000/api/v1';
  // If it's already an absolute URL, use it directly.
  if (defined.startsWith('http://') || defined.startsWith('https://')) {
    return defined;
  }
  // Relative URL (e.g. "/api/v1") — expand against the current browser origin.
  if (kIsWeb) {
    final base = Uri.base; // e.g. https://myapp.example.com/
    return '${base.scheme}://${base.host}${base.port != 80 && base.port != 443 ? ':${base.port}' : ''}$defined';
  }
  return 'http://localhost:8000$defined';
}

final _baseUrl = _resolveBaseUrl();

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      // Storage keys must match the chassis's AuthService
      // (frontend/sentinel_build/lib/core/auth/auth_service.dart) —
      // `sb_access_token` / `sb_refresh_token`. Using the unprefixed
      // names silently 401s every request because the chassis writes
      // tokens under the `sb_` namespace. (The JSON keys in /login
      // responses stay `access_token`/`refresh_token` — those are
      // user-master's wire format, not local storage keys.)
      final token = await _storage.read(key: 'sb_access_token');
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) async {
      if (error.response?.statusCode == 401) {
        // Try to refresh token
        final refreshToken = await _storage.read(key: 'sb_refresh_token');
        if (refreshToken != null) {
          try {
            final response = await Dio().post('$_baseUrl/auth/refresh', data: {'refresh_token': refreshToken});
            final newToken = response.data['access_token'];
            await _storage.write(key: 'sb_access_token', value: newToken);
            // Retry original request
            error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
            final retryResponse = await dio.fetch(error.requestOptions);
            return handler.resolve(retryResponse);
          } catch (_) {
            await _storage.deleteAll();
          }
        }
      }
      handler.next(error);
    },
  ));

  return dio;
});

class AuthStorage {
  // Keys mirror the chassis's AuthService (`sb_access_token` /
  // `sb_refresh_token`) so the package and host share one
  // secure-storage namespace.
  static Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: 'sb_access_token', value: accessToken);
    await _storage.write(key: 'sb_refresh_token', value: refreshToken);
  }

  static Future<void> clear() async => _storage.deleteAll();

  static Future<bool> hasToken() async => (await _storage.read(key: 'sb_access_token')) != null;
}
