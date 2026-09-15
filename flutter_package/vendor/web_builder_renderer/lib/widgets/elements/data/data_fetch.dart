// Shared helper for data-bound widgets (dataTable, list, kanban, plus the
// Phase-4-finisher display widgets: statCard, apiText, gaugeChart, chart,
// stepper).
//
// Page JSON expresses URLs as `{{env.X}}/path?query={{form.x}}` (or
// `{{api.<source>.<...>}}`).  We resolve the templates via
// ExpressionResolver, identify the matching HttpDataSource by baseUrl
// prefix, and call its `fetch` so caching + auth stay centralised. Falls
// back to a fresh authenticated Dio call if no registered source matches.
import 'dart:async';

import 'package:dio/dio.dart';

import '../../../binding/expression_resolver.dart';
import '../../../models/data_binding.dart';

/// Resolves the URL + headers from a DataBinding, fetches the response,
/// and returns it as a list of maps (the row shape both dataTable and list
/// consume). If the response is itself a list it's returned as-is; if it's
/// an envelope `{items: [...]}` the `items` array is extracted; if it's a
/// single object the helper returns a one-row list.
Future<List<Map<String, dynamic>>> fetchBindingRows(
  BindingContext ctx,
  DataBinding binding,
) async {
  final body = await fetchBindingBody(ctx, binding);
  if (body is List) {
    return body.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }
  if (body is Map<String, dynamic>) {
    for (final key in const ['items', 'results', 'data', 'rows']) {
      final v = body[key];
      if (v is List) {
        return v.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
    }
    return [body];
  }
  return const [];
}

/// Raw fetch — returns whatever the endpoint returns. Used by elements
/// that consume the response in a non-list shape (e.g. statCard reading
/// a `{count: 42}` envelope, gauge reading a `{value: 0.8}` envelope).
Future<dynamic> fetchBindingBody(
  BindingContext ctx,
  DataBinding binding,
) async {
  final resolver = ExpressionResolver(ctx);
  final url = await resolver.resolve(binding.url);
  final resolvedHeaders = <String, String>{};
  for (final entry in binding.headers.entries) {
    final v = await resolver.resolve(entry.value);
    if (v.isNotEmpty) resolvedHeaders[entry.key] = v;
  }

  // Try to route through a registered HttpDataSource so the central cache +
  // auth-token-provider apply. Match by baseUrl prefix.
  for (final source in ctx.dataSources.values) {
    final base = source.baseUrl;
    if (base != null && base.isNotEmpty && url.startsWith(base)) {
      final relative = url.substring(base.length);
      final queryParams = _splitQuery(relative);
      final pathOnly = _stripQuery(relative);
      return source.fetch(pathOnly, queryParams: queryParams);
    }
  }

  // No matching source — fall back to a one-off authenticated request.
  // Auth comes from the headers the page already specified (typically
  // `Authorization: Bearer {{session.access_token}}`).
  final dio = Dio();
  final body = binding.body == null
      ? null
      : await resolver.resolve(binding.body!);
  final resp = await dio.request<dynamic>(
    url,
    options: Options(method: binding.method.name, headers: resolvedHeaders),
    data: body,
  );
  return resp.data;
}

Map<String, dynamic>? _splitQuery(String relative) {
  final q = relative.indexOf('?');
  if (q < 0) return null;
  final qs = relative.substring(q + 1);
  if (qs.isEmpty) return null;
  final out = <String, dynamic>{};
  for (final pair in qs.split('&')) {
    final eq = pair.indexOf('=');
    if (eq < 0) {
      out[Uri.decodeQueryComponent(pair)] = '';
    } else {
      out[Uri.decodeQueryComponent(pair.substring(0, eq))] =
          Uri.decodeQueryComponent(pair.substring(eq + 1));
    }
  }
  return out;
}

String _stripQuery(String relative) {
  final q = relative.indexOf('?');
  return q < 0 ? relative : relative.substring(0, q);
}

/// Scalar read: fetch the binding then drill into the response via a
/// dot-separated [responsePath] (e.g. `data.count`, `value`,
/// `kpis.0.value`). Returns null when the path can't be resolved.
Future<dynamic> fetchBindingValue(
  BindingContext ctx,
  DataBinding binding, {
  String? responsePath,
}) async {
  final body = await fetchBindingBody(ctx, binding);
  final path = (responsePath ?? binding.responsePath).trim();
  if (path.isEmpty || path == r'$') return body;
  return _drillPath(body, _normalisePath(path));
}

/// Splits a path like `kpis.0.title` or `$.kpis[0].title` into segments
/// the resolver can walk.
List<String> _normalisePath(String path) {
  var p = path;
  if (p.startsWith(r'$.')) p = p.substring(2);
  if (p.startsWith(r'$')) p = p.substring(1);
  // Convert `kpis[0]` → `kpis.0`
  p = p.replaceAllMapped(RegExp(r'\[(\d+)\]'), (m) => '.${m.group(1)}');
  return p.split('.').where((s) => s.isNotEmpty).toList();
}

dynamic _drillPath(dynamic node, List<String> parts) {
  dynamic current = node;
  for (final p in parts) {
    if (current is Map) {
      current = current[p];
    } else if (current is List) {
      final i = int.tryParse(p);
      if (i == null || i < 0 || i >= current.length) return null;
      current = current[i];
    } else {
      return null;
    }
  }
  return current;
}

/// Subscribes the caller to the `refreshOn` events declared on a
/// [DataBinding]. When any event fires:
///   1. We invalidate the matching HttpDataSource's cache for this URL,
///      so the next fetch is fresh
///   2. We call [onTrigger], so the caller can bump its own state /
///      re-render
///
/// Returns a cancel function that the caller must invoke in dispose to
/// avoid leaking the subscription.
void Function() bindRefreshOn(
  BindingContext ctx,
  DataBinding binding,
  Future<void> Function() onTrigger,
) {
  final events = binding.refreshOn;
  if (events.isEmpty) return () {};
  final sub = ctx.eventBus.onAny(events).listen((_) {
    // Best-effort cache invalidation. We don't know the resolved URL here
    // without re-running the resolver, so invalidate every source — the
    // cost is bounded (a Map clear) and the benefit is correctness.
    for (final source in ctx.dataSources.values) {
      source.invalidate();
    }
    // Don't await — the listen callback is sync; let the trigger run in
    // its own zone and swallow errors so they don't bubble up as
    // unhandled-async exceptions.
    onTrigger().catchError((_) {});
  });
  // Wrap `sub.cancel` (which returns Future<void>) in a void thunk so
  // callers can `cancel()` without dropping a Future on the floor — the
  // dropped Future surfaces as "Instance of 'Future<void>'" type errors
  // on Flutter web at dispose time.
  return () {
    sub.cancel();
  };
}
