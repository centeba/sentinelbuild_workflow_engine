enum NavigationType { push, replace, pop, externalUrl }

class ContextValue {
  final String? literal;
  final String? template;

  const ContextValue({this.literal, this.template});

  String resolve(Map<String, dynamic> context) {
    if (literal != null) return literal!;
    if (template != null) {
      return template!; // resolved by TemplateEngine at runtime
    }
    return '';
  }

  Map<String, dynamic> toJson() => {
        if (literal != null) 'literal': literal,
        if (template != null) 'template': template,
      };

  factory ContextValue.fromJson(Map<String, dynamic> json) => ContextValue(
        literal: json['literal'] as String?,
        template: json['template'] as String?,
      );
}

class NavigationAction {
  final String targetPageId;
  final NavigationType type;
  final Map<String, ContextValue> params;

  const NavigationAction({
    required this.targetPageId,
    this.type = NavigationType.push,
    this.params = const {},
  });

  NavigationAction copyWith({
    String? targetPageId,
    NavigationType? type,
    Map<String, ContextValue>? params,
  }) {
    return NavigationAction(
      targetPageId: targetPageId ?? this.targetPageId,
      type: type ?? this.type,
      params: params ?? this.params,
    );
  }

  Map<String, dynamic> toJson() => {
        'targetPageId': targetPageId,
        'type': type.name,
        if (params.isNotEmpty)
          'params': params.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory NavigationAction.fromJson(Map<String, dynamic> json) {
    // Backward-compat: canonical shape is
    //   {targetPageId: "<page>", type: "push|replace|pop|externalUrl", params: {...}}
    // Page authors often use a higher-level shape inherited from form/
    // workflow builders:
    //   {type: "navigate", to: "/projects/{{row.id}}"}  → push to that URL
    //   {type: "navigate", to: "page-slug"}             → push to that page
    //   {type: "form_submit", method, url, body, onSuccess: {...}}
    //   {type: "open_modal", modalId}
    // Map any of these into the canonical fields so the runtime resolver
    // and existing call-sites keep working without each one knowing every
    // dialect. Unrecognised action types degrade to a no-op push to the
    // current page id.
    final rawType = json['type']?.toString();
    String targetPageId = json['targetPageId'] as String? ?? '';
    NavigationType type = NavigationType.push;

    if (targetPageId.isEmpty && json['to'] != null) {
      targetPageId = json['to'].toString();
    }

    switch (rawType) {
      case 'navigate':
        // `to` is a URL template that the host app's router will
        // interpret. Treat absolute URLs (http://, https://) as
        // externalUrl, everything else as a push.
        if (targetPageId.startsWith('http://') ||
            targetPageId.startsWith('https://')) {
          type = NavigationType.externalUrl;
        } else {
          type = NavigationType.push;
        }
        break;
      case 'push':
      case 'replace':
      case 'pop':
      case 'externalUrl':
        type = NavigationType.values.firstWhere((t) => t.name == rawType,
            orElse: () => NavigationType.push);
        break;
      case null:
        // No type given → default to push.
        type = NavigationType.push;
        break;
      default:
        // form_submit, open_modal, etc. — not handled at the navigation
        // layer (the originating widget handles the side effect). We still
        // build a NavigationAction so existing call-sites don't crash; it
        // just navigates nowhere useful unless overridden.
        type = NavigationType.push;
    }

    return NavigationAction(
      targetPageId: targetPageId,
      type: type,
      params: (json['params'] as Map<String, dynamic>? ?? {}).map(
        (k, v) =>
            MapEntry(k, ContextValue.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }
}
