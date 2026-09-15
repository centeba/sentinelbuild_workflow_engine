import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Dio client for the AI admin screens. Hits integration-hub's
/// ``/ai-agents`` and ``/ai-skills`` factory routers (mounted by the
/// host at ``/api/integration-hub/v1``).
///
/// The host overrides this provider in its `ProviderScope` to inject
/// the right baseUrl and auth interceptor — see SentinelBuild's
/// ``ai_admin_dio_override.dart``.
final aiAdminDioProvider = Provider<Dio>((ref) {
  const baseUrl = String.fromEnvironment(
    'AI_ADMIN_BASE_URL',
    defaultValue: '/api/integration-hub/v1',
  );
  final dio = Dio(BaseOptions(
    baseUrl: kIsWeb ? baseUrl : 'http://localhost$baseUrl',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: const {'Content-Type': 'application/json'},
  ));
  const storage = FlutterSecureStorage();
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      // Storage key must match the chassis's AuthService — `sb_access_token`.
      // This fallback dioProvider is only used when the chassis hasn't
      // overridden `aiAdminDioProvider`; the chassis's override path
      // attaches the token from `authServiceProvider` directly.
      final token = await storage.read(key: 'sb_access_token');
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
  ));
  return dio;
});

class AiAdminApi {
  final Dio _dio;
  AiAdminApi(this._dio);

