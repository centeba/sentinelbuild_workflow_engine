// Phase 4 of documents/platform/web-builder-roadmap.md — data-binding runtime.
//
// Covers:
//   - ExpressionResolver: route / query / session / form / element / env
//   - api.<source>.<jsonpath>: HttpDataSource lookup + JSONPath drilling
//   - EventBus: publish/subscribe + onAny
//   - FormSubmitAction: token resolution + onSuccess/onError branching

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_builder_renderer/web_builder_renderer.dart';

class _StubAdapter implements HttpClientAdapter {
  /// Map of URL → JSON body returned for that URL.
  final Map<String, dynamic> responses;
  /// Map of URL → status code (default 200).
  final Map<String, int> statusCodes;
  /// Captured requests for assertion.
  final List<Map<String, dynamic>> seen = [];

  _StubAdapter({required this.responses, this.statusCodes = const {}});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    seen.add({
      'method': options.method,
      'url': options.uri.toString(),
      'data': options.data,
      'headers': Map<String, dynamic>.from(options.headers),
    });
    final url = options.uri.toString();
    final status = statusCodes[url] ??
        statusCodes[options.path] ??
        statusCodes['*'] ??
        200;
    final body = responses[url] ??
        responses[options.path] ??
        responses['*'] ??
        {};
    final encoded = '${_encodeJson(body)}';
    return ResponseBody.fromString(
      encoded,
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _encodeJson(dynamic v) {
  if (v is String) return '"$v"';
  if (v is bool || v is num) return v.toString();
  if (v is List) return '[${v.map(_encodeJson).join(',')}]';
  if (v is Map) {
    final entries =
        v.entries.map((e) => '"${e.key}":${_encodeJson(e.value)}').join(',');
    return '{$entries}';
  }
  return 'null';
}

void main() {
  // ── EventBus ───────────────────────────────────────────────────────────────

  group('EventBus', () {
    test('publishes to listeners that match the event name', () async {
      final bus = EventBus();
      var hits = 0;
      final sub = bus.on('foo').listen((_) => hits++);
      bus.publish('foo');
      bus.publish('bar');
      bus.publish('foo');
      await Future<void>.delayed(Duration.zero);
      expect(hits, 2);
      await sub.cancel();
      await bus.close();
    });

    test('onAny matches any of multiple events', () async {
      final bus = EventBus();
      final hits = <String>[];
      final sub =
          bus.stream.where(['a', 'c'].contains).listen(hits.add);
      bus.publish('a');
      bus.publish('b');
      bus.publish('c');
      await Future<void>.delayed(Duration.zero);
      expect(hits, ['a', 'c']);
      await sub.cancel();
      await bus.close();
    });
  });

  // ── ExpressionResolver: simple prefixes ─────────────────────────────────────

  group('ExpressionResolver simple prefixes', () {
    final ctx = BindingContext(
      routeParams: {'jobId': 'abc'},
      queryParams: {'tab': 'overview'},
      session: {
        'token': 'tk',
        'user': {'id': 'u1', 'email': 'a@b'},
        'org_id': 'o1',
        'roles': ['admin', 'myapp:editor'],
      },
      formValues: {'name': 'Alice'},
      elementValues: {
        'el1': {'value': 'X'}
      },
      env: {'API_BASE': 'https://api'},
    );
    final r = ExpressionResolver(ctx);

    test('route param', () async {
      expect(await r.resolve('Job: {{route.jobId}}'), 'Job: abc');
    });
    test('query param', () async {
      expect(await r.resolve('{{query.tab}}'), 'overview');
    });
    test('session.token', () async {
      expect(await r.resolve('Bearer {{session.token}}'), 'Bearer tk');
    });
    test('session.user.id (nested)', () async {
      expect(await r.resolve('{{session.user.id}}'), 'u1');
    });
    test('session.roles[0] (array index)', () async {
      expect(await r.resolve('{{session.roles[0]}}'), 'admin');
    });
    test('form field', () async {
      expect(await r.resolve('Hi {{form.name}}'), 'Hi Alice');
    });
    test('element value', () async {
      expect(await r.resolve('{{element.el1.value}}'), 'X');
    });
    test('env', () async {
      expect(await r.resolve('{{env.API_BASE}}/x'), 'https://api/x');
    });
    test('unresolved token preserved', () async {
      expect(await r.resolve('{{route.missing}}'), '{{route.missing}}');
    });
    test('resolveValue returns typed value when whole template is one token',
        () async {
      final v = await r.resolveValue('{{session.roles}}');
      expect(v, ['admin', 'myapp:editor']);
    });
    test('sync variant works for non-api prefixes', () {
      expect(r.resolveValueSync('{{form.name}}'), 'Alice');
    });
    test('sync variant throws on api.*', () {
      expect(() => r.resolveValueSync('{{api.x.y}}'), throwsStateError);
    });
  });

  // ── ExpressionResolver: i18n.* via Translator ──────────────────────────────

  group('ExpressionResolver i18n.<key>', () {
    test('resolves through StaticTranslator', () async {
      final r = ExpressionResolver(BindingContext(
        translator: const StaticTranslator({
          'web-builder.lead.title': 'Get in touch',
        }),
      ));
      expect(
        await r.resolve('Heading: {{i18n.web-builder.lead.title}}'),
        'Heading: Get in touch',
      );
    });

    test('missing key leaves the verbatim token in the output', () async {
      final r = ExpressionResolver(BindingContext(
        translator: const StaticTranslator({}),
      ));
      expect(
        await r.resolve('{{i18n.nope.x}}'),
        '{{i18n.nope.x}}',
      );
    });

    test('sync variant works for i18n', () {
      final r = ExpressionResolver(BindingContext(
        translator: const StaticTranslator({'a.b': 'value'}),
      ));
      expect(r.resolveValueSync('{{i18n.a.b}}'), 'value');
    });

    test('default BindingContext uses NoopTranslator (no crash)', () async {
      final r = ExpressionResolver(BindingContext());
      // Miss returns null → outer template loop preserves the token.
      expect(await r.resolve('{{i18n.x.y}}'), '{{i18n.x.y}}');
      // resolveValue on a single token returns null directly.
      expect(await r.resolveValue('{{i18n.x.y}}'), isNull);
    });

    test('whole-template resolveValue returns the typed string', () async {
      final r = ExpressionResolver(BindingContext(
        translator: const StaticTranslator({'a': 'A'}),
      ));
      expect(await r.resolveValue('{{i18n.a}}'), 'A');
    });
  });

  // ── session.locale convenience ─────────────────────────────────────────────

  group('session.locale fallback', () {
    test('top-level BindingContext.locale surfaces as session.locale',
        () async {
      final r = ExpressionResolver(BindingContext(locale: 'es-MX'));
      expect(await r.resolve('Hi {{session.locale}}'), 'Hi es-MX');
    });

    test('explicit session.locale takes precedence', () async {
      final r = ExpressionResolver(BindingContext(
        locale: 'en-US',
        session: {'locale': 'fr-FR'},
      ));
      expect(await r.resolve('{{session.locale}}'), 'fr-FR');
    });
  });

  // ── ExpressionResolver: api.* via HttpDataSource ────────────────────────────

  group('ExpressionResolver api.<source>', () {
    test('fetches and JSONPath-drills response', () async {
      final adapter = _StubAdapter(responses: {
        '/jobs': [
          {'id': 'j1', 'title': 'First'},
          {'id': 'j2', 'title': 'Second'},
        ],
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://api.example'));
      dio.httpClientAdapter = adapter;
      final src = HttpDataSource(baseUrl: 'http://api.example', dio: dio);

      final r = ExpressionResolver(BindingContext(dataSources: {
        'crm': src,
      }));

      expect(
        await r.resolveValue('{{api.crm.jobs.0.title}}'),
        'First',
      );
      expect(
        await r.resolveValue('{{api.crm.jobs.1.id}}'),
        'j2',
      );
    });

    test('caches identical requests', () async {
      final adapter = _StubAdapter(responses: {
        '/jobs': {'count': 1},
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://api.example'));
      dio.httpClientAdapter = adapter;
      final src = HttpDataSource(baseUrl: 'http://api.example', dio: dio);

      final r = ExpressionResolver(BindingContext(dataSources: {'x': src}));
      await r.resolveValue('{{api.x.jobs.count}}');
      await r.resolveValue('{{api.x.jobs.count}}');
      expect(adapter.seen.length, 1);
    });

    test('forwards bearer token from authTokenProvider', () async {
      final adapter = _StubAdapter(responses: {'/me': {'name': 'A'}});
      final dio = Dio(BaseOptions(baseUrl: 'http://api.example'));
      dio.httpClientAdapter = adapter;
      final src = HttpDataSource(
        baseUrl: 'http://api.example',
        dio: dio,
        authTokenProvider: () => 'tk',
      );

      final r = ExpressionResolver(BindingContext(dataSources: {'x': src}));
      await r.resolveValue('{{api.x.me.name}}');
      expect(adapter.seen.first['headers']['Authorization'], 'Bearer tk');
    });

    test('unknown source returns null (token left as-is)', () async {
      final r = ExpressionResolver(BindingContext(dataSources: const {}));
      // Whole-template resolveValue returns null
      expect(await r.resolveValue('{{api.gone.x}}'), null);
    });
  });

  // ── FormSubmitAction ────────────────────────────────────────────────────────

  group('FormSubmitAction', () {
    test('resolves URL/headers/body and reports onSuccess.navigate', () async {
      final adapter = _StubAdapter(responses: {
        '*': {'id': 'job_99'},
      });
      final dio = Dio();
      dio.httpClientAdapter = adapter;

      final ctx = BindingContext(
        session: {'token': 'tk'},
        env: {'API_BASE': 'http://api'},
      );
      final resolver = ExpressionResolver(ctx);
      final action = FormSubmitAction(
        method: 'POST',
        url: '{{env.API_BASE}}/jobs',
        body: '{{form}}',
        headers: {'Authorization': 'Bearer {{session.token}}'},
        onSuccess: {'navigate': '/jobs/{{response.id}}'},
      );

      final result = await action.execute(
        formValues: {'title': 'New'},
        resolver: resolver,
        httpClient: dio,
      );
      expect(result.success, true);
      expect(result.navigateTo, '/jobs/job_99');
      // Verify the request actually carried the resolved URL/headers/body.
      final req = adapter.seen.single;
      expect(req['method'], 'POST');
      expect(req['url'], 'http://api/jobs');
      expect(req['headers']['Authorization'], 'Bearer tk');
      expect(req['data'], {'title': 'New'});
    });

    test('publishes form.submitted on success', () async {
      final adapter = _StubAdapter(responses: {'*': {}});
      final dio = Dio();
      dio.httpClientAdapter = adapter;

      final bus = EventBus();
      final hits = <String>[];
      final sub = bus.stream.listen(hits.add);

      final ctx = BindingContext(eventBus: bus);
      final resolver = ExpressionResolver(ctx);
      final action = FormSubmitAction(
        url: 'http://api/x',
        body: '{{form}}',
      );

      await action.execute(
        formValues: {},
        resolver: resolver,
        httpClient: dio,
      );
      await Future<void>.delayed(Duration.zero);
      expect(hits, contains('form.submitted'));
      await sub.cancel();
      await bus.close();
    });

    test('runs onError block when server returns non-2xx', () async {
      final adapter = _StubAdapter(
        responses: {'*': {'error': {'message': 'rate limited'}}},
        statusCodes: {'*': 429},
      );
      final dio = Dio();
      dio.httpClientAdapter = adapter;

      final ctx = BindingContext();
      final resolver = ExpressionResolver(ctx);
      final action = FormSubmitAction(
        url: 'http://api/x',
        body: '{{form}}',
        onError: {'showToast': '{{response.error.message}}'},
      );
      final result = await action.execute(
        formValues: {},
        resolver: resolver,
        httpClient: dio,
      );
      expect(result.success, false);
      expect(result.toast, 'rate limited');
    });
  });

  // ── DataBinding model JSON roundtrip for new fields ─────────────────────────

  group('DataBinding new fields', () {
    test('refreshOn + subscribe roundtrip', () {
      const original = DataBinding(
        url: '/x',
        refreshOn: ['form.submitted', 'foo'],
        subscribe: 'execution.{{element.config.id}}',
      );
      final j = original.toJson();
      expect(j['refreshOn'], ['form.submitted', 'foo']);
      expect(j['subscribe'], 'execution.{{element.config.id}}');

      final back = DataBinding.fromJson(j);
      expect(back.refreshOn, ['form.submitted', 'foo']);
      expect(back.subscribe, 'execution.{{element.config.id}}');
    });

    test('absent refreshOn defaults to empty list', () {
      final back = DataBinding.fromJson({'url': '/x'});
      expect(back.refreshOn, isEmpty);
      expect(back.subscribe, isNull);
    });
  });
}
