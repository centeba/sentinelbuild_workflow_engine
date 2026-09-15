import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_builder_renderer/web_builder_renderer.dart';

/// The active [SiteStorage] for the running app.
///
/// Defaults to [LocalSiteStorage] (designer's machine). Host apps that
/// store sites server-side (e.g. SentinelBuild chassis) override this
/// with a [RemoteSiteStorage] via `ProviderScope(overrides: [...])`.
final siteStorageProvider = Provider<SiteStorage>((ref) {
  return LocalSiteStorage();
});

/// Strategy for persisting [SiteDefinition]s.
///
/// Two implementations ship in this package:
/// - [LocalSiteStorage] — designer-only, backs onto `SharedPreferences`.
/// - [RemoteSiteStorage] — calls the `pages-api` service so sites/pages
///   round-trip through the platform and other deployed apps can render
///   the same published versions.
///
/// A vertical app can implement its own ([SiteStorage]) if it wants a
/// different backend.
abstract class SiteStorage {
  Future<List<SiteDefinition>> loadAll();
  Future<void> save(SiteDefinition site);
  Future<void> delete(String siteId);
  Future<SiteDefinition?> loadById(String id);
  Future<SiteDefinition?> loadBySlug(String slug);
}

// ─────────────────────────────────────────────────────────────────────────────
// LocalSiteStorage — SharedPreferences-backed (designer's machine only).
// ─────────────────────────────────────────────────────────────────────────────

class LocalSiteStorage implements SiteStorage {
  static const _allSitesKey = 'wb_site_ids';
  static const _sitePrefix = 'wb_site_';

