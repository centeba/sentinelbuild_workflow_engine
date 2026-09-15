import 'package:dio/dio.dart';

import 'expression_resolver.dart';

/// Outcome of a [FormSubmitAction.execute] call.
class FormSubmitResult {
  final bool success;
  final dynamic response;
  final String? error;
  final String? navigateTo;
  final String? toast;

  const FormSubmitResult({
    required this.success,
    this.response,
    this.error,
    this.navigateTo,
    this.toast,
  });
}

/// Structured "submit this form" action — Phase 4 of documents/platform/web-builder-roadmap.md.
///
/// Form Submit buttons read this off their `PageElement.action` and execute
/// it with the current form values. The action handles three things:
///   1. Resolve `{{...}}` tokens in `url`, `headers`, and `body`
///   2. Make the HTTP request
///   3. Run `onSuccess` (navigate / toast) or `onError` based on the response
///
/// JSON shape:
/// ```json
/// {
///   "type": "form_submit",
///   "method": "POST",
///   "url": "{{env.API_BASE}}/records",
///   "body": "{{form}}",
///   "headers": { "Authorization": "Bearer {{session.token}}" },
///   "onSuccess": { "navigate": "/records/{{response.id}}" },
///   "onError":   { "showToast": "{{response.error.message}}" }
/// }
/// ```
class FormSubmitAction {
  final String method;
  final String url;
  /// Either a literal map, or the magic string `"{{form}}"` to send the
  /// active form values verbatim, or a token-bearing string that will be
  /// resolved + JSON-decoded.
  final dynamic body;
  final Map<String, String> headers;
  final Map<String, dynamic>? onSuccess;
  final Map<String, dynamic>? onError;
  /// Event names to publish on the bus when the action completes
  /// successfully — typically `["form.submitted", "form.<formId>.submitted"]`.
  final List<String> publishOnSuccess;

  const FormSubmitAction({
    this.method = 'POST',
    required this.url,
    this.body,
    this.headers = const {},
    this.onSuccess,
    this.onError,
    this.publishOnSuccess = const ['form.submitted'],
  });

  factory FormSubmitAction.fromJson(Map<String, dynamic> json) =>
      FormSubmitAction(
        method: (json['method'] as String? ?? 'POST').toUpperCase(),
        url: json['url'] as String,
        body: json['body'],
        headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
        onSuccess: json['onSuccess'] as Map<String, dynamic>?,
        onError: json['onError'] as Map<String, dynamic>?,
        publishOnSuccess: (json['publishOnSuccess'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const ['form.submitted'],
      );

  Map<String, dynamic> toJson() => {
        'type': 'form_submit',
        'method': method,
        'url': url,
        if (body != null) 'body': body,
        if (headers.isNotEmpty) 'headers': headers,
        if (onSuccess != null) 'onSuccess': onSuccess,
        if (onError != null) 'onError': onError,
        if (publishOnSuccess.isNotEmpty) 'publishOnSuccess': publishOnSuccess,
      };

  /// Execute the action with the current form values + a configured Dio.
  /// Returns a [FormSubmitResult] the caller can react to (navigate, toast).
  Future<FormSubmitResult> execute({
    required Map<String, dynamic> formValues,
    required ExpressionResolver resolver,
    Dio? httpClient,
  }) async {
    // The chassis is expected to inject a Dio with the auth interceptor +
    // base URL configured. Falling back to a bare Dio() means no
    // Authorization header is attached and any /api/... call will 401.
    // Surface that misconfiguration loudly in debug; in release we still
    // construct one so the page doesn't crash, but the request will fail.
    assert(httpClient != null,
        'FormSubmitAction.execute called without an httpClient — '
        'the chassis must override BindingContext.dio so the form '
        'inherits the auth interceptor and base URL.');
    final dio = httpClient ?? Dio();

    // Resolve URL + headers up-front (sync where possible).
    final resolvedUrl = await resolver.resolve(url);
    final resolvedHeaders = <String, String>{};
    for (final e in headers.entries) {
      resolvedHeaders[e.key] = await resolver.resolve(e.value);
    }

    // Resolve body. Three shapes:
    //   1) Map literal — send as-is (after resolving any string values)
    //   2) String "{{form}}" — send formValues
    //   3) Other string — resolve template, send the resulting string
    dynamic resolvedBody;
    if (body == null) {
      resolvedBody = null;
    } else if (body is String) {
      if (body.trim() == '{{form}}') {
        resolvedBody = formValues;
      } else {
        resolvedBody = await resolver.resolve(body);
      }
    } else if (body is Map) {
      resolvedBody = await _resolveMapTokens(
          body.cast<String, dynamic>(), resolver, formValues);
    } else {
      resolvedBody = body;
    }

    Response<dynamic>? resp;
    String? error;
    try {
      // We override validateStatus so non-2xx responses surface here as
      // ordinary Response objects — the action treats status-code as the
      // source of truth and runs its own onError block. Without this,
      // dio's default raises on 4xx/5xx and the response body needed by
      // `{{response.error.message}}` bindings is harder to retrieve.
      resp = await dio.request(
        resolvedUrl,
        data: resolvedBody,
        options: Options(
          method: method,
          headers: resolvedHeaders,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      resp = e.response;
      error = e.message ?? 'request failed';
    } catch (e) {
      error = e.toString();
    }

    final statusCode = resp?.statusCode;
    final ok = error == null &&
        statusCode != null &&
        statusCode >= 200 &&
        statusCode < 300;

    // Branch: bind `{{response.*}}` for the duration of running onSuccess /
    // onError side-effects.
    final branchCtx = resolver.bindingContext.copyWith(
      context: {
        ...resolver.bindingContext.context,
        'response': resp?.data ?? {'error': {'message': error}},
      },
    );
    final branchResolver =
        ExpressionResolver(branchCtx, legacy: null);

    String? navigate;
    String? toast;

    final block = ok ? onSuccess : onError;
    if (block != null) {
      final navTpl = block['navigate'] as String?;
      if (navTpl != null) {
        navigate = await branchResolver.resolve(navTpl);
      }
      final toastTpl = block['showToast'] as String? ??
          block['toast'] as String?;
      if (toastTpl != null) {
        toast = await branchResolver.resolve(toastTpl);
      }
    }

    if (ok) {
      for (final ev in publishOnSuccess) {
        resolver.bindingContext.eventBus.publish(ev);
      }
    }

    return FormSubmitResult(
      success: ok,
      response: resp?.data,
      error: ok ? null : (error ?? 'HTTP ${resp?.statusCode}'),
      navigateTo: navigate,
      toast: toast,
    );
  }

  static Future<Map<String, dynamic>> _resolveMapTokens(
    Map<String, dynamic> input,
    ExpressionResolver resolver,
    Map<String, dynamic> formValues,
  ) async {
    final out = <String, dynamic>{};
    for (final entry in input.entries) {
      final v = entry.value;
      if (v is String) {
        if (v.trim() == '{{form}}') {
          out[entry.key] = formValues;
        } else {
          out[entry.key] = await resolver.resolve(v);
        }
      } else if (v is Map) {
        out[entry.key] = await _resolveMapTokens(
            v.cast<String, dynamic>(), resolver, formValues);
      } else {
        out[entry.key] = v;
      }
    }
    return out;
  }
}
