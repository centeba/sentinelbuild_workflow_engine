// Phase 8 of documents/platform/web-builder-roadmap.md — real-time refresh hooks.
//
// Verifies that:
//   1. RealtimeSubscriptionManager resolves the subscribe template via
//      ExpressionResolver, opens an adapter subscription, and forwards
//      every message to the EventBus as `subscribe.<channel>`.
//   2. Re-binding the same element id replaces the previous subscription.
//   3. dispose() cancels everything.
//   4. The InMemory adapter is wired correctly so emit() reaches subscribers.
//   5. PageRendererWidget plumbs subscriptions for elements with
//      `dataBinding.subscribe` set, and tears them down on widget dispose.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_builder_renderer/web_builder_renderer.dart';

PageDefinition _pageWithSubscribe(String subscribeTemplate) => PageDefinition(
      id: 'p1',
      title: 'Demo',
      slug: 'demo',
      // No sections → no element rendering. The realtime manager iterates
      // `page.elements` regardless of section assignment, so we still get
      // subscription wiring without triggering GoogleFonts network fetches.
      sections: const [],
      elements: [
        PageElement(
          id: 'el1',
          type: PageElementType.divider,
          rowIndex: 0,
          dataBinding: DataBinding(
            url: '/jobs/{{element.id.config.id}}',
            subscribe: subscribeTemplate,
          ),
        ),
      ],
    );

void main() {
  group('InMemoryWebSocketAdapter', () {
    test('emit reaches subscribers on the same channel', () async {
      final adapter = InMemoryWebSocketAdapter();
      final hits = <dynamic>[];
      final sub = adapter.subscribe('execution.123').listen(hits.add);
      adapter.emit('execution.123', {'state': 'completed'});
      adapter.emit('other-channel', {'ignored': true});
      await Future<void>.delayed(Duration.zero);
      expect(hits, [
        {'state': 'completed'}
      ]);
      await sub.cancel();
      await adapter.close();
    });
  });

  group('RealtimeSubscriptionManager', () {
    test('resolves template, opens subscription, publishes to EventBus',
        () async {
      final adapter = InMemoryWebSocketAdapter();
      final bus = EventBus();
      final ctx = BindingContext(
        routeParams: {'jobId': 'abc'},
        eventBus: bus,
        webSocket: adapter,
      );
      final mgr = RealtimeSubscriptionManager(
        adapter: adapter,
        resolver: ExpressionResolver(ctx),
        eventBus: bus,
      );
      final published = <String>[];
      final busSub = bus.stream.listen(published.add);

      final cancel = await mgr.bind('el1', 'execution.{{route.jobId}}');
      expect(adapter.activeChannels, contains('execution.abc'));

      adapter.emit('execution.abc', {'state': 'running'});
      adapter.emit('execution.abc', {'state': 'completed'});
      await Future<void>.delayed(Duration.zero);

      expect(published, ['subscribe.execution.abc', 'subscribe.execution.abc']);
      expect(mgr.activeCount, 1);

      cancel();
      // After cancel, further emits don't publish.
      adapter.emit('execution.abc', {'state': 'extra'});
      await Future<void>.delayed(Duration.zero);
      expect(published.length, 2);
      expect(mgr.activeCount, 0);

      await busSub.cancel();
      await mgr.dispose();
    });

    test('re-binding the same elementId replaces the previous subscription',
        () async {
      final adapter = InMemoryWebSocketAdapter();
      final bus = EventBus();
      final ctx = BindingContext(eventBus: bus, webSocket: adapter);
      final mgr = RealtimeSubscriptionManager(
        adapter: adapter,
        resolver: ExpressionResolver(ctx),
        eventBus: bus,
      );
      final published = <String>[];
      final busSub = bus.stream.listen(published.add);

      await mgr.bind('el1', 'channel.A');
      await mgr.bind('el1', 'channel.B'); // re-bind same id
      expect(mgr.activeCount, 1);

      adapter.emit('channel.A', null);
      adapter.emit('channel.B', null);
      await Future<void>.delayed(Duration.zero);

      // Only channel.B should have fired (the re-bind cancels A's listener).
      expect(published, ['subscribe.channel.B']);

      await busSub.cancel();
      await mgr.dispose();
    });

    test('dispose() cancels all active subscriptions', () async {
      final adapter = InMemoryWebSocketAdapter();
      final bus = EventBus();
      final ctx = BindingContext(eventBus: bus, webSocket: adapter);
      final mgr = RealtimeSubscriptionManager(
        adapter: adapter,
        resolver: ExpressionResolver(ctx),
        eventBus: bus,
      );

      await mgr.bind('a', 'chan.a');
      await mgr.bind('b', 'chan.b');
      expect(mgr.activeCount, 2);

      await mgr.dispose();
      expect(mgr.activeCount, 0);
    });

    test('NoopWebSocketAdapter never publishes to the bus', () async {
      const adapter = NoopWebSocketAdapter();
      final bus = EventBus();
      final ctx = BindingContext(eventBus: bus, webSocket: adapter);
      final mgr = RealtimeSubscriptionManager(
        adapter: adapter,
        resolver: ExpressionResolver(ctx),
        eventBus: bus,
      );
      final published = <String>[];
      final busSub = bus.stream.listen(published.add);

      await mgr.bind('el1', 'whatever');
      await Future<void>.delayed(Duration.zero);
      expect(published, isEmpty);

      await busSub.cancel();
      await mgr.dispose();
    });
  });

  group('PageRendererWidget realtime integration', () {
    testWidgets(
        'binds subscriptions for elements with dataBinding.subscribe and '
        'cancels on dispose', (tester) async {
      // The post-frame callback that wires subscriptions is async, so we
      // run the test inside `tester.runAsync` to allow real Future
      // scheduling instead of fake-async pumping.
      await tester.runAsync(() async {
        final adapter = InMemoryWebSocketAdapter();
        final bus = EventBus();
        final published = <String>[];
        final busSub = bus.stream.listen(published.add);

        final bindingCtx = BindingContext(
          routeParams: {'jobId': 'job_42'},
          eventBus: bus,
          webSocket: adapter,
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: PageRendererWidget(
                  page: _pageWithSubscribe('execution.{{route.jobId}}'),
                  bindingContext: bindingCtx,
                ),
              ),
            ),
          ),
        );
        // Let the post-frame callback fire and the async bind() chain settle.
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(adapter.activeChannels, contains('execution.job_42'));

        adapter.emit('execution.job_42', {'foo': 1});
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(published, contains('subscribe.execution.job_42'));

        // Tear down the widget — subscriptions should be cancelled.
        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: SizedBox.shrink())),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final beforeCount = published.length;
        adapter.emit('execution.job_42', {'foo': 2});
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(published.length, beforeCount);

        await busSub.cancel();
      });
    });
  });
}
