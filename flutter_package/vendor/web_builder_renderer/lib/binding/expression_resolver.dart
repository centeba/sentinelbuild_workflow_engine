import '../services/template_engine.dart';
import 'data_source.dart';
import 'event_bus.dart';
import 'realtime.dart';
import 'translator.dart';

/// Runtime context for [ExpressionResolver].
///
/// Phase 4 of documents/platform/web-builder-roadmap.md — the resolver consults this struct when
/// substituting `{{...}}` tokens. Vertical apps build one per page and pass
/// it to `PageRendererWidget.bindingContext`.
class BindingContext {
  /// GoRouter / equivalent path params, e.g. `{ "id": "abc" }`.
  final Map<String, dynamic> routeParams;

  /// URL query params.
  final Map<String, dynamic> queryParams;

  /// Auth + identity. Well-known shape:
  /// `{ "token": "...", "user": {"id":"u_1","email":"a@b"}, "org_id":"o_1",
  ///    "roles": ["admin", "myapp:editor"] }`.
  final Map<String, dynamic> session;

  /// Free-form host context — copied from `PageRendererWidget.initialContext`
  /// for backward compatibility with the legacy `{{context.x}}` prefix.
  final Map<String, dynamic> context;

  /// Registered HTTP sources keyed by name. The token `{{api.<name>.<jsonpath>}}`
  /// looks up `<name>` here.
  final Map<String, HttpDataSource> dataSources;

  /// Currently-mounted form values — populated by `FormScope` / `FormElement`.
  /// Token: `{{form.<field>}}`.
  final Map<String, dynamic> formValues;

  /// Element runtime state, keyed by element id. Token: `{{element.<id>.<prop>}}`.
  final Map<String, Map<String, dynamic>> elementValues;

  /// Build-time / deploy-time env values. Restricted at the host-app level
  /// (do not pass secrets — they will end up in the rendered DOM).
  /// Token: `{{env.<name>}}`.
  final Map<String, String> env;

  /// Pub/sub for `refreshOn:` triggers and form-submit lifecycle events.
  final EventBus eventBus;

  /// Phase 8 — host-supplied WebSocket transport. Defaults to a no-op so
  /// pages with `dataBinding.subscribe` render correctly even when the
  /// platform WS bus isn't available yet.
  final WebSocketAdapter webSocket;

  /// Multi-lang — host-supplied translator backing `{{i18n.<key>}}` tokens.
  /// Defaults to [NoopTranslator] which leaves tokens verbatim on miss.
  final Translator translator;

  /// BCP-47 locale tag (e.g. "en-US", "es-MX"). Surfaced as
  /// `{{session.locale}}` and used by the host-app adapter to load the
  /// matching translation pack. Null = no locale-aware resolution.
  final String? locale;

  BindingContext({
    this.routeParams = const {},
    this.queryParams = const {},
    this.session = const {},
    this.context = const {},
    this.dataSources = const {},
    this.formValues = const {},
    this.elementValues = const {},
    this.env = const {},
    EventBus? eventBus,
    WebSocketAdapter? webSocket,
    Translator? translator,
    this.locale,
  })  : eventBus = eventBus ?? EventBus(),
        webSocket = webSocket ?? const NoopWebSocketAdapter(),
        translator = translator ?? const NoopTranslator();

  BindingContext copyWith({
    Map<String, dynamic>? routeParams,
    Map<String, dynamic>? queryParams,
    Map<String, dynamic>? session,
    Map<String, dynamic>? context,
    Map<String, HttpDataSource>? dataSources,
    Map<String, dynamic>? formValues,
    Map<String, Map<String, dynamic>>? elementValues,
    Map<String, String>? env,
    EventBus? eventBus,
    WebSocketAdapter? webSocket,
    Translator? translator,
    String? locale,
  }) {
    return BindingContext(
      routeParams: routeParams ?? this.routeParams,
      queryParams: queryParams ?? this.queryParams,
      session: session ?? this.session,
      context: context ?? this.context,
      dataSources: dataSources ?? this.dataSources,
      formValues: formValues ?? this.formValues,
      elementValues: elementValues ?? this.elementValues,
      env: env ?? this.env,
      eventBus: eventBus ?? this.eventBus,
      webSocket: webSocket ?? this.webSocket,
      translator: translator ?? this.translator,
      locale: locale ?? this.locale,
    );
  }
}