  // ── Skills ──────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listSkills({
    String? search,
    bool? activeOnly,
    bool allCompanies = false,
  }) async {
    // Default (platform admin): own company + platform-scoped rows only.
    // ``allCompanies=true`` opts into the full cross-tenant list (every
    // tenant's per-company seeded skills — noisy, hence opt-in).
    final r = await _dio.get('/ai-skills/', queryParameters: {
      'limit': 500,
      if (search != null && search.isNotEmpty) 'search': search,
      if (activeOnly == true) 'active': true,
      if (allCompanies) 'all_companies': true,
    });
    return List<Map<String, dynamic>>.from(r.data['data'] ?? []);
  }

  Future<Map<String, dynamic>> createSkill(Map<String, dynamic> body) async {
    final r = await _dio.post('/ai-skills/', data: body);
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> updateSkill(String id, Map<String, dynamic> body) async {
    final r = await _dio.patch('/ai-skills/$id', data: body);
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> deleteSkill(String id) => _dio.delete('/ai-skills/$id');

  /// Returns Python tools registered in `smart_llm.registry`.
  Future<List<Map<String, dynamic>>> listRegistry() async {
    final r = await _dio.get('/ai-skills/registry');
    return List<Map<String, dynamic>>.from(r.data ?? []);
  }

  /// Returns metadata for a single registered tool, including
  /// ``params_schema`` (Phase E1 auto-form rendering).
  Future<Map<String, dynamic>> getRegistryTool(String name) async {
    final r = await _dio.get('/ai-skills/registry/$name');
    return Map<String, dynamic>.from(r.data ?? {});
  }

  // ── Agents ──────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listAgents({
    String? search,
    bool allCompanies = false,
  }) async {
    // Default (platform admin): own company + platform-scoped rows only.
    // ``allCompanies=true`` opts into the full cross-tenant list.
    final r = await _dio.get('/ai-agents/', queryParameters: {
      'limit': 500,
      if (search != null && search.isNotEmpty) 'search': search,
      if (allCompanies) 'all_companies': true,
    });
    return List<Map<String, dynamic>>.from(r.data['data'] ?? []);
  }

  Future<Map<String, dynamic>> createAgent(Map<String, dynamic> body) async {
    final r = await _dio.post('/ai-agents/', data: body);
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> updateAgent(String id, Map<String, dynamic> body) async {
    final r = await _dio.patch('/ai-agents/$id', data: body);
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> deleteAgent(String id) => _dio.delete('/ai-agents/$id');

  // ── Usage (Phase E4) ────────────────────────────────────────────────────
  /// Returns ``{events, by_agent, monthly_budget_usd}`` for the
  /// current company over the last ``days`` (default 30).
  Future<Map<String, dynamic>> getUsage({int days = 30, String? agentId}) async {
    final r = await _dio.get('/ai-usage/', queryParameters: {
      'days': days,
      if (agentId != null) 'agent_id': agentId,
    });
    return Map<String, dynamic>.from(r.data ?? {});
  }

  Future<double> setBudget(double monthlyUsd) async {
    final r = await _dio.patch('/ai-usage/budget',
        data: {'monthly_ai_budget_usd': monthlyUsd});
    return ((r.data?['monthly_ai_budget_usd']) ?? 0).toDouble();
  }

  // ── PII & AI compliance (company defaults) ──────────────────────────────
  /// Company settings incl. the PII masking policy + category allowlist.
  /// Returns an empty map on 404 (no settings row yet) so the caller can
  /// render defaults instead of erroring.
  Future<Map<String, dynamic>> getCompanySettings() async {
    try {
      final r = await _dio.get('/company-settings/me');
      return Map<String, dynamic>.from(r.data ?? const {});
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const {};
      rethrow;
    }
  }

  /// Update the company's PII masking policy and/or category allowlist.
  /// ``policy`` null leaves it unchanged; ``categories`` null leaves it
  /// unchanged, an empty list clears it (mask all types).
  Future<Map<String, dynamic>> updateCompanyPii({
    String? policy,
    List<String>? categories,
  }) async {
    final r = await _dio.patch('/company-settings/me', data: {
      if (policy != null) 'pii_masking_policy': policy,
      if (categories != null) 'pii_categories': categories,
    });
    return Map<String, dynamic>.from(r.data ?? const {});
  }

  // ── Phase G — Platform LLM keys (system_admin only) ────────────────────
  /// List rows in ``platform_llm_api_keys`` — one per provider used
  /// by ``scope='platform'`` agents. Each row's ``key_encrypted`` is
  /// intentionally never returned; the API only exposes metadata.
  Future<List<Map<String, dynamic>>> listPlatformKeys() async {
    final r = await _dio.get('/platform-llm-keys/');
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createPlatformKey({
    required String provider,
    required String apiKey,
  }) async {
    final r = await _dio.post(
      '/platform-llm-keys/',
      data: {'provider': provider, 'api_key': apiKey},
    );
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> deletePlatformKey(String id) =>
      _dio.delete('/platform-llm-keys/$id');

  // ── Phase G — Agent grants (cross-tenant sharing) ──────────────────────
  /// List grantees for a ``scope='shared'`` agent. Only the owning
  /// company_admin (or system_admin) gets a 200.
  Future<List<Map<String, dynamic>>> listAgentGrants(String agentId) async {
    final r = await _dio.get('/ai-agents/$agentId/grants');
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  /// Add (or upsert) a grant. ``pays`` is ``'owner'`` (default) or
  /// ``'grantee'`` — see the backend doc on ``GrantCreate``.
  Future<Map<String, dynamic>> upsertAgentGrant({
    required String agentId,
    required String granteeCompanyId,
    String pays = 'owner',
  }) async {
    final r = await _dio.post(
      '/ai-agents/$agentId/grants',
      data: {'grantee_company_id': granteeCompanyId, 'pays': pays},
    );
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> deleteAgentGrant({
    required String agentId,
    required String granteeCompanyId,
  }) =>
      _dio.delete('/ai-agents/$agentId/grants/$granteeCompanyId');

  // ── Phase M — Elasticsearch search over AI Admin (agents/skills/tools)
  /// Hits ``GET /ai-search/admin?q=...&type=...&limit=...`` and returns
  /// the raw rows from the ES index. The result envelope is
  /// ``{results: [...], count: int}``; we surface the inner list.
  ///
  /// Empty ``q`` (the in-memory filter's "show everything" state)
  /// short-circuits to an empty list — the caller already has the
  /// full row set from the per-tab list endpoints and should keep
  /// rendering it. When ES is unreachable the backend returns an
  /// empty list too; we map both to the same outcome so consumers
  /// can fall back to client-side filtering without a separate
  /// error branch.
  Future<List<Map<String, dynamic>>> searchAdmin(
    String q, {
    String? type,
    int limit = 25,
  }) async {
    if (q.trim().isEmpty) return const [];
    try {
      final r = await _dio.get('/ai-search/admin', queryParameters: {
        'q': q,
        if (type != null) 'type': type,
        'limit': limit,
      });
      final body = Map<String, dynamic>.from(r.data ?? const {});
      final results = (body['results'] as List?) ?? const [];
      return results.cast<Map<String, dynamic>>();
    } catch (_) {
      // ES down or 5xx → caller falls back to client-side filter.
      return const [];
    }
  }
}

final aiAdminApiProvider = Provider<AiAdminApi>(
  (ref) => AiAdminApi(ref.watch(aiAdminDioProvider)),
);
