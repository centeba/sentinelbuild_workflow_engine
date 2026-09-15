/// Phase 8 of documents/platform/web-builder-roadmap.md — real-time refresh hooks.
///
/// Gated on PLATFORM_GAPS_PLAN Phase 5.1 (the platform-wide WebSocket bus)
/// for the actual transport — that work is owned by user-master / a new
/// `events-api` service. This file defines the **renderer-side contract**
/// host apps implement; vertical apps that don't have a WS bus yet get the
/// default [NoopWebSocketAdapter] which silently no-ops.
///
/// Wiring story:
///
/// 1. Host app constructs a [WebSocketAdapter] (or accepts the no-op).
/// 2. The adapter is injected through `BindingContext.webSocket`.
/// 3. When an element with `dataBinding.subscribe = "execution.{{...}}"` is
///    mounted, [RealtimeSubscriptionManager.bind] resolves the channel via
///    [ExpressionResolver], opens the subscription, and forwards every
///    incoming message to the [EventBus] as event name
///    `subscribe.<resolvedChannel>`.
/// 4. The element's `dataBinding.refreshOn` already includes that event
///    name (or it can be added at authoring time), so the existing
///    refresh-on-event plumbing re-fetches the underlying data.
///
/// This split keeps Phase 4's EventBus plumbing as the single source of
/// truth for "something changed, re-render the bound elements" — the WS
/// bus is just one more producer.

library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_bus.dart';
import 'expression_resolver.dart';

/// Host-overridable Riverpod provider for the active [WebSocketAdapter].
///
/// Renderer-level elements (e.g. ``WorkflowStatus``) read this provider
/// to open subscriptions without having to thread the adapter through
/// every BindingContext call site. The chassis overrides it in its
/// ``ProviderScope.overrides`` to install a real
/// :class:`BusWebSocketAdapter`; standalone designers leave it at the
/// default :class:`NoopWebSocketAdapter`.
final webSocketAdapterProvider = Provider<WebSocketAdapter>(
  (ref) => const NoopWebSocketAdapter(),
);

/// Host-app-supplied transport. Implementations decide how to talk to the
/// platform's event bus (websocket, server-sent events, in-process for
/// tests, etc).
abstract class WebSocketAdapter {
  /// Open a subscription on [channel] and yield every incoming message
  /// (any JSON-decoded shape). The stream MUST emit when the underlying
  /// connection is lost so the manager can re-subscribe; alternatively,
  /// implementations can transparently re-connect and never close the stream.
  Stream<dynamic> subscribe(String channel);

  /// Tear down everything (called when the [PageRendererWidget] is disposed).
  Future<void> close();
}

/// Default adapter — does nothing. Used when the host app isn't yet wired
/// to a WebSocket bus. Pages with `dataBinding.subscribe` set still render
/// correctly; they just don't receive real-time updates.
class NoopWebSocketAdapter implements WebSocketAdapter {
  const NoopWebSocketAdapter();

  @override
  Stream<dynamic> subscribe(String channel) =>
      const Stream<dynamic>.empty();

  @override
  Future<void> close() async {}
}

/// In-memory adapter for tests. Producers call [emit] to inject messages
/// onto a named channel; subscribers receive them in order.
class InMemoryWebSocketAdapter implements WebSocketAdapter {
  final _controllers = <String, StreamController<dynamic>>{};

  @override
  Stream<dynamic> subscribe(String channel) {
    final c = _controllers.putIfAbsent(
        channel, () => StreamController<dynamic>.broadcast());
    return c.stream;
  }

  /// Push [message] to everyone subscribed to [channel].
  void emit(String channel, dynamic message) {
    final c = _controllers[channel];
    if (c == null || c.isClosed) return;
    c.add(message);
  }

  /// Active channel names — useful for tests asserting that a given element
  /// actually subscribed.
  Iterable<String> get activeChannels => _controllers.keys;

  @override
  Future<void> close() async {
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }
}

/// Manager that converts `dataBinding.subscribe` declarations into live
/// EventBus traffic. One instance per `PageRendererWidget` lifecycle.
///
/// Usage from inside the renderer:
///
/// ```dart
/// final mgr = RealtimeSubscriptionManager(
///   adapter: bindingContext.webSocket,
///   resolver: resolver,
///   eventBus: bindingContext.eventBus,
/// );
///
/// // For each element with subscribe set:
/// final cancel = await mgr.bind(elementId, subscribeTemplate);
/// // ... on element dispose: cancel();
/// ```
class RealtimeSubscriptionManager {
  final WebSocketAdapter adapter;
  final ExpressionResolver resolver;
  final EventBus eventBus;
  final _activeSubs = <String, StreamSubscription<dynamic>>{};

  RealtimeSubscriptionManager({
    required this.adapter,
    required this.resolver,
    required this.eventBus,
  });

  /// Resolve [subscribeTemplate] (e.g. `"execution.{{element.id.config.id}}"`),
  /// open the subscription, and forward each message to [eventBus] as
  /// `subscribe.<resolvedChannel>`. Returns a cancel callback that closes
  /// the underlying StreamSubscription — call it on element dispose.
  ///
  /// Re-binding the same [elementId] cancels the previous subscription
  /// first; this is what the renderer does when an element's resolved
  /// channel changes (e.g. its bound id swapped).
  Future<void Function()> bind(
    String elementId,
    String subscribeTemplate,
  ) async {
    await _cancel(elementId);
    final channel = await resolver.resolve(subscribeTemplate);

    final eventName = 'subscribe.$channel';
    final sub = adapter.subscribe(channel).listen((_) {
      // We don't surface the message body here — Phase 4's refresh-on-event
      // contract is "the named source changed, re-fetch yourself". Element
      // bindings declare `refreshOn: ["subscribe.<channel>"]` and fetch
      // again through their HttpDataSource.
      eventBus.publish(eventName);
    });
    _activeSubs[elementId] = sub;

    return () => _cancel(elementId);
  }

  Future<void> _cancel(String elementId) async {
    final sub = _activeSubs.remove(elementId);
    if (sub != null) await sub.cancel();
  }

  /// Tear down everything. Called by [PageRendererWidget.dispose].
  Future<void> dispose() async {
    for (final sub in _activeSubs.values) {
      await sub.cancel();
    }
    _activeSubs.clear();
    await adapter.close();
  }

  /// Number of currently-active subscriptions. Useful for tests.
  int get activeCount => _activeSubs.length;
}
