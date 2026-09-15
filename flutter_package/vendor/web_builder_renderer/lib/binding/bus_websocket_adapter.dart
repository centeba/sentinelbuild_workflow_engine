/// Phase 8 / Phase 5.1 — concrete [WebSocketAdapter] for the platform
/// subscription bus on integration-hub.
///
/// Wire protocol matches the FastAPI endpoint at
/// ``/api/v1/subscribe/{topic}`` in
/// ``services/integration-hub/.../routes/subscription_bus.py``:
///
/// 1. Open ``WS <base>/api/integration-hub/v1/subscribe/<channel>``.
/// 2. Send first JSON message ``{"token": "<jwt>"}``.
/// 3. Receive the server's ``{"event":"subscribed","topic":"..."}`` ack,
///    then forward every subsequent text frame as a decoded JSON value
///    to the stream.
/// 4. On any drop, reconnect with capped exponential backoff (1s → 2 →
///    4 → 8 → 16 → 30 cap) and emit a synthetic
///    ``{"reconnected": true}`` event so the renderer's
///    [RealtimeSubscriptionManager] re-publishes its bus event and any
///    bound element re-fetches.
///
/// The host owns lifecycle: construct once, register in
/// ``BindingContext.webSocket`` via Riverpod overrides, and the
/// renderer calls [close] on widget dispose.

library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'realtime.dart';

/// Provides the bearer JWT to attach to every WS handshake. Called
/// every connect attempt so the adapter picks up token rotation
/// transparently. Return `null` to skip the auth message — the server
/// will close the connection.
///
/// Async so chassis-style implementations can pull the token from
/// `flutter_secure_storage` (or another async store) without
/// pre-caching.
typedef BusTokenProvider = Future<String?> Function();

/// Lifecycle states emitted on [BusWebSocketAdapter.connectionState].
///
/// UI layers (e.g. a "reconnecting…" banner in a renderer element)
/// subscribe to this stream alongside the data stream so the user
/// sees stale data with an indicator rather than stale data alone.
enum BusConnectionState {
  /// Adapter created but no connect attempt has been made yet.
  idle,

  /// Connect attempt in progress (URL built, socket opening, token sent).
  connecting,

  /// Token accepted; receiving frames.
  connected,

  /// Last connect attempt failed, or the socket dropped. The adapter
  /// will retry automatically (see [BusWebSocketAdapter] backoff).
  disconnected,
}

/// Concrete [WebSocketAdapter] that talks to the platform's
/// subscription bus. One socket per channel; multiple subscribers to
/// the same channel share a broadcast stream.
class BusWebSocketAdapter implements WebSocketAdapter {
  /// Host (with scheme) the WS URL is built from. Empty string means
  /// same-origin — the adapter rewrites `http(s)://` to `ws(s)://` on
  /// build. For the chassis pass `''` (or `Uri.base.origin`).
  final String baseUrl;
  final BusTokenProvider tokenProvider;

  /// Per-channel state. One entry per active channel.
  final _channels = <String, _ChannelState>{};

  /// Used by tests to swap the real `WebSocketChannel.connect` for a
  /// fake. Production code leaves this null.
  final Future<WebSocketChannel> Function(Uri url)? connector;

  BusWebSocketAdapter({
    required this.tokenProvider,
    this.baseUrl = '',
    this.connector,
  });

  @override
  Stream<dynamic> subscribe(String channel) {
    final state = _ensureChannel(channel);
    return state.controller.stream;
  }

