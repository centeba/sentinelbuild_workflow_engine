import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../binding/expression_resolver.dart';
import '../binding/realtime.dart';
import '../models/page_definition.dart';
import '../models/page_element.dart';
import '../models/page_section.dart';
import '../models/site_definition.dart';
import '../design/palette.dart';
import '../design/pd_tokens.gen.dart';
import '../design/tokens.dart';
import '../providers/page_context_provider.dart';
import '../providers/section_counts_provider.dart';
import '../util/ui_prefs.dart';
import 'elements/element_renderer.dart';

/// Callbacks the host app can intercept to customize behavior:
/// - [onNavigate]   — fires when a `NavigationAction` resolves to navigate to
///                    a different page. The host app's router decides what to
///                    do (push a route, replace, open in a tab, etc.).
/// - [onFormSubmit] — fires when a form element submits with `local_only`.
///                    The host app receives the field values and decides what
///                    to do. SentinelBuild submit actions still hit the API
///                    directly via the configured client.
/// - [onApiCall]    — optional override for outgoing data-binding API calls.
///                    Useful for hosts that want to inject an in-app cache
///                    layer or replace HTTP with native calls.
class PageRendererCallbacks {
  final void Function(String pageId, Map<String, dynamic> params)? onNavigate;
  final void Function(String formElementId, Map<String, dynamic> values)?
      onFormSubmit;
  final Future<dynamic> Function(String url, Map<String, String> headers)?
      onApiCall;

  /// Fired by Form Block's `action.onSuccess.showToast` /
  /// `action.onError.showToast`. Host wires this to its in-app toast/snackbar.
  final void Function(String message)? onShowToast;

  /// Fired after a Form Block successfully POSTs its form_submit action.
  /// Hosts can use this for analytics, follow-up navigation, etc. The
  /// elementId is the form's id; response is the parsed body.
  final void Function(String formElementId, dynamic response)?
      onFormSubmitDone;

  const PageRendererCallbacks({
    this.onNavigate,
    this.onFormSubmit,
    this.onApiCall,
    this.onShowToast,
    this.onFormSubmitDone,
  });
}

/// Top-level widget for embedding a published page authored in the
/// web-builder. Takes a [PageDefinition] (decoded from the page JSON
/// returned by `PagesApiClient.get_published_page`) and renders it with
/// no builder chrome.
///
/// Wrap with [ProviderScope] in your host app. Pass [initialContext] for
/// any `{{context.x}}` template tokens used by the page (e.g. the current
/// user id, the resource id this page is showing).
///
/// ```dart
/// PageRendererWidget(
///   page: PageDefinition.fromJson(json),
///   initialContext: {'userId': 'u_123', 'recordId': 'r_42'},
///   callbacks: PageRendererCallbacks(
///     onNavigate: (pageId, params) => myRouter.push('/page/$pageId', extra: params),
///   ),
/// )
/// ```
class PageRendererWidget extends ConsumerStatefulWidget {
  final PageDefinition page;
  final SiteDefinition? site;
  final Map<String, dynamic> initialContext;
  final PageRendererCallbacks? callbacks;

  /// If true, wraps the page in a centered max-width container (1200px)
  /// with the canvas background, mirroring the builder Preview chrome.
  final bool wrapInCanvas;

  /// Phase 4 + 8 — typed binding context. When provided, the renderer
  /// instantiates a [RealtimeSubscriptionManager] for elements declaring
  /// `dataBinding.subscribe`, and exposes the resolver to host-app
  /// element widgets via [bindingContextProvider].
  ///
  /// Backward-compat: when null, the renderer behaves exactly as before
  /// (legacy `pageContextProvider` only).
  final BindingContext? bindingContext;

  const PageRendererWidget({
    super.key,
    required this.page,
    this.site,
    this.initialContext = const {},
    this.callbacks,
    this.wrapInCanvas = false,
    this.bindingContext,
  });

  @override
  ConsumerState<PageRendererWidget> createState() =>
      _PageRendererWidgetState();
}

class _PageRendererWidgetState extends ConsumerState<PageRendererWidget> {
  RealtimeSubscriptionManager? _realtime;
  final List<void Function()> _subCancellers = [];

