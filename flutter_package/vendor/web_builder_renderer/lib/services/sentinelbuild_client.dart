import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sentinelbuild_settings.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class SbEnvelope {
  final String id;
  final String status; // draft|sent|delivered|completed|voided
  final String subject;
  final List<String> recipientEmails;
  final DateTime? createdAt;

  const SbEnvelope({
    required this.id,
    required this.status,
    required this.subject,
    required this.recipientEmails,
    this.createdAt,
  });

  factory SbEnvelope.fromJson(Map<String, dynamic> j) => SbEnvelope(
        id: j['id'] as String? ?? '',
        status: j['status'] as String? ?? 'draft',
        subject: j['subject'] as String? ?? '',
        recipientEmails: (j['recipients'] as List<dynamic>? ?? [])
            .map((r) => (r as Map<String, dynamic>)['email'] as String? ?? '')
            .toList(),
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
      );
}

class SbWorkflowRun {
  final String id;
  final String status; // pending|running|completed|failed
  final String workflowId;
  final Map<String, dynamic> output;

  const SbWorkflowRun({
    required this.id,
    required this.status,
    required this.workflowId,
    required this.output,
  });

  factory SbWorkflowRun.fromJson(Map<String, dynamic> j) => SbWorkflowRun(
        id: j['id'] as String? ?? '',
        status: j['status'] as String? ?? 'pending',
        workflowId: j['workflow_id'] as String? ?? '',
        output: j['output'] as Map<String, dynamic>? ?? {},
      );
}

class SbVaultNode {
  final String id;
  final String name;
  final bool isFolder;
  final String? parentId;
  final int? size;

  const SbVaultNode({
    required this.id,
    required this.name,
    required this.isFolder,
    this.parentId,
    this.size,
  });

  factory SbVaultNode.fromJson(Map<String, dynamic> j) => SbVaultNode(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        isFolder: j['type'] == 'folder',
        parentId: j['parent_id'] as String?,
        size: j['size'] as int?,
      );
}

class SbAgentResult {
  final String runId;
  final String output;
  final bool success;

  const SbAgentResult(
      {required this.runId, required this.output, required this.success});

  factory SbAgentResult.fromJson(Map<String, dynamic> j) => SbAgentResult(
        runId: j['run_id'] as String? ?? '',
        output: j['output'] as String? ?? '',
        success: j['success'] as bool? ?? false,
      );
}

// ── Client ────────────────────────────────────────────────────────────────────

class SentinelBuildClient {
  final String _mitStackBase;
  final String _vaultBase;
  String? _token;

  late final Dio _mitDio;
  late final Dio _vaultDio;

  SentinelBuildClient({
    required String mitStackBase,
    required String vaultBase,
    String? token,
  })  : _mitStackBase = mitStackBase,
        _vaultBase = vaultBase,
        _token = token {
    _mitDio = Dio(BaseOptions(
      baseUrl: _mitStackBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _vaultDio = Dio(BaseOptions(
      baseUrl: _vaultBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _applyAuthInterceptors();
  }

  void updateToken(String? token) {
    _token = token;
    _applyAuthInterceptors();
  }

  void _applyAuthInterceptors() {
    for (final dio in [_mitDio, _vaultDio]) {
      dio.interceptors.clear();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          handler.next(options);
        },
      ));
    }
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  /// Login and return a JWT token. Throws on failure.
  Future<String> login(String email, String password) async {
    final resp = await _mitDio.post(
      '/api/auth/login',
      data: {'email': email, 'password': password},
    );
    final token = resp.data['token'] as String? ??
        resp.data['access_token'] as String? ??
        '';
    _token = token;
    _applyAuthInterceptors();
    return token;
  }

  /// Test current credentials. Returns true if a simple authenticated request
  /// succeeds.
  Future<bool> testConnection() async {
    try {
      await _mitDio.get('/api/users/me');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Doc Vault ─────────────────────────────────────────────────────────────

  Future<List<SbVaultNode>> listNodes(String? parentId) async {
    final params = parentId != null ? {'parent_id': parentId} : null;
    final resp = await _vaultDio.get('/api/vault/nodes', queryParameters: params);
    final list = resp.data as List<dynamic>;
    return list.map((e) => SbVaultNode.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SbVaultNode> uploadDocument(
      String parentId, Uint8List bytes, String filename) async {
    final formData = FormData.fromMap({
      'parent_id': parentId,
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final resp = await _vaultDio.post('/api/vault/upload', data: formData);
    return SbVaultNode.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Uint8List> downloadDocument(String nodeId) async {
    final resp = await _vaultDio.get(
      '/api/vault/nodes/$nodeId/download',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(resp.data as List<int>);
  }

  // ── E-Signature ───────────────────────────────────────────────────────────

  Future<SbEnvelope> createEnvelope({
    required String templateId,
    required List<Map<String, String>> recipients,
  }) async {
    final resp = await _mitDio.post('/api/esig/envelopes', data: {
      'template_id': templateId,
      'recipients': recipients,
    });
    return SbEnvelope.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<SbEnvelope> getEnvelope(String envelopeId) async {
    final resp = await _mitDio.get('/api/esig/envelopes/$envelopeId');
    return SbEnvelope.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> voidEnvelope(String envelopeId, String reason) async {
    await _mitDio.post('/api/esig/envelopes/$envelopeId/void',
        data: {'reason': reason});
  }

  /// Submit a form as an envelope. Maps form values to envelope fields and
  /// attaches the SVG signature if provided.
  Future<SbEnvelope> submitFormAsEnvelope({
    required String templateId,
    required Map<String, dynamic> formValues,
    required String signerEmail,
    required String signerName,
    String? signatureSvg,
  }) async {
    final payload = {
      'template_id': templateId,
      'recipients': [
        {'email': signerEmail, 'name': signerName},
      ],
      'field_values': formValues,
      if (signatureSvg != null) 'signature_svg': signatureSvg,
    };
    final resp = await _mitDio.post('/api/esig/envelopes/from-form', data: payload);
    return SbEnvelope.fromJson(resp.data as Map<String, dynamic>);
  }

  // ── Workflows ─────────────────────────────────────────────────────────────

  Future<SbWorkflowRun> triggerWorkflow(
      String workflowId, Map<String, dynamic> payload) async {
    final resp = await _mitDio.post(
      '/api/workflow/workflows/$workflowId/trigger',
      data: payload,
    );
    return SbWorkflowRun.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<SbWorkflowRun> getWorkflowRun(String runId) async {
    final resp = await _mitDio.get('/api/workflow/runs/$runId');
    return SbWorkflowRun.fromJson(resp.data as Map<String, dynamic>);
  }

  // ── AI Agents ─────────────────────────────────────────────────────────────

  Future<SbAgentResult> invokeAgent(
      String agentId, Map<String, dynamic> input) async {
    final resp = await _mitDio.post(
      '/api/agent/$agentId/invoke',
      data: input,
    );
    return SbAgentResult.fromJson(resp.data as Map<String, dynamic>);
  }
}

// ── Riverpod provider ─────────────────────────────────────────────────────────

final sentinelBuildClientProvider = Provider<SentinelBuildClient>((ref) {
  final settings = ref.watch(sentinelBuildSettingsProvider);
  return SentinelBuildClient(
    mitStackBase: settings.mitStackBase,
    vaultBase: settings.vaultBase,
    token: settings.jwtToken,
  );
});