  @override
  Future<List<SiteDefinition>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_allSitesKey) ?? [];
    final sites = <SiteDefinition>[];
    for (final id in ids) {
      final json = prefs.getString('$_sitePrefix$id');
      if (json != null) {
        try {
          sites.add(SiteDefinition.fromJson(
              jsonDecode(json) as Map<String, dynamic>));
        } catch (_) {}
      }
    }
    return sites;
  }

  @override
  Future<void> save(SiteDefinition site) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_allSitesKey) ?? [];
    if (!ids.contains(site.id)) {
      ids.add(site.id);
      await prefs.setStringList(_allSitesKey, ids);
    }
    await prefs.setString(
        '$_sitePrefix${site.id}', jsonEncode(site.toJson()));
  }

  @override
  Future<void> delete(String siteId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_allSitesKey) ?? [];
    ids.remove(siteId);
    await prefs.setStringList(_allSitesKey, ids);
    await prefs.remove('$_sitePrefix$siteId');
  }

  @override
  Future<SiteDefinition?> loadById(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_sitePrefix$id');
    if (json == null) return null;
    try {
      return SiteDefinition.fromJson(
          jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SiteDefinition?> loadBySlug(String slug) async {
    final all = await loadAll();
    try {
      return all.firstWhere((s) => s.slug == slug);
    } catch (_) {
      return null;
    }
  }
}

/// Backwards-compatible alias for callers that imported the old concrete
/// class. New code should depend on [SiteStorage] (the interface) and pick
/// an implementation explicitly.
typedef SiteStorageService = LocalSiteStorage;

// ─────────────────────────────────────────────────────────────────────────────
// RemoteSiteStorage — talks to services/pages-api.
//
// Site/page split: pages-api stores a row per site and a row per page (with
// versioned definitions). Locally, a SiteDefinition bundles both. This
// implementation transparently bridges by:
//   - on `save(site)` — upsert the site, then upsert each child page as a
//     new draft version (PUT /sites/{id}/pages/{slug});
//   - on `loadById(id)` — fetch the site, list pages, fetch each page's
//     latest draft definition, reassemble.
//
// Versioning is exposed at the route level (?version=published|draft|N) but
// this client always reads `draft` so the designer sees the latest unsaved
// work; a future "preview as published" mode flips the param.
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the current bearer token (or null for unauthenticated requests).
typedef AuthTokenProvider = String? Function();

class RemoteSiteStorage implements SiteStorage {
  final String baseUrl;
  final AuthTokenProvider _authTokenProvider;
  late final Dio _dio;

  RemoteSiteStorage({
    required this.baseUrl,
    required AuthTokenProvider authTokenProvider,
    Dio? dio,
  }) : _authTokenProvider = authTokenProvider {
    _dio = dio ??
        Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _authTokenProvider();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  // ── Sites ──────────────────────────────────────────────────────────────────

  @override
  Future<List<SiteDefinition>> loadAll() async {
    final resp = await _dio.get('/api/v1/sites');
    final list = resp.data as List<dynamic>;
    final sites = <SiteDefinition>[];
    for (final raw in list) {
      final summary = raw as Map<String, dynamic>;
      final full = await _hydrateSite(summary);
      if (full != null) sites.add(full);
    }
    return sites;
  }

  @override
  Future<SiteDefinition?> loadById(String id) async {
    try {
      final resp = await _dio.get('/api/v1/sites/$id');
      return _hydrateSite(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<SiteDefinition?> loadBySlug(String slug) async {
    final all = await loadAll();
    try {
      return all.firstWhere((s) => s.slug == slug);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(SiteDefinition site) async {
    // 1) Upsert site row (create if id is unknown to server, else PATCH name/theme).
    Map<String, dynamic>? existing;
    try {
      final r = await _dio.get('/api/v1/sites/${site.id}');
      existing = r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      existing = null;
    }

    if (existing == null) {
      await _dio.post('/api/v1/sites', data: {
        'name': site.name,
        'slug': site.slug,
        if (site.appId != null) 'app_id': site.appId,
        if (site.audienceCompanyType != null)
          'audience_company_type': site.audienceCompanyType,
        if (site.asTemplate) 'as_template': true,
        'theme_json': site.theme.toJson(),
        if (site.globalContext.isNotEmpty)
          'global_context_json': site.globalContext,
      });
    } else {
      await _dio.patch('/api/v1/sites/${site.id}', data: {
        'name': site.name,
        'slug': site.slug,
        if (site.appId != null) 'app_id': site.appId,
        if (site.audienceCompanyType != null)
          'audience_company_type': site.audienceCompanyType,
        'theme_json': site.theme.toJson(),
        if (site.globalContext.isNotEmpty)
          'global_context_json': site.globalContext,
      });
    }

    // 2) Upsert each page as a new draft version. Visibility / anti-abuse
    // fields stored on PageDefinition flow through to pages-api as
    // first-class SavePageRequest params (separate from the `definition`
    // JSON blob — pages-api stores them on the row directly).
    for (final page in site.pages) {
      await _dio.put(
        '/api/v1/sites/${site.id}/pages/${page.slug.isEmpty ? page.id : page.slug}',
        data: {
          'title': page.title,
          'definition': page.toJson(),
          if (page.publicAccess) 'public': true,
          if (page.roleVisibility != null)
            'role_visibility': page.roleVisibility,
          if (page.rateLimits != null) 'rate_limits_json': page.rateLimits,
          if (page.captchaConfig != null)
            'captcha_config_json': page.captchaConfig,
          if (page.submissionConfig != null)
            'submission_config_json': page.submissionConfig,
        },
      );
    }
  }

  @override
  Future<void> delete(String siteId) async {
    try {
      await _dio.delete('/api/v1/sites/$siteId');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return;
      rethrow;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<SiteDefinition?> _hydrateSite(Map<String, dynamic> siteRow) async {
    final siteId = siteRow['id'] as String;

    // Fetch page list, then each page's latest draft definition.
    final pagesResp = await _dio.get('/api/v1/sites/$siteId/pages');
    final pageRows = pagesResp.data as List<dynamic>;

    final pages = <PageDefinition>[];
    for (final r in pageRows) {
      final summary = r as Map<String, dynamic>;
      final slug = summary['slug'] as String;
      try {
        final detail = await _dio.get(
          '/api/v1/sites/$siteId/pages/$slug',
          queryParameters: {'version': 'draft'},
        );
        final defJson =
            (detail.data as Map<String, dynamic>)['definition_json'];
        if (defJson is Map<String, dynamic>) {
          pages.add(PageDefinition.fromJson(defJson));
        }
      } on DioException {
        // Skip pages whose definition can't be fetched — corrupt rows
        // shouldn't break the whole site load.
        continue;
      }
    }

    final themeJson = siteRow['theme_json'];
    final ctxJson = siteRow['global_context_json'];

    return SiteDefinition(
      id: siteId,
      name: siteRow['name'] as String? ?? '',
      slug: siteRow['slug'] as String? ?? '',
      theme: themeJson is Map<String, dynamic>
          ? SiteTheme.fromJson(themeJson)
          : const SiteTheme(),
      pages: pages,
      globalContext:
          ctxJson is Map<String, dynamic> ? ctxJson : const {},
      appId: siteRow['app_id'] as String?,
      audienceCompanyType: siteRow['audience_company_type'] as String?,
    );
  }
}