  @override
  void initState() {
    super.initState();
    // Seed page context once the widget tree is mounted.
    if (widget.initialContext.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(pageContextProvider.notifier)
            .setPageContext(widget.page.id, widget.initialContext);
      });
    }

    // Publish host-app callbacks so action-firing elements (buttons, row
    // tap targets) can fire onNavigate / onFormSubmit without prop-drill.
    if (widget.callbacks != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(pageRendererCallbacksProvider.notifier)
            .register(widget.page.id, widget.callbacks!);
      });
    }

    // Phase 8 + multi-lang: wire WS subscriptions and publish the
    // BindingContext so ElementRenderer can pre-resolve config tokens like
    // `{{i18n.x}}` without prop-drilling. Both depend on a non-null context.
    final ctx = widget.bindingContext;
    if (ctx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(bindingContextProvider.notifier)
            .register(widget.page.id, ctx);
      });

      final resolver = ExpressionResolver(ctx);
      _realtime = RealtimeSubscriptionManager(
        adapter: ctx.webSocket,
        resolver: resolver,
        eventBus: ctx.eventBus,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _bindAllSubscriptions();
      });
    }
  }

  Future<void> _bindAllSubscriptions() async {
    final mgr = _realtime;
    if (mgr == null) return;
    for (final el in widget.page.elements) {
      final tpl = el.dataBinding?.subscribe;
      if (tpl == null || tpl.isEmpty) continue;
      final cancel = await mgr.bind(el.id, tpl);
      _subCancellers.add(cancel);
    }
  }

  @override
  void dispose() {
    for (final c in _subCancellers) {
      c();
    }
    _subCancellers.clear();
    _realtime?.dispose();

    // Clean up our entry in the binding-context provider so subsequent
    // renderer instances don't see stale context. Read before super.dispose()
    // — the WidgetRef remains valid during dispose.
    if (widget.bindingContext != null) {
      try {
        ref
            .read(bindingContextProvider.notifier)
            .unregister(widget.page.id);
      } catch (_) {
        // ProviderScope may have been torn down — nothing to clean up.
      }
    }
    if (widget.callbacks != null) {
      try {
        ref
            .read(pageRendererCallbacksProvider.notifier)
            .unregister(widget.page.id);
      } catch (_) {/* scope already gone */}
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Render pages on the canonical unified design tokens (the adopted
    // Mitigation-Tracker design system: navy/teal/light-grey). We install an
    // OPaletteScope from `pdPalette(...)` so descendant elements that read
    // OPaletteScope.of(context) resolve the exact same brand/surface/text as
    // the app chrome (`pd_design_system`). Only the site's brightness is
    // honoured; per-tenant brand overrides can be reintroduced later via
    // `OPaletteData.fromSiteTheme`.
    final brightness = widget.site?.theme.brightness == 'dark'
        ? Brightness.dark
        : Brightness.light;
    final palette =
        OPaletteData.fromPd(pdPalette(PdBrand.restoration, brightness));

    final body = _buildPageBody(widget.page);

    final Widget content = widget.wrapInCanvas
        ? ColoredBox(
            color: palette.bgCanvas,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: OTokens.s8, vertical: OTokens.s8),
                  child: body,
                ),
              ),
            ),
          )
        : body;

    return OPaletteScope(data: palette, child: content);
  }

  Widget _buildPageBody(PageDefinition page) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final section in page.sortedSections)
            _SectionSlot(
              pageId: page.id,
              section: section,
              elements: page.elementsInSection(section.id),
            ),
        ],
      ),
    );
  }
}

/// Wraps a section, rendering it only when it has at least one element visible
/// under the current role + `conditional` rules. This keeps a collapsible
/// section's header (and its bottom spacing) from appearing when every element
/// inside is hidden — e.g. the Reconstruction section on a water-mitigation
/// sub-job, whose elements are all gated on `query.division == reconstruction`.
class _SectionSlot extends ConsumerWidget {
  final String pageId;
  final PageSection section;
  final List<PageElement> elements;

  const _SectionSlot({
    required this.pageId,
    required this.section,
    required this.elements,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(pageContextProvider); // rebuild on role changes
    ref.watch(bindingContextProvider); // rebuild when route/query context lands
    final roles = ref.read(pageContextProvider.notifier);
    final hasVisible = elements.any((el) =>
        roles.isVisibleToRoles(pageId, el.roleVisibility) &&
        conditionalVisible(ref, pageId, el));
    if (!hasVisible) return const SizedBox.shrink();

    final body = _RenderedSection(elements: elements, pageId: pageId);
    final content = section.collapsible
        ? _CollapsibleSection(
            pageId: pageId,
            sectionId: section.id,
            title: section.title,
            startCollapsed: section.collapsed,
            child: body,
          )
        : body;
    return Padding(
      padding: const EdgeInsets.only(bottom: OTokens.s4),
      child: content,
    );
  }
}

/// Renders one section's elements grouped by `rowIndex`, mapping `colWidth`
/// to proportional widths in a 12-column grid.
///
/// Phase 6 of documents/platform/web-builder-roadmap.md: elements declaring `roleVisibility` are
/// hidden when the active session's roles don't intersect that list. The
/// filter consults [pageContextProvider] which the host app seeds via
/// `PageRendererWidget.initialContext` (`session.roles: [...]`).
class _RenderedSection extends ConsumerWidget {
  final List<PageElement> elements;
  final String pageId;