/// Resolves `{{...}}` template tokens against a [BindingContext].
///
/// Supports the following prefixes:
///   - `route.<param>`         — URL path params
///   - `query.<param>`         — URL query params
///   - `session.token` / `session.user.*` / `session.org_id` /
///     `session.roles` (or `session.roles[i]`)
///   - `api.<source>.<jsonpath>`  — fetches via the named [HttpDataSource]
///                                  and evaluates the JSONPath against the
///                                  response body
///   - `form.<field>`          — current value from the active form scope
///   - `element.<id>.<prop>`   — runtime value reported by an element
///   - `env.<name>`            — host-app build-time env safe-list
///   - `context.*` / `site.*` / `page.formResult.*` — preserved via the
///     legacy [TemplateEngine] for backward compatibility
class ExpressionResolver {
  final BindingContext bindingContext;
  final TemplateEngine _legacy;

  ExpressionResolver(this.bindingContext, {TemplateEngine? legacy})
      : _legacy = legacy ?? TemplateEngine();

  static final _tokenRegex = RegExp(r'\{\{([^}]+)\}\}');

  /// Resolve a string template, awaiting any async data-source fetches.
  /// Untouched tokens (paths that don't resolve) are left in the output as
  /// `{{...}}` so the caller can surface a "binding error" hint instead of
  /// rendering an empty string.
  Future<String> resolve(String template) async {
    final matches = _tokenRegex.allMatches(template).toList();
    if (matches.isEmpty) return template;

    // Resolve all tokens (in parallel where possible).
    final replacements = await Future.wait(
      matches.map((m) async {
        final path = m.group(1)!.trim();
        final v = await _resolvePath(path);
        return v?.toString();
      }),
    );

    // Single-pass replace using the original match boundaries.
    final buf = StringBuffer();
    int cursor = 0;
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      buf.write(template.substring(cursor, m.start));
      final value = replacements[i];
      buf.write(value ?? m.group(0));
      cursor = m.end;
    }
    buf.write(template.substring(cursor));
    return buf.toString();
  }

  /// Resolve to a typed value when the entire template is a single token
  /// (e.g. `"{{api.x.jobs}}"` returns the list directly). Falls back to
  /// [resolve] for mixed content.
  Future<dynamic> resolveValue(String template) async {
    final trimmed = template.trim();
    final m = _tokenRegex.firstMatch(trimmed);
    if (m != null && m.group(0) == trimmed) {
      return _resolvePath(m.group(1)!.trim());
    }
    return resolve(template);
  }

  /// Synchronous variant — throws on `api.*` (those need awaiting).
  dynamic resolveValueSync(String template) {
    final trimmed = template.trim();
    final m = _tokenRegex.firstMatch(trimmed);
    if (m != null && m.group(0) == trimmed) {
      return _resolveSync(m.group(1)!.trim());
    }
    return template.replaceAllMapped(_tokenRegex, (match) {
      final path = match.group(1)!.trim();
      try {
        final v = _resolveSync(path);
        return v?.toString() ?? match.group(0)!;
      } catch (_) {
        return match.group(0)!;
      }
    });
  }

  // ── Path resolution ────────────────────────────────────────────────────────

  Future<dynamic> _resolvePath(String path) async {
    final parts = path.split('.');
    if (parts.isEmpty) return null;
    final prefix = parts.first;

    switch (prefix) {
      case 'route':
        return _drill(bindingContext.routeParams, parts.sublist(1));
      case 'query':
        return _drill(bindingContext.queryParams, parts.sublist(1));
      case 'session':
        return _resolveSession(parts.sublist(1));
      case 'form':
        return _drill(bindingContext.formValues, parts.sublist(1));
      case 'element':
        return _drill(bindingContext.elementValues, parts.sublist(1));
      case 'env':
        return _drill(bindingContext.env, parts.sublist(1));
      case 'api':
        return _resolveApi(parts.sublist(1));
      case 'i18n':
        // null on miss — outer loop preserves the verbatim token.
        return bindingContext.translator.translate(parts.sublist(1).join('.'));
      default:
        // Delegate to the legacy engine (handles `context`, `site`,
        // `page.formResult`, `element.*` legacy shape, plain keys).
        return _legacy.resolveValue(
          '{{$path}}',
          context: bindingContext.context,
          siteGlobals: const {},
          elementValues: const {},
        );
    }
  }

  dynamic _resolveSync(String path) {
    final parts = path.split('.');
    if (parts.isEmpty) return null;
    final prefix = parts.first;

    switch (prefix) {
      case 'route':
        return _drill(bindingContext.routeParams, parts.sublist(1));
      case 'query':
        return _drill(bindingContext.queryParams, parts.sublist(1));
      case 'session':
        return _resolveSession(parts.sublist(1));
      case 'form':
        return _drill(bindingContext.formValues, parts.sublist(1));
      case 'element':
        return _drill(bindingContext.elementValues, parts.sublist(1));
      case 'env':
        return _drill(bindingContext.env, parts.sublist(1));
      case 'api':
        throw StateError(
            'api.* references are async; use resolveValue() instead');
      case 'i18n':
        return bindingContext.translator.translate(parts.sublist(1).join('.'));
      default:
        return _legacy.resolveValue(
          '{{$path}}',
          context: bindingContext.context,
        );
    }
  }

  /// `{{session.<path>}}` — prefers values in the `session` map, then falls
  /// back to top-level [BindingContext.locale] for the well-known
  /// `session.locale` token. Host apps that don't bother filling the
  /// session map can still rely on `{{session.locale}}` to surface the
  /// active locale.
  dynamic _resolveSession(List<String> parts) {
    final v = _drill(bindingContext.session, parts);
    if (v != null) return v;
    if (parts.length == 1 && parts.first == 'locale') {
      return bindingContext.locale;
    }
    return null;
  }

  /// `{{api.<source>.<jsonpath>}}`
  /// Convention: the path after the source name is treated as JSONPath
  /// against the response body, with `[N]` array indexing supported.
  Future<dynamic> _resolveApi(List<String> parts) async {
    if (parts.isEmpty) return null;
    final sourceName = parts.first;
    final source = bindingContext.dataSources[sourceName];
    if (source == null) return null;

    // Anything after the source name is path + JSONPath. Convention: the
    // first segment is the URL path; subsequent segments are JSONPath into
    // the response. e.g. `api.crm.records.0.title`:
    //   urlPath = "/records"   responsePath = "0.title"
    // For more flexibility, vertical apps can register a source whose
    // baseUrl already encodes the path, then use JSONPath only.
    if (parts.length == 1) {
      return source.fetch('/');
    }
    final urlSeg = parts[1];
    final jsonPathParts = parts.length > 2 ? parts.sublist(2) : const <String>[];
    final body = await source.fetch('/$urlSeg');
    if (jsonPathParts.isEmpty) return body;
    // Use our own drill so numeric indices work against List bodies (the
    // legacy TemplateEngine.extractPath only supports `key[N]` shape).
    return _drill(body, jsonPathParts);
  }

  // ── Drill helper ───────────────────────────────────────────────────────────

  static dynamic _drill(dynamic root, List<String> parts) {
    dynamic current = root;
    for (final part in parts) {
      if (current == null) return null;
      // Support `roles[0]` style array indexing.
      final arrayMatch = RegExp(r'^(\w+)\[(\d+)\]$').firstMatch(part);
      if (arrayMatch != null) {
        final key = arrayMatch.group(1)!;
        final idx = int.parse(arrayMatch.group(2)!);
        if (current is Map) current = current[key];
        if (current is List && idx < current.length) {
          current = current[idx];
        } else {
          return null;
        }
        continue;
      }
      if (current is Map) {
        current = current[part];
      } else if (current is List) {
        final idx = int.tryParse(part);
        if (idx != null && idx >= 0 && idx < current.length) {
          current = current[idx];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return current;
  }
}
