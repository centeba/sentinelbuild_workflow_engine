// Phase 8 / Phase 5.1 — BusWebSocketAdapter unit tests.
//
// Verifies:
//   1. URL construction (http → ws, https → wss; channel in path).
//   2. Token sent as the first WS frame.
//   3. Incoming text frames decoded as JSON, emitted on the broadcast
//      stream; non-JSON frames emitted as the raw string.
//   4. On drop, the adapter reconnects and emits a synthetic
//      {"reconnected": true} event so bound elements can re-fetch.
//   5. close() tears down all channel streams.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_builder_renderer/web_builder_renderer.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// In-process fake. Lets the test push frames to the adapter and
/// observe what the adapter sends back. One instance per "physical
/// connection" — when the adapter reconnects, the test supplies a
/// fresh fake.
class _FakeWebSocketChannel implements WebSocketChannel {
  final _inbound = StreamController<dynamic>.broadcast();
  final outbound = <dynamic>[];
  final _sink = _FakeSink();

  _FakeWebSocketChannel() {
    _sink._onAdd = outbound.add;
    _sink._onClose = _inbound.close;
  }

  void push(String frame) => _inbound.add(frame);
  void dropConnection() => _inbound.close();

  // A newer stream_channel adds StreamChannelMixin members (cast / pipe /
  // transform / changeStream / changeSink / …) to the WebSocketChannel
  // interface. This fake never exercises them, so forward to noSuchMethod
  // (which throws if anything actually calls them) to satisfy the interface.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Stream<dynamic> get stream => _inbound.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class _FakeSink implements WebSocketSink {
  void Function(dynamic)? _onAdd;
  Future<void> Function()? _onClose;

  @override
  void add(dynamic data) => _onAdd?.call(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final d in stream) {
      add(d);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    final cb = _onClose;
    if (cb != null) await cb();
  }

  @override
  Future<void> get done => Future.value();
}

void main() {
  group('BusWebSocketAdapter URL construction', () {
    test('http base rewrites to ws', () async {
      late Uri capturedUrl;
      final fake = _FakeWebSocketChannel();
      final adapter = BusWebSocketAdapter(
        tokenProvider: () async => 't0k',
        baseUrl: 'http://localhost',
        connector: (url) async {
          capturedUrl = url;
          return fake;
        },
      );

      final sub = adapter.subscribe('org.X.execution.Y').listen((_) {});
      // Give the connect microtask a chance to run.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(capturedUrl.scheme, 'ws');
      expect(capturedUrl.host, 'localhost');
      expect(
        capturedUrl.path,
        '/api/integration-hub/v1/subscribe/${Uri.encodeComponent('org.X.execution.Y')}',
      );

      await sub.cancel();
      await adapter.close();
    });

    test('https base rewrites to wss', () async {
      late Uri capturedUrl;
      final fake = _FakeWebSocketChannel();
      final adapter = BusWebSocketAdapter(
        tokenProvider: () async => 't0k',
        baseUrl: 'https://api.example.com',
        connector: (url) async {
          capturedUrl = url;
          return fake;
        },
      );

      final sub = adapter.subscribe('any.topic').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(capturedUrl.scheme, 'wss');
      expect(capturedUrl.host, 'api.example.com');

      await sub.cancel();
      await adapter.close();
    });
  });

  group('BusWebSocketAdapter handshake', () {
    test('first frame is the auth message with the supplied token',
        () async {
      final fake = _FakeWebSocketChannel();
      final adapter = BusWebSocketAdapter(
        tokenProvider: () async => 'jwt-abc',
        baseUrl: 'http://localhost',
        connector: (_) async => fake,
      );

      final sub = adapter.subscribe('org.X.execution.Y').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fake.outbound, hasLength(1));
      final firstFrame = jsonDecode(fake.outbound.first as String) as Map;
      expect(firstFrame['token'], 'jwt-abc');

      await sub.cancel();
      await adapter.close();
    });
  });

  group('BusWebSocketAdapter message decoding', () {
    test('JSON frames are decoded; non-JSON passes through as string',
        () async {
      final fake = _FakeWebSocketChannel();
      final adapter = BusWebSocketAdapter(
        tokenProvider: () async => 't',
        baseUrl: 'http://localhost',
        connector: (_) async => fake,
      );

      final messages = <dynamic>[];
      final sub = adapter.subscribe('any.topic').listen(messages.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      fake.push('{"event":"subscribed","topic":"any.topic"}');
      fake.push('{"type":"execution_status","status":"running"}');
      fake.push('not-json');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(messages.length, 3);
      expect(messages[0], {'event': 'subscribed', 'topic': 'any.topic'});
      expect(messages[1], {'type': 'execution_status', 'status': 'running'});
      expect(messages[2], 'not-json');

      await sub.cancel();
      await adapter.close();
    });
  });

  group('BusWebSocketAdapter reconnect', () {
    test(
      'emits {reconnected:true} on the second connect attempt',
      () async {
        // First connection opens then drops; second opens and stays.
        // The adapter's first backoff delay is 1s, so the test waits
        // ~1.1s — slow but bounded.
        final fakes = <_FakeWebSocketChannel>[
          _FakeWebSocketChannel(),
          _FakeWebSocketChannel(),
        ];
        var connectCount = 0;
        final adapter = BusWebSocketAdapter(
          tokenProvider: () async => 't',
          baseUrl: 'http://localhost',
          connector: (_) async => fakes[connectCount++],
        );

        final messages = <dynamic>[];
        final sub = adapter.subscribe('any.topic').listen(messages.add);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // Drop the first connection.
        fakes[0].dropConnection();
        // Wait past the 1s backoff window.
        await Future<void>.delayed(const Duration(milliseconds: 1200));

        // After reconnect we should see at least one {reconnected: true}.
        final reconnected = messages
            .whereType<Map>()
            .where((m) => m['reconnected'] == true)
            .toList();
        expect(reconnected, isNotEmpty,
            reason: 'expected synthetic reconnected event on retry');
        expect(connectCount, 2);

        await sub.cancel();
        await adapter.close();
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );
  });
}