  const _RenderedSection({required this.elements, required this.pageId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (elements.isEmpty) return const SizedBox.shrink();

    // Watch the page-context map so role changes (login, role switch) re-render.
    ref.watch(pageContextProvider);
    final notifier = ref.read(pageContextProvider.notifier);

    // Apply role-visibility filter before grouping into rows. Elements
    // hidden by role check are simply omitted — their grid cell collapses.
    final visible = elements
        .where((el) => notifier.isVisibleToRoles(pageId, el.roleVisibility))
        .toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    final rowMap = <int, List<PageElement>>{};
    for (final el in visible) {
      rowMap.putIfAbsent(el.rowIndex, () => []).add(el);
    }
    final sortedRows = rowMap.keys.toList()..sort();

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final unitWidth = totalWidth / 12;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < sortedRows.length; i++) ...[
              if (i > 0) const SizedBox(height: OTokens.s3),
              _buildGridRow(rowMap[sortedRows[i]]!, unitWidth, totalWidth, pageId),
            ],
          ],
        );
      },
    );
  }

  /// One grid row. Elements are placed left→right by `colWidth`. When a row is
  /// made up entirely of cards (the "Claim & project details" / KPI rows), the
  /// cells are stretched to equal height (tallest wins) so side-by-side cards
  /// line up; mixed rows keep natural top-aligned heights.
  Widget _buildGridRow(
    List<PageElement> els,
    double unitWidth,
    double totalWidth,
    String pageId,
  ) {
    final equalHeight = els.length > 1 &&
        els.every((el) =>
            el.type == PageElementType.card ||
            el.type == PageElementType.statCard);
    final row = Row(
      crossAxisAlignment:
          equalHeight ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: els.map((el) {
        final w = (unitWidth * el.colWidth).clamp(unitWidth, totalWidth);
        return SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OTokens.s1),
            child: ElementRenderer(
              element: el,
              mode: RenderMode.published,
              pageId: pageId,
            ),
          ),
        );
      }).toList(),
    );
    return equalHeight ? IntrinsicHeight(child: row) : row;
  }
}

/// A section rendered as a collapsible card: a clickable header (title +
/// chevron) over an animated body. Each section collapses independently
/// (multiple can be open at once), and the open/closed choice is remembered
/// per user+page+section via [loadUiPref]/[saveUiPref], so the layout persists
/// across reloads. Sections start in [startCollapsed] only when the user has
/// no saved preference yet.
class _CollapsibleSection extends StatefulWidget {
  final String pageId;
  final String sectionId;
  final String title;
  final bool startCollapsed;
  final Widget child;

  const _CollapsibleSection({
    required this.pageId,
    required this.sectionId,
    required this.title,
    required this.startCollapsed,
    required this.child,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _collapsed;

  String get _prefKey => 'sec.collapsed:${widget.pageId}:${widget.sectionId}';

  @override
  void initState() {
    super.initState();
    final stored = loadUiPref(_prefKey);
    _collapsed = stored == null ? widget.startCollapsed : stored == '1';
  }

  void _toggle() {
    setState(() => _collapsed = !_collapsed);
    saveUiPref(_prefKey, _collapsed ? '1' : '0');
  }

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: pal.bgRaised,
        borderRadius: BorderRadius.circular(OTokens.radiusMd),
        border: Border.all(color: pal.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: OTokens.s4, vertical: OTokens.s3),
              child: Row(
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: pal.textBright,
                    ),
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      ref.watch(sectionCountsProvider);
                      final n = ref
                          .read(sectionCountsProvider.notifier)
                          .countFor(widget.pageId, widget.sectionId);
                      if (n == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(left: OTokens.s2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 1),
                          decoration: BoxDecoration(
                            color: pal.primaryBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '$n',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: pal.primaryBlue,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _collapsed ? 0 : 0.5,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.expand_more, color: pal.textMuted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _collapsed
                ? const SizedBox(width: double.infinity, height: 0)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(
                        OTokens.s4, 0, OTokens.s4, OTokens.s4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(height: 1, color: pal.borderSubtle),
                        const SizedBox(height: OTokens.s3),
                        widget.child,
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
