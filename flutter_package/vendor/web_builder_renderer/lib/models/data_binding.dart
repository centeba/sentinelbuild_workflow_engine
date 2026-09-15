enum HttpMethod { get, post, put, delete, patch }

class DataBinding {
  final String url;
  final HttpMethod method;
  final Map<String, String> headers;
  final String? body;
  final String responsePath;
  final int? pollingIntervalSeconds;
  final bool fetchOnLoad;
  final String? triggerElementId;
  /// Phase 4 of documents/platform/web-builder-roadmap.md — names of EventBus events the bound
  /// element should listen to. When any of these fire, the element re-fetches
  /// (after invalidating its cached value). Empty list = no event-driven refresh.
  final List<String> refreshOn;
  /// Phase 8 hook (gated on PLATFORM_GAPS_PLAN Phase 5.1 WS bus). When set,
  /// the renderer opens a subscription on element mount and re-fetches on
  /// every incoming message. Stored as a string template — the host app's
  /// WS adapter resolves it at subscription time. Null = no subscription.
  final String? subscribe;

  const DataBinding({
    required this.url,
    this.method = HttpMethod.get,
    this.headers = const {},
    this.body,
    this.responsePath = '\$',
    this.pollingIntervalSeconds,
    this.fetchOnLoad = true,
    this.triggerElementId,
    this.refreshOn = const [],
    this.subscribe,
  });

  DataBinding copyWith({
    String? url,
    HttpMethod? method,
    Map<String, String>? headers,
    String? body,
    String? responsePath,
    int? pollingIntervalSeconds,
    bool? fetchOnLoad,
    String? triggerElementId,
    List<String>? refreshOn,
    String? subscribe,
  }) {
    return DataBinding(
      url: url ?? this.url,
      method: method ?? this.method,
      headers: headers ?? this.headers,
      body: body ?? this.body,
      responsePath: responsePath ?? this.responsePath,
      pollingIntervalSeconds:
          pollingIntervalSeconds ?? this.pollingIntervalSeconds,
      fetchOnLoad: fetchOnLoad ?? this.fetchOnLoad,
      triggerElementId: triggerElementId ?? this.triggerElementId,
      refreshOn: refreshOn ?? this.refreshOn,
      subscribe: subscribe ?? this.subscribe,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'method': method.name,
        if (headers.isNotEmpty) 'headers': headers,
        if (body != null) 'body': body,
        'responsePath': responsePath,
        if (pollingIntervalSeconds != null)
          'pollingIntervalSeconds': pollingIntervalSeconds,
        'fetchOnLoad': fetchOnLoad,
        if (triggerElementId != null) 'triggerElementId': triggerElementId,
        if (refreshOn.isNotEmpty) 'refreshOn': refreshOn,
        if (subscribe != null) 'subscribe': subscribe,
      };

  factory DataBinding.fromJson(Map<String, dynamic> json) => DataBinding(
        url: json['url'] as String,
        method: HttpMethod.values.firstWhere(
          (m) => m.name == json['method'],
          orElse: () => HttpMethod.get,
        ),
        headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
        body: json['body'] as String?,
        responsePath: json['responsePath'] as String? ?? '\$',
        pollingIntervalSeconds: json['pollingIntervalSeconds'] as int?,
        fetchOnLoad: json['fetchOnLoad'] as bool? ?? true,
        triggerElementId: json['triggerElementId'] as String?,
        refreshOn: (json['refreshOn'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        subscribe: json['subscribe'] as String?,
      );
}
