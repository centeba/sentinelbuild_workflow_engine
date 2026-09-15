import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Phase-E3 — opens a WebSocket to integration-hub's
/// ``/ws/ai-agents/{agent_id}/stream`` endpoint and yields incremental
/// text deltas (legacy text mode).
///
/// The smart-llm WS protocol expects an init message
/// ``{token, input, mode?}`` and emits one of two frame shapes:
///
/// - **mode="text"** (default, Phase E3): ``{delta: ...}`` chunks then
///   ``{done: true}``. Errors surface as ``{error: ...}`` and close.
/// - **mode="tools"** (Phase F2 streaming follow-up): a discriminated
///   union from ``smart_llm.agent_loop`` — ``{type: "text_delta", ...}``,
///   ``tool_use_start/_input_delta/_stop``, ``turn_complete``, and
///   ``error``. Final terminator is ``{type: "done"}``.
///
/// [AgentStream] keeps the legacy text-mode surface; the Phase F2
/// path is exposed via [AgentEventStream] below.
class AgentStream {
  final String agentId;
  final String input;
  AgentStream({required this.agentId, required this.input});

  static const _storage = FlutterSecureStorage();

  Stream<String> tokens() async* {
    // Storage key must match the chassis's AuthService — the chassis
// writes the JWT under `sb_access_token`. Using `access_token`
// silently sends an empty token over the WebSocket handshake.
final token = await _storage.read(key: 'sb_access_token') ?? '';
    final uri = _buildWsUri(agentId);
    final channel = WebSocketChannel.connect(uri);

    channel.sink.add(jsonEncode({'token': token, 'input': input}));
    try {
      await for (final raw in channel.stream) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        if (msg['error'] != null) {
          throw StateError(msg['error'].toString());
        }
        if (msg['done'] == true) {
          break;
        }
        final delta = msg['delta'];
        if (delta is String && delta.isNotEmpty) {
          yield delta;
        }
      }
    } finally {
      await channel.sink.close();
    }
  }
}

Uri _buildWsUri(String agentId) {
  const basePath = String.fromEnvironment(
    'AI_ADMIN_BASE_URL',
    defaultValue: '/api/integration-hub/v1',
  );
  final wsBase = kIsWeb
      ? (Uri.base.scheme == 'https' ? 'wss' : 'ws') +
          '://' +
          Uri.base.host +
          (Uri.base.port == 0 ? '' : ':${Uri.base.port}')
      : 'ws://localhost';
  return Uri.parse('$wsBase$basePath/ws/ai-agents/$agentId/stream');
}

/// Phase F2 streaming follow-up — discriminated event union surfaced
/// from the agent-loop streaming driver. Frontend consumers branch on
/// [type] to render text vs. tool-use cards mid-stream.
///
/// Mirror of the dict shape documented in ``smart_llm/agent_loop.py``
/// (``text_delta`` / ``tool_use_start`` / ``tool_use_input_delta`` /
/// ``tool_use_stop`` / ``turn_complete`` / ``error`` / ``done``).
sealed class AgentStreamEvent {
  const AgentStreamEvent();

  factory AgentStreamEvent.fromJson(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    switch (type) {
      case 'text_delta':
        return TextDeltaEvent(delta: (msg['delta'] as String?) ?? '');
      case 'tool_use_start':
        return ToolUseStartEvent(
          id: (msg['id'] as String?) ?? '',
          name: (msg['name'] as String?) ?? '',
        );
      case 'tool_use_input_delta':
        return ToolUseInputDeltaEvent(
          id: (msg['id'] as String?) ?? '',
          partialJson: (msg['partial_json'] as String?) ?? '',
        );
      case 'tool_use_stop':
        return ToolUseStopEvent(id: (msg['id'] as String?) ?? '');
      case 'turn_complete':
        return TurnCompleteEvent(
          stopReason: (msg['stop_reason'] as String?) ?? 'end_turn',
          usage: (msg['usage'] as Map<String, dynamic>?) ?? const {},
        );
      case 'error':
        return ErrorEvent(message: (msg['message'] as String?) ?? 'unknown');
      case 'done':
        return const DoneEvent();
      default:
        // Unknown — treat as a no-op pass-through so future event
        // types don't break old clients.
        return UnknownEvent(payload: msg);
    }
  }
}

