// Multi-model chat — API client + models (package-portable).
//
// Unlike the chassis copy this takes its Dio instances by constructor (no host
// providers) so any embedding app can supply its own authenticated, proxy-aware
// clients. Talks to user-master's /ai-chat routes; the send endpoint returns
// Server-Sent Events which `sendMessage` decodes into text/error deltas.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

class ChatThread {
  final String id;
  final String? title;
  final int conversationSize;

  const ChatThread({required this.id, this.title, this.conversationSize = 0});

  factory ChatThread.fromJson(Map<String, dynamic> j) => ChatThread(
        id: j['id'] as String,
        title: j['title'] as String?,
        conversationSize: (j['conversation_size'] as int?) ?? 0,
      );

  String get displayTitle =>
      (title != null && title!.trim().isNotEmpty) ? title! : 'New chat';
}

class ChatMessage {
  final String id;
  final String role; // "user" | "assistant"
  final String? modelUsed;
  final String text;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.modelUsed,
  });

  bool get isUser => role == 'user';

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final parts = (j['parts'] as List<dynamic>? ?? const []);
    final text = parts
        .whereType<Map<String, dynamic>>()
        .where((p) => p['part_type'] == 'text')
        .map((p) => (p['text_content'] as String?) ?? '')
        .join('');
    return ChatMessage(
      id: j['id'] as String,
      role: j['role'] as String? ?? 'assistant',
      modelUsed: j['model_used'] as String?,
      text: text,
    );
  }
}

class ModelChoice {
  final String provider;
  final String model;
  final String label;
  final bool hasKey;
  final bool supportsVision;

  const ModelChoice({
    required this.provider,
    required this.model,
    required this.label,
    required this.hasKey,
    required this.supportsVision,
  });

  String get id => '$provider:$model';
}

class ChatDelta {
  final String? text;
  final String? error;
  const ChatDelta._({this.text, this.error});
  factory ChatDelta.text(String t) => ChatDelta._(text: t);
  factory ChatDelta.error(String e) => ChatDelta._(error: e);
  bool get isError => error != null;
}

/// One file the host picked, to be uploaded as a chat attachment.
class PickedFile {
  final List<int> bytes;
  final String filename;
  final String? mimeType;
  const PickedFile({required this.bytes, required this.filename, this.mimeType});
}

class ChatApi {
  ChatApi({required Dio userMasterDio, required Dio docVaultDio})
      : _dio = userMasterDio,
        _docVaultDio = docVaultDio;
  final Dio _dio;
  final Dio _docVaultDio;

  static const _base = '/api/v1/ai-chat';

  Future<String> ensureDefaultAgent() async {
    final r = await _dio.post('$_base/default-agent');
    return (r.data as Map<String, dynamic>)['id'] as String;
  }

  Future<List<ChatThread>> listThreads() async {
    final r = await _dio.get('$_base/threads/');
    final data = (r.data as Map<String, dynamic>)['data'] as List<dynamic>;
    return data.whereType<Map<String, dynamic>>().map(ChatThread.fromJson).toList();
  }

  Future<ChatThread> createThread(String agentConfigId, {String? title}) async {
    final r = await _dio.post('$_base/threads/', data: {
      'agent_config_id': agentConfigId,
      if (title != null) 'title': title,
    });
    return ChatThread.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deleteThread(String threadId) =>
      _dio.delete('$_base/threads/$threadId');

  Future<List<ChatMessage>> listMessages(String threadId) async {
    final r = await _dio.get('$_base/threads/$threadId/messages');
    final data = (r.data as Map<String, dynamic>)['data'] as List<dynamic>;
    return data.whereType<Map<String, dynamic>>().map(ChatMessage.fromJson).toList();
  }

  Future<List<ModelChoice>> listModels() async {
    final r = await _dio.get('$_base/models');
    final providers = (r.data as Map<String, dynamic>)['providers'] as List<dynamic>;
    final out = <ModelChoice>[];
    for (final p in providers.whereType<Map<String, dynamic>>()) {
      final hasKey = (p['has_key'] as bool?) ?? false;
      for (final m in (p['models'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()) {
        final caps = (m['capabilities'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();
        out.add(ModelChoice(
          provider: p['provider'] as String,
          model: m['model'] as String,
          label: (m['label'] as String?) ?? m['model'] as String,
          hasKey: hasKey,
          supportsVision: caps.contains('vision'),
        ));
      }
    }
    return out;
  }

  Future<Map<String, dynamic>> uploadDocument(PickedFile file) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(file.bytes, filename: file.filename),
      'target_path': 'root',
    });
    final r = await _docVaultDio.post('/api/v1/documents/upload', data: form);
    final m = r.data as Map<String, dynamic>;
    return {
      'node_id': m['node_id'] as String,
      'kind': 'document',
      'filename': file.filename,
      if (file.mimeType != null) 'mime_type': file.mimeType,
    };
  }

  /// Stream an assistant reply as text/error deltas; completes on `done`.
  Stream<ChatDelta> sendMessage({
    required String threadId,
    required String content,
    String? provider,
    String? model,
    List<Map<String, dynamic>> attachments = const [],
  }) async* {
    final resp = await _dio.post(
      '$_base/threads/$threadId/send',
      data: {
        'content': content,
        if (provider != null) 'provider_type': provider,
        if (model != null) 'model_name': model,
        if (attachments.isNotEmpty) 'attachments': attachments,
      },
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
      ),
    );
    final body = resp.data as ResponseBody;
    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(line.substring(6)) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      switch (payload['type']) {
        case 'text':
          yield ChatDelta.text((payload['content'] as String?) ?? '');
        case 'error':
          yield ChatDelta.error((payload['content'] as String?) ?? 'error');
        case 'done':
          return;
      }
    }
  }
}
