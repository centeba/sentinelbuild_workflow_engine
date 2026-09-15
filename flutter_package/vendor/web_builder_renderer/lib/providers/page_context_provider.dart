import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../binding/expression_resolver.dart';

/// Active per-page [BindingContext] keyed by `pageId`. The renderer's
/// [PageRendererWidget] publishes its `bindingContext` here on mount; child
/// widgets (e.g. ElementRenderer) read it to resolve `{{...}}` tokens —
/// notably `{{i18n.x}}` for multi-lang support — before passing config
/// values to underlying element widgets.
///
/// Null map entry = no context registered for that page → element widgets
/// fall back to rendering raw config values verbatim (legacy behaviour).
class BindingContextRegistry
    extends Notifier<Map<String, BindingContext>> {
  @override
  Map<String, BindingContext> build() => const {};

  void register(String pageId, BindingContext ctx) {
    state = {...state, pageId: ctx};
  }

  void unregister(String pageId) {
    final next = Map<String, BindingContext>.from(state)..remove(pageId);
    state = next;
  }

  /// Page-scoped element value tracking. Standalone form fields (a dropdown
  /// sitting outside any Form Block, etc.) call this when their value
  /// changes so other elements on the same page can reference them via
  /// `{{element.<id>.value}}` in upload URLs, data bindings, etc.
  void setElementValue(String pageId, String elementId, dynamic value) {
    final ctx = state[pageId];
    if (ctx == null) return;
    final nextElements =
        Map<String, Map<String, dynamic>>.from(ctx.elementValues);
    final inner = Map<String, dynamic>.from(
      nextElements[elementId] ?? const <String, dynamic>{},
    );
    inner['value'] = value;
    nextElements[elementId] = inner;
    state = {...state, pageId: ctx.copyWith(elementValues: nextElements)};
  }
}

final bindingContextProvider =
    NotifierProvider<BindingContextRegistry, Map<String, BindingContext>>(
  BindingContextRegistry.new,
);

/// Per-page host-app callbacks (onNavigate, onFormSubmit, etc.) so element
/// widgets can fire side effects without prop-drilling. The host registers
/// callbacks via [PageRendererWidget.callbacks]; the widget publishes them
/// here on mount.
class PageRendererCallbacksRegistry
    extends Notifier<Map<String, Object>> {
  @override
  Map<String, Object> build() => const {};

  void register(String pageId, Object callbacks) {
    state = {...state, pageId: callbacks};
  }

  void unregister(String pageId) {
    final next = Map<String, Object>.from(state)..remove(pageId);
    state = next;
  }
}

final pageRendererCallbacksProvider =
    NotifierProvider<PageRendererCallbacksRegistry, Map<String, Object>>(
  PageRendererCallbacksRegistry.new,
);

/// Per-page context map keyed by `pageId` → arbitrary key/value pairs that
/// templating + bindings can read.
///
/// The context honors a small set of well-known top-level keys (Phase 4 of
/// documents/platform/web-builder-roadmap.md):
///   - `route`   : Map of GoRouter path params (e.g. `{"id": "abc"}`)
///   - `query`   : Map of URL query params
///   - `session` : Map with `user`, `org_id`, `roles: List<String>`, `token`
///                 — used by the renderer for role-visibility filtering
///                 (Phase 6) and by binding expressions (Phase 4).
///   - `params`  : Free-form host-app context.
///
/// Vertical apps inject the values once at `PageRendererWidget.initialContext`
/// time; the [setPageContext] mutator overwrites for the same page.
class PageContextNotifier
    extends Notifier<Map<String, Map<String, dynamic>>> {
  @override
  Map<String, Map<String, dynamic>> build() => {};

  void setPageContext(String pageId, Map<String, dynamic> params) {
    state = {...state, pageId: params};
  }

  void clearPageContext(String pageId) {
    final updated = Map<String, Map<String, dynamic>>.from(state);
    updated.remove(pageId);
    state = updated;
  }

  Map<String, dynamic> getContext(String pageId) {
    return state[pageId] ?? {};
  }

  dynamic getValue(String pageId, String keyPath) {
    final ctx = state[pageId] ?? {};
    final parts = keyPath.split('.');
    dynamic current = ctx;
    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  /// Returns the active user's roles for `pageId`, reading the well-known
  /// `session.roles` slot. Returns an empty list when no session/roles are
  /// configured (which means "no role match" — anything with non-empty
  /// `role_visibility` is hidden).
  List<String> getRoles(String pageId) {
    final raw = getValue(pageId, 'session.roles');
    if (raw is List) return List<String>.from(raw.map((e) => e.toString()));
    return const [];
  }

  /// True if the user can see an element gated by [roleVisibility]. Null /
  /// empty `roleVisibility` always passes ("visible to all"); otherwise the
  /// user must have at least one matching role.
  bool isVisibleToRoles(String pageId, List<String>? roleVisibility) {
    if (roleVisibility == null || roleVisibility.isEmpty) return true;
    final roles = getRoles(pageId);
    if (roles.isEmpty) return false;
    final required = roleVisibility.toSet();
    return roles.any(required.contains);
  }
}

final pageContextProvider =
    NotifierProvider<PageContextNotifier, Map<String, Map<String, dynamic>>>(
  PageContextNotifier.new,
);