class TextDeltaEvent extends AgentStreamEvent {
  final String delta;
  const TextDeltaEvent({required this.delta});
}

class ToolUseStartEvent extends AgentStreamEvent {
  final String id;
  final String name;
  const ToolUseStartEvent({required this.id, required this.name});
}

class ToolUseInputDeltaEvent extends AgentStreamEvent {
  final String id;
  final String partialJson;
  const ToolUseInputDeltaEvent({required this.id, required this.partialJson});
}

class ToolUseStopEvent extends AgentStreamEvent {
  final String id;
  const ToolUseStopEvent({required this.id});
}

class TurnCompleteEvent extends AgentStreamEvent {
  final String stopReason;
  final Map<String, dynamic> usage;
  const TurnCompleteEvent({required this.stopReason, required this.usage});
}

class ErrorEvent extends AgentStreamEvent {
  final String message;
  const ErrorEvent({required this.message});
}

class DoneEvent extends AgentStreamEvent {
  const DoneEvent();
}

class UnknownEvent extends AgentStreamEvent {
  final Map<String, dynamic> payload;
  const UnknownEvent({required this.payload});
}

/// Streaming-with-tools client. Opens the same WS endpoint as
/// [AgentStream] but sets ``mode: "tools"`` in the init message so the
/// backend routes through ``run_agent_loop_stream``.
class AgentEventStream {
  final String agentId;
  final String input;
  AgentEventStream({required this.agentId, required this.input});

  static const _storage = FlutterSecureStorage();

  Stream<AgentStreamEvent> events() async* {
    // Storage key must match the chassis's AuthService — the chassis
// writes the JWT under `sb_access_token`. Using `access_token`
// silently sends an empty token over the WebSocket handshake.
final token = await _storage.read(key: 'sb_access_token') ?? '';
    final uri = _buildWsUri(agentId);
    final channel = WebSocketChannel.connect(uri);

    channel.sink.add(jsonEncode({
      'token': token,
      'input': input,
      'mode': 'tools',
    }));
    try {
      await for (final raw in channel.stream) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        // The legacy ``{error: "..."}`` shape from connect/auth errors
        // is mapped to ErrorEvent so callers don't need a second branch.
        if (msg['error'] != null && msg['type'] == null) {
          yield ErrorEvent(message: msg['error'].toString());
          break;
        }
        final event = AgentStreamEvent.fromJson(msg);
        yield event;
        if (event is DoneEvent || event is ErrorEvent) {
          break;
        }
      }
    } finally {
      await channel.sink.close();
    }
  }
}

/// Riverpod factory for ad-hoc stream consumption from the run-history
/// viewer (legacy text mode). Pass ``(agentId, input)`` as the family
/// argument.
final agentStreamProvider =
    StreamProvider.family<String, ({String agentId, String input})>(
  (ref, args) async* {
    final stream = AgentStream(agentId: args.agentId, input: args.input);
    final buffer = StringBuffer();
    await for (final delta in stream.tokens()) {
      buffer.write(delta);
      yield buffer.toString();
    }
  },
);

/// Phase F2 streaming follow-up — Riverpod factory for the discriminated
/// event union. Consumers branch on event types to render tool cards
/// alongside text. Each emission is the full event list to date so the
/// UI can drive off ``ref.watch`` without per-event StateNotifier work.
final agentEventStreamProvider = StreamProvider.family<
    List<AgentStreamEvent>, ({String agentId, String input})>(
  (ref, args) async* {
    final stream = AgentEventStream(agentId: args.agentId, input: args.input);
    final accumulated = <AgentStreamEvent>[];
    await for (final event in stream.events()) {
      accumulated.add(event);
      yield List.unmodifiable(accumulated);
    }
  },
);