  /// Lifecycle stream for [channel]. Emits the current state on
  /// listen and every transition thereafter. Calling this *before*
  /// [subscribe] is fine — the channel state is created lazily and the
  /// data stream will start flowing on the first subscribe.
  Stream<BusConnectionState> connectionState(String channel) {
    final state = _ensureChannel(channel);
    // Late subscribers should see the current state immediately
    // (not just future transitions). Use a controller with onListen.
    final controller = StreamController<BusConnectionState>();
    controller.add(state.connectionState);
    final sub = state.connectionStateController.stream.listen(controller.add);
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  _ChannelState _ensureChannel(String channel) {
    final existing = _channels[channel];
    if (existing != null && !existing.controller.isClosed) {
      return existing;
    }
    final state = _ChannelState(channel);
    _channels[channel] = state;
    // Kick off connect attempts in the background; subscribers wait
    // on the broadcast stream and receive messages as they arrive.
    unawaited(_run(state));
    return state;
  }

  @override
  Future<void> close() async {
    final states = _channels.values.toList();
    _channels.clear();
    for (final s in states) {
      s.shouldRun = false;
      await s.socket?.sink.close();
      if (!s.controller.isClosed) await s.controller.close();
      if (!s.connectionStateController.isClosed) {
        await s.connectionStateController.close();
      }
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  /// Build the WS URL for [channel]. Same-origin (`baseUrl == ''`)
  /// rewrites `http(s)://` to `ws(s)://`; absolute baseUrls are passed
  /// through after the same rewrite.
  Uri _buildUrl(String channel) {
    final base = baseUrl.isEmpty ? Uri.base.toString() : baseUrl;
    var u = Uri.parse(base);
    if (u.scheme == 'http') {
      u = u.replace(scheme: 'ws');
    } else if (u.scheme == 'https') {
      u = u.replace(scheme: 'wss');
    }
    // The channel may contain dots (`org.X.execution.Y`); we still
    // URL-encode it defensively in case future topics include
    // reserved characters.
    return u.replace(
      path: '/api/integration-hub/v1/subscribe/${Uri.encodeComponent(channel)}',
      query: null,
    );
  }

  static const _backoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  Future<void> _run(_ChannelState state) async {
    var attempt = 0;
    while (state.shouldRun) {
      _setState(state, BusConnectionState.connecting);
      try {
        final url = _buildUrl(state.channel);
        final ws = connector != null
            ? await connector!(url)
            : WebSocketChannel.connect(url);
        state.socket = ws;

        // Send token as first message.
        final token = await tokenProvider();
        ws.sink.add(jsonEncode({if (token != null) 'token': token}));

        _setState(state, BusConnectionState.connected);
        if (attempt > 0) {
          // Emit a synthetic event so subscribers know to re-fetch.
          _emit(state, {'reconnected': true});
        }
        attempt = 0;

        await for (final raw in ws.stream) {
          if (!state.shouldRun) break;
          final str = raw is String ? raw : raw?.toString() ?? '';
          dynamic decoded;
          try {
            decoded = jsonDecode(str);
          } catch (_) {
            // Server can also send plain text (mit-stack publishes JSON
            // strings; downstream services may send arbitrary text).
            decoded = str;
          }
          _emit(state, decoded);
        }
      } catch (e, st) {
        // Connection failure — log then fall through to backoff so an
        // outright protocol failure (handshake reject, malformed frame)
        // doesn't disappear silently. Backoff is unchanged.
        // ignore: avoid_print
        print('[BusWebSocketAdapter] channel="${state.channel}" '
            'attempt=$attempt error=$e\n$st');
      }
      state.socket = null;
      _setState(state, BusConnectionState.disconnected);
      if (!state.shouldRun) break;
      final delay = _backoff[attempt.clamp(0, _backoff.length - 1)];
      attempt += 1;
      await Future<void>.delayed(delay);
    }
  }

  void _setState(_ChannelState state, BusConnectionState next) {
    if (state.connectionState == next) return;
    state.connectionState = next;
    if (!state.connectionStateController.isClosed) {
      state.connectionStateController.add(next);
    }
  }

  void _emit(_ChannelState state, dynamic msg) {
    if (state.controller.isClosed) return;
    state.controller.add(msg);
  }
}

class _ChannelState {
  final String channel;
  final StreamController<dynamic> controller =
      StreamController<dynamic>.broadcast();
  final StreamController<BusConnectionState> connectionStateController =
      StreamController<BusConnectionState>.broadcast();
  BusConnectionState connectionState = BusConnectionState.idle;
  WebSocketChannel? socket;
  bool shouldRun = true;

  _ChannelState(this.channel);
}
