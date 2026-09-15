import 'dart:async';

/// In-page pub/sub for the binding runtime.
///
/// Phase 4 of documents/platform/web-builder-roadmap.md introduces `refreshOn: [...]` on element
/// data bindings so e.g. a `Text` element can re-fetch its API value when
/// the user submits a form on the same page. The event bus is the cheap
/// channel that connects emitters (`form.submitted`, `field.changed.<id>`,
/// `websocket.execution.<id>`) to listeners (the data-bound elements).
///
/// Phase 8 layers WebSocket subscriptions on top — for now we only forward
/// in-process events, which is enough for forms and refresh-on-success.
class EventBus {
  final _controller = StreamController<String>.broadcast();

  /// Raw stream of all event names. Most consumers want [on] / [onAny].
  Stream<String> get stream => _controller.stream;

  /// Publishes [eventName] to all listeners. No-op when the bus is closed.
  void publish(String eventName) {
    if (_controller.isClosed) return;
    _controller.add(eventName);
  }

  /// Stream that fires whenever exactly [eventName] is published.
  Stream<void> on(String eventName) =>
      stream.where((e) => e == eventName).map((_) {});

  /// Stream that fires whenever any event in [eventNames] is published.
  /// Useful for an element with `refreshOn: ["form.submitted", "x.y"]`.
  Stream<void> onAny(Iterable<String> eventNames) {
    final set = eventNames.toSet();
    return stream.where(set.contains).map((_) {});
  }

  /// Closes the bus. After this, [publish] is a no-op and listeners receive
  /// the done event.
  Future<void> close() async {
    if (_controller.isClosed) return;
    await _controller.close();
  }

  bool get isClosed => _controller.isClosed;
}
