import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../binding/expression_resolver.dart';
import '../../models/page_element.dart';
import '../../models/element_style.dart';
import '../../providers/page_context_provider.dart';
import '../../design/palette.dart';
import '../../design/tokens.dart';
import 'layout/container_element.dart';
import 'layout/row_element.dart';
import 'layout/stack_element.dart';
import 'layout/columns_element.dart';
import 'layout/divider_element.dart';
import 'layout/spacer_element.dart';
import 'layout/card_element.dart';
import 'layout/accordion_element.dart';
import 'layout/content_tabs_element.dart';
import 'layout/callout_element.dart';
import 'content/text_element.dart';
import 'content/heading_element.dart';
import 'content/image_element.dart';
import 'content/icon_element.dart';
import 'content/badge_element.dart';
import 'content/bullet_list_element.dart';
import 'content/ordered_list_element.dart';
import 'content/blockquote_element.dart';
import 'content/rich_text_element.dart';
import 'content/video_element.dart';
import 'interactive/button_element.dart';
import 'interactive/link_element.dart';
import 'interactive/nav_tabs_element.dart';
import 'interactive/progress_bar_element.dart';
import 'interactive/stepper_element.dart';
import 'interactive/breadcrumbs_element.dart';
import 'interactive/timeline_element.dart';
import 'data/data_fetch.dart';
import 'data/stat_card_element.dart';
import 'data/data_table_element.dart';
import 'data/chart_element.dart';
import 'data/list_element.dart';
import 'data/api_text_element.dart';
import 'data/gauge_chart_element.dart';
import 'data/gantt_chart_element.dart';
import 'data/kanban_element.dart';
import 'data/heatmap_element.dart';
import 'data/waterfall_chart_element.dart';
import 'data/candlestick_element.dart';
import 'data/sparkline_element.dart';
import 'form/form_element.dart';
import 'form/text_field_element.dart';
import 'form/text_area_element.dart';
import 'form/email_field_element.dart';
import 'form/phone_field_element.dart';
import 'form/dropdown_element.dart';
import 'form/checkbox_element.dart';
import 'form/checkbox_group_element.dart';
import 'form/select_field_element.dart';
import 'form/checkbox_field_element.dart';
import 'form/radio_group_element.dart';
import 'form/number_field_element.dart';
import 'form/switch_field_element.dart';
import 'form/date_picker_element.dart';
import 'form/file_upload_element.dart';
import 'form/range_slider_element.dart';
import 'form/multi_select_element.dart';
import 'form/tags_input_element.dart';
import 'form/search_field_element.dart';
import 'form/password_field_element.dart';
import 'form/signature_pad_element.dart';
import 'form/form_submit_button_element.dart';
import 'form/honeypot_element.dart';
import 'form/currency_field_element.dart';
import 'form/url_field_element.dart';
import 'form/time_field_element.dart';
import 'form/date_time_field_element.dart';
import 'form/rating_element.dart';
import 'form/hidden_field_element.dart';
import 'form/data_grid_element.dart';
import 'form/computed_element.dart';
enum RenderMode { builder, preview, published }

/// Signature for a custom element builder. Pass-by-position to keep the
/// registry call site terse: `(element, mode, pageId) => MyWidget(...)`.
typedef ExternalElementBuilder = Widget Function(
    PageElement element, RenderMode mode, String pageId);

/// Registry for `PageElementType`s whose widgets live outside this package.
///
/// The renderer's switch handles the core 40+ types directly. Anything else —
/// SentinelBuild widgets, vertical-app-specific widgets, future Phase 4
/// additions like `treeView`/`multiStepForm` — registers here. The wildcard
/// branch in [ElementRenderer]'s switch consults this registry.
///
/// Call [register] once at app startup, before any [ElementRenderer] is built.
/// See `package:sentinelbuild_elements/sentinelbuild_elements.dart` for an
/// example of registering a batch of types.
class ElementRegistry {
  ElementRegistry._();
  static final Map<PageElementType, ExternalElementBuilder> _builders = {};

  static void register(PageElementType type, ExternalElementBuilder builder) {
    _builders[type] = builder;
  }

  static ExternalElementBuilder? lookup(PageElementType type) =>
      _builders[type];

  /// Test-only: clear registrations between tests so they don't bleed across.
  @visibleForTesting
  static void clear() => _builders.clear();
}

class ElementRenderer extends ConsumerWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const ElementRenderer({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pre-resolve any `{{...}}` tokens (`{{i18n.x}}`, `{{session.user.email}}`,
    // etc.) in the element's `config` map so leaf widgets — which read raw
    // strings — never see template placeholders. We only do this when a
    // BindingContext is registered for the active page; otherwise the
    // legacy raw-config path is preserved verbatim.
    final pal = OPaletteScope.of(context);
    final resolvedElement = _withResolvedConfig(ref, element);
    // Evaluate optional show/hide rule against the page context. Author
    // syntax (from form-builder JSON): `{action: 'show'|'hide', combinator:
    // 'and'|'or', conditions: [{field, operator, value}]}`. Falsy →
    // SizedBox.shrink() so the element vanishes entirely.
    if (!_isConditionallyVisible(ref, resolvedElement)) {
      return const SizedBox.shrink();
    }

    // If the element has a dataBinding AND its config contains
    // `{{response.X}}` tokens, fetch the binding once and substitute
    // before rendering. This lets heading/text/badge etc. show real
    // bound data without each widget needing its own data-binding
    // implementation. Widgets that already handle their own dataBinding
    // (statCard, list, kanban, etc.) check for the same tokens
    // themselves; substituting here too is harmless (no-op when nothing
    // matches).
    if (_needsResponseSubstitution(resolvedElement)) {
      return _BoundConfigWrapper(
        element: resolvedElement,
        pageId: pageId,
        builder: (substituted) {
          Widget content = _buildContent(context, ref, substituted);
          content = _applyStyle(
              content, substituted.type.name, substituted.style, pal);
          return content;
        },
      );
    }

    Widget content = _buildContent(context, ref, resolvedElement);
    content =
        _applyStyle(content, resolvedElement.type.name, resolvedElement.style, pal);

    // If this element's dataBinding declares refreshOn events, wrap it so
    // the subtree rebuilds (and any FutureBuilder inside re-runs its
    // fetch) whenever one of those events fires on the page's EventBus.
    // Widgets that already manage their own refresh (kanban, statCard,
    // etc. — they call bindRefreshOn directly) ignore this wrapper's
    // re-key because their FutureBuilder keys off their own tick.
    final refreshOn = resolvedElement.dataBinding?.refreshOn ?? const [];
    if (refreshOn.isNotEmpty) {
      content = _RefreshOnWrapper(
        pageId: pageId,
        element: resolvedElement,
        child: content,
      );
    }
    return content;
  }

  /// True when this element has a dataBinding AND its config (or style)
  /// contains a `{{response.X}}` token that needs the fetched body to
  /// resolve.
  bool _needsResponseSubstitution(PageElement el) {
    if (el.dataBinding == null) return false;
    bool walk(dynamic node) {
      if (node is String) return node.contains('{{response.');
      if (node is Map) return node.values.any(walk);
      if (node is List) return node.any(walk);
      return false;
    }
    return walk(el.config);
  }

  /// Evaluate `element.conditional` against the page's current session /
  /// form / route / element context. Returns true (visible) when no
  /// conditional is set OR the rule passes.
  bool _isConditionallyVisible(WidgetRef ref, PageElement el) {
    final cond = el.conditional;
    if (cond == null || cond.isEmpty) return true;
    final action = (cond['action'] as String?) ?? 'show';
    final combinator = (cond['combinator'] as String?) ?? 'and';
    final conditions = cond['conditions'];
    if (conditions is! List || conditions.isEmpty) return true;

    // Pull readable context from registered providers.
    final ctxMap = ref.read(bindingContextProvider);
    final ctx = ctxMap[pageId];
    final session = ctx?.session ?? const {};
    final formValues = ctx?.formValues ?? const {};
    final route = ctx?.routeParams ?? const {};
    final query = ctx?.queryParams ?? const {};
    final elementValues = ctx?.elementValues ?? const {};

    bool eval(Map cnd) {
      final field = cnd['field'] as String? ?? '';
      final operator = cnd['operator'] as String? ?? 'equals';
      final expected = cnd['value'];
      final actual = _lookup(
        field,
        session: session,
        form: formValues,
        route: route,
        query: query,
        element: elementValues,
      );
      return _applyOperator(actual, operator, expected);
    }

    final results = conditions.map((c) => c is Map ? eval(c) : false);
    final passes = combinator == 'or'
        ? results.any((b) => b)
        : results.every((b) => b);
    return action == 'hide' ? !passes : passes;
  }

  dynamic _lookup(
    String dotted, {
    required Map<String, dynamic> session,
    required Map<String, dynamic> form,
    required Map<String, dynamic> route,
    required Map<String, dynamic> query,
    required Map<String, dynamic> element,
  }) {
    final parts = dotted.split('.');
    if (parts.isEmpty) return null;
    dynamic current = switch (parts.first) {
      'session' => session,
      'form' => form,
      'route' => route,
      'query' => query,
      'element' => element,
      _ => null,
    };
    for (final p in parts.skip(1)) {
      if (current is Map) {
        current = current[p];
      } else {
        return null;
      }
    }
    return current;
  }

  bool _applyOperator(dynamic actual, String op, dynamic expected) {
    switch (op) {
      case 'equals':
      case '==':
        return '$actual' == '$expected';
      case 'not_equals':
      case '!=':
        return '$actual' != '$expected';
      case 'empty':
        if (actual == null) return true;
        if (actual is String) return actual.isEmpty;
        if (actual is Iterable) return actual.isEmpty;
        if (actual is Map) return actual.isEmpty;
        return false;
      case 'not_empty':
        return !_applyOperator(actual, 'empty', null);
      case 'contains':
        if (actual is String) return actual.contains('$expected');
        if (actual is Iterable) return actual.contains(expected);
        return false;
      case 'in':
        if (expected is Iterable) return expected.contains(actual);
        return false;
      default:
        return false;
    }
  }

  /// Walk [el]'s config map and substitute `{{...}}` tokens via the active
  /// [BindingContext] (if any). Returns a new [PageElement] with the
  /// resolved config; unresolved tokens are preserved verbatim so designers
  /// can spot misses.
  PageElement _withResolvedConfig(WidgetRef ref, PageElement el) {
    final ctxMap = ref.watch(bindingContextProvider);
    final ctx = ctxMap[pageId];
    if (ctx == null) return el;
    if (el.config.isEmpty) return el;

    final resolver = ExpressionResolver(ctx);
    final resolved = _resolveMap(el.config, resolver);
    if (identical(resolved, el.config)) return el;
    return el.copyWith(config: resolved);
  }

  /// Recursively resolve string tokens in a config map. Returns the same
  /// instance when no substitutions happened, so `_withResolvedConfig`
  /// can short-circuit on no-op pages.
  static Map<String, dynamic> _resolveMap(
      Map<String, dynamic> input, ExpressionResolver resolver) {
    Map<String, dynamic>? out;
    input.forEach((k, v) {
      final replaced = _resolveAny(v, resolver);
      if (!identical(replaced, v)) {
        out ??= Map<String, dynamic>.from(input);
        out![k] = replaced;
      }
    });
    return out ?? input;
  }

  static dynamic _resolveAny(dynamic v, ExpressionResolver resolver) {
    if (v is String) {
      if (!v.contains('{{')) return v;
      try {
        final out = resolver.resolveValueSync(v);
        return out ?? v;
      } catch (_) {
        return v; // async-only token (e.g. `api.*`) — leave for the widget
      }
    }
    if (v is List) {
      List<dynamic>? changed;
      for (var i = 0; i < v.length; i++) {
        final r = _resolveAny(v[i], resolver);
        if (!identical(r, v[i])) {
          changed ??= List<dynamic>.from(v);
          changed[i] = r;
        }
      }
      return changed ?? v;
    }
    if (v is Map<String, dynamic>) {
      return _resolveMap(v, resolver);
    }
    return v;
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, PageElement element) {
    return switch (element.type) {
      PageElementType.container =>
        ContainerElement(element: element, mode: mode, pageId: pageId),
      PageElementType.row =>
        RowElement(element: element, mode: mode, pageId: pageId),
      PageElementType.stack =>
        StackElement(element: element, mode: mode, pageId: pageId),
      PageElementType.columns =>
        ColumnsElement(element: element, mode: mode, pageId: pageId),
      PageElementType.divider =>
        DividerElement(element: element),
      PageElementType.spacer =>
        SpacerElement(element: element),
      PageElementType.card =>
        CardElement(element: element, mode: mode, pageId: pageId),
      PageElementType.accordion =>
        AccordionElement(element: element, mode: mode),
      PageElementType.contentTabs =>
        ContentTabsElement(element: element, mode: mode, pageId: pageId),
      PageElementType.callout =>
        CalloutElement(element: element, mode: mode),
      PageElementType.text =>
        TextElement(element: element),
      PageElementType.heading =>
        HeadingElement(element: element),
      PageElementType.image =>
        ImageElement(element: element),
      PageElementType.icon =>
        IconElement(element: element),
      PageElementType.badge =>
        BadgeElement(element: element),
      PageElementType.bulletList =>
        BulletListElement(element: element, mode: mode),
      PageElementType.orderedList =>
        OrderedListElement(element: element, mode: mode),
      PageElementType.blockquote =>
        BlockquoteElement(element: element, mode: mode),
      PageElementType.richText =>
        RichTextElement(element: element, mode: mode),
      PageElementType.video =>
        VideoElement(element: element, mode: mode),
      PageElementType.button =>
        ButtonElement(element: element, mode: mode, pageId: pageId),
      PageElementType.link =>
        LinkElement(element: element, mode: mode, pageId: pageId),
      PageElementType.navTabs =>
        NavTabsElement(element: element, mode: mode, pageId: pageId),
      PageElementType.progressBar =>
        ProgressBarElement(element: element, mode: mode),
      PageElementType.stepper =>
        StepperElement(element: element, mode: mode, pageId: pageId),
      PageElementType.breadcrumbs =>
        BreadcrumbsElement(element: element, mode: mode),
      PageElementType.timeline =>
        TimelineElement(element: element, mode: mode),
      PageElementType.statCard =>
        StatCardElement(element: element, mode: mode, pageId: pageId),
      PageElementType.dataTable =>
        DataTableElement(element: element, mode: mode, pageId: pageId),
      PageElementType.chart =>
        ChartElement(element: element, mode: mode, pageId: pageId),
      PageElementType.list =>
        ListElement(element: element, mode: mode, pageId: pageId),
      PageElementType.apiText =>
        ApiTextElement(element: element, mode: mode, pageId: pageId),
      PageElementType.gaugeChart =>
        GaugeChartElement(element: element, mode: mode, pageId: pageId),
      PageElementType.ganttChart =>
        GanttChartElement(element: element, mode: mode),
      PageElementType.kanban =>
        KanbanElement(element: element, mode: mode, pageId: pageId),
      PageElementType.heatmap =>
        HeatmapElement(element: element, mode: mode),
      PageElementType.waterfallChart =>
        WaterfallChartElement(element: element, mode: mode),
      PageElementType.candlestick =>
        CandlestickElement(element: element, mode: mode),
      PageElementType.sparkline =>
        SparklineElement(element: element, mode: mode),
      PageElementType.form =>
        FormElement(element: element, mode: mode, pageId: pageId),
      PageElementType.textField =>
        TextFieldElement(element: element, mode: mode),
      PageElementType.textArea =>
        TextAreaElement(element: element, mode: mode),
      PageElementType.selectField =>
        SelectFieldElement(element: element, mode: mode, pageId: pageId),
      PageElementType.checkboxField =>
        CheckboxFieldElement(element: element, mode: mode),
      PageElementType.radioGroup =>
        RadioGroupElement(element: element, mode: mode),
      PageElementType.numberField =>
        NumberFieldElement(element: element, mode: mode),
      PageElementType.switchField =>
        SwitchFieldElement(element: element, mode: mode),
      PageElementType.datePicker =>
        DatePickerElement(element: element, mode: mode),
      PageElementType.fileUpload =>
        FileUploadElement(element: element, mode: mode, pageId: pageId),
      PageElementType.rangeSlider =>
        RangeSliderElement(element: element, mode: mode),
      PageElementType.multiSelect =>
        MultiSelectElement(element: element, mode: mode, pageId: pageId),
      PageElementType.tagsInput =>
        TagsInputElement(element: element, mode: mode),
      PageElementType.searchField =>
        SearchFieldElement(element: element, mode: mode),
      PageElementType.passwordField =>
        PasswordFieldElement(element: element, mode: mode),
      // New form field types
      PageElementType.emailField =>
        EmailFieldElement(element: element, mode: mode),
      PageElementType.phoneField =>
        PhoneFieldElement(element: element, mode: mode),
      PageElementType.dropdown =>
        DropdownElement(element: element, mode: mode, pageId: pageId),
      PageElementType.checkbox =>
        CheckboxElement(element: element, mode: mode),
      PageElementType.checkboxGroup =>
        CheckboxGroupElement(element: element, mode: mode),
      PageElementType.signaturePad =>
        SignaturePadElement(element: element, mode: mode),
      PageElementType.formSubmitButton =>
        FormSubmitButtonElement(element: element, mode: mode),
      PageElementType.honeypot => HoneypotElement(element: element),
      // Form parity additions
      PageElementType.currency =>
        CurrencyFieldElement(element: element, mode: mode),
      PageElementType.urlField =>
        UrlFieldElement(element: element, mode: mode),
      PageElementType.timeField =>
        TimeFieldElement(element: element, mode: mode),
      PageElementType.dateTimeField =>
        DateTimeFieldElement(element: element, mode: mode),
      PageElementType.rating =>
        RatingElement(element: element, mode: mode),
      PageElementType.hiddenField =>
        HiddenFieldElement(element: element, mode: mode),
      PageElementType.dataGrid =>
        DataGridElement(element: element, mode: mode, pageId: pageId),
      // workspacePanel is restoration-domain — its builder is registered by the
      // restoration app via ElementRegistry, so it falls through to the
      // external-dispatch branch below (keeps domain widgets out of this pkg).
      PageElementType.computed =>
        ComputedElement(element: element, mode: mode),
      // External element types — SentinelBuild widgets, future Phase 4 adds,
      // and any vertical-app extensions register via [ElementRegistry].
      _ => _externalDispatch(element),
    };
  }

  Widget _externalDispatch(PageElement element) {
    final builder = ElementRegistry.lookup(element.type);
    if (builder != null) return builder(element, mode, pageId);
    return _UnregisteredElement(type: element.type);
  }

  Widget _applyStyle(
      Widget child, String type, ElementStyle? style, OPaletteData pal) {
    if (style == null) return child;

    Widget result = child;

    // statCard/card paint their own clean surface (and use the page-authored
    // backgroundColor only to derive an accent). Skipping the wrapper bg/border
    // here stops the old tinted backing panel from showing around them.
    final selfPaints = type == 'statCard' || type == 'card';

    if (style.opacity != null && style.opacity != 1.0) {
      result = Opacity(opacity: style.opacity!.clamp(0.0, 1.0), child: result);
    }

    final hasPadding = style.paddingTop != null ||
        style.paddingBottom != null ||
        style.paddingLeft != null ||
        style.paddingRight != null;
    final hasMargin = style.marginTop != null ||
        style.marginBottom != null ||
        style.marginLeft != null ||
        style.marginRight != null;
    final bg = style.resolvedBackgroundColor(pal);
    final borderColor = style.resolvedBorderColor(pal);
    final hasBg = bg != null && !selfPaints;
    final hasBorder = borderColor != null &&
        (style.borderWidth ?? 0) > 0 &&
        !selfPaints;
    final hasBorderRadius = style.borderRadius != null;
    final hasSizing = style.width != null || style.height != null || style.minHeight != null;

    if (hasBg || hasBorder || hasBorderRadius || hasPadding || hasSizing) {
      result = Container(
        width: style.width,
        height: style.height,
        constraints: style.minHeight != null
            ? BoxConstraints(minHeight: style.minHeight!)
            : null,
        padding: hasPadding ? style.padding : null,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: hasBorderRadius
              ? BorderRadius.circular(style.borderRadius!)
              : null,
          border: hasBorder
              ? Border.all(
                  color: borderColor,
                  width: style.borderWidth ?? 1,
                )
              : null,
        ),
        child: result,
      );
    }

    if (hasMargin) {
      result = Padding(padding: style.margin, child: result);
    }

    return result;
  }
}

// Placeholder used during builder mode for elements with no content yet
class ElementPlaceholder extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const ElementPlaceholder({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: OTokens.s4, horizontal: OTokens.s4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(OTokens.radiusSm),
        border: Border.all(
            color: color.withValues(alpha: 0.2),
            style: BorderStyle.solid),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.withValues(alpha: 0.6)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: OTokens.textXs,
              color: color.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder shown when a `PageElementType` is encountered that has no
/// registered builder. The fix is to call the relevant
/// `register…Elements()` function at app startup.
class _UnregisteredElement extends StatelessWidget {
  final PageElementType type;
  const _UnregisteredElement({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(OTokens.s3),
      decoration: BoxDecoration(
        color: OPaletteScope.of(context).warningAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(OTokens.radiusSm),
        border: Border.all(
            color: OPaletteScope.of(context).warningAmber.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Unregistered element type: ${type.name}\n'
        'Did you forget to call register…Elements() at app startup?',
        style: TextStyle(
          fontSize: OTokens.textXs,
          color: OPaletteScope.of(context).warningAmber,
        ),
      ),
    );
  }
}

// ── Response-token wrapper ──────────────────────────────────────────────
//
// When an element declares a dataBinding AND its config contains
// `{{response.X}}` tokens (e.g. a heading's `text: "{{response.title}}"`),
// we wrap the element render in this widget. It fetches the binding
// once, walks the config map substituting tokens, then passes the
// substituted element to a builder that knows how to render it. Also
// subscribes to `dataBinding.refreshOn` so writes elsewhere on the page
// invalidate + re-fetch transparently.

class _BoundConfigWrapper extends ConsumerStatefulWidget {
  final PageElement element;
  final String pageId;
  final Widget Function(PageElement substituted) builder;

  const _BoundConfigWrapper({
    required this.element,
    required this.pageId,
    required this.builder,
  });

  @override
  ConsumerState<_BoundConfigWrapper> createState() =>
      _BoundConfigWrapperState();
}

class _BoundConfigWrapperState extends ConsumerState<_BoundConfigWrapper> {
  void Function()? _cancelRefresh;
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    final binding = widget.element.dataBinding;
    if (binding == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = ref.read(bindingContextProvider)[widget.pageId];
      if (ctx == null) return;
      _cancelRefresh =
          bindRefreshOn(ctx, binding, () async {
        if (mounted) setState(() => _refreshTick++);
      });
    });
  }

  @override
  void dispose() {
    _cancelRefresh?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final binding = widget.element.dataBinding;
    final ctxMap = ref.watch(bindingContextProvider);
    final ctx = ctxMap[widget.pageId];
    if (binding == null || ctx == null) {
      // No context yet → render the element as-is (tokens visible);
      // BindingContext registration is post-frame so this only flashes.
      return widget.builder(widget.element);
    }
    return FutureBuilder<dynamic>(
      key: ValueKey('bound-${widget.element.id}-$_refreshTick'),
      future: fetchBindingBody(ctx, binding),
      builder: (_, snap) {
        final body = snap.data;
        final substituted = _substituteResponseTokens(widget.element, body);
        return widget.builder(substituted);
      },
    );
  }

  /// Walks the element's config + style maps, substituting any
  /// `{{response.<dotted.path>}}` tokens with values from [body]. Returns
  /// a new PageElement (the existing one is unchanged so caching upstream
  /// isn't disturbed). When the body is null (loading / error), tokens
  /// are replaced with empty strings so the UI doesn't show ugly braces.
  PageElement _substituteResponseTokens(PageElement el, dynamic body) {
    String sub(String s) {
      return s.replaceAllMapped(RegExp(r'\{\{response\.([^}]+)\}\}'), (m) {
        if (body == null) return '';
        final path = m.group(1)!.split('.');
        dynamic current = body;
        for (final p in path) {
          if (current is Map) {
            current = current[p];
          } else {
            return '';
          }
        }
        return current == null ? '' : '$current';
      });
    }

    dynamic walk(dynamic node) {
      if (node is String) return sub(node);
      if (node is Map) {
        // Explicit typed map to avoid Dart inferring Map<dynamic,dynamic>
        // through the recursive dynamic return type — a downstream cast
        // to Map<String, dynamic> would otherwise blow up at runtime.
        final out = <String, dynamic>{};
        for (final e in node.entries) {
          out['${e.key}'] = walk(e.value);
        }
        return out;
      }
      if (node is List) return node.map(walk).toList();
      return node;
    }

    final walked = walk(el.config);
    final newConfig = walked is Map<String, dynamic>
        ? walked
        : walked is Map
            ? Map<String, dynamic>.from(walked)
            : <String, dynamic>{};
    return PageElement(
      id: el.id,
      type: el.type,
      sectionId: el.sectionId,
      rowIndex: el.rowIndex,
      colWidth: el.colWidth,
      config: newConfig,
      style: el.style,
      dataBinding: el.dataBinding,
      conditional: el.conditional,
      responsive: el.responsive,
      children: el.children,
      action: el.action,
      roleVisibility: el.roleVisibility,
    );
  }
}

// ── refreshOn wrapper ──────────────────────────────────────────────────
//
// Generic subtree-rebuild wrapper. Subscribes to events listed in the
// element's `dataBinding.refreshOn`; on any emit, invalidates every
// registered HttpDataSource cache and re-keys the child so its build()
// reruns and any FutureBuilder inside re-fetches.

class _RefreshOnWrapper extends ConsumerStatefulWidget {
  final String pageId;
  final PageElement element;
  final Widget child;

  const _RefreshOnWrapper({
    required this.pageId,
    required this.element,
    required this.child,
  });

  @override
  ConsumerState<_RefreshOnWrapper> createState() => _RefreshOnWrapperState();
}

class _RefreshOnWrapperState extends ConsumerState<_RefreshOnWrapper> {
  void Function()? _cancel;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    final binding = widget.element.dataBinding;
    if (binding == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = ref.read(bindingContextProvider)[widget.pageId];
      if (ctx == null) return;
      _cancel = bindRefreshOn(ctx, binding, () async {
        if (mounted) setState(() => _tick++);
      });
    });
  }

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('refresh-${widget.element.id}-$_tick'),
      child: widget.child,
    );
  }
}

/// Standalone evaluation of an element's `conditional` visibility against the
/// page's session/form/route/query context. Mirrors ElementRenderer's
/// per-element check, exposed at top level so the page body can decide whether
/// a section has ANY visible content — e.g. don't render a collapsible
/// section's header when every element inside is conditionally hidden (a
/// Reconstruction section on a water-mitigation sub-job).
bool conditionalVisible(WidgetRef ref, String pageId, PageElement el) {
  final cond = el.conditional;
  if (cond == null || cond.isEmpty) return true;
  final action = (cond['action'] as String?) ?? 'show';
  final combinator = (cond['combinator'] as String?) ?? 'and';
  final conditions = cond['conditions'];
  if (conditions is! List || conditions.isEmpty) return true;

  final ctx = ref.read(bindingContextProvider)[pageId];
  final session = ctx?.session ?? const <String, dynamic>{};
  final form = ctx?.formValues ?? const <String, dynamic>{};
  final route = ctx?.routeParams ?? const <String, dynamic>{};
  final query = ctx?.queryParams ?? const <String, dynamic>{};
  final element = ctx?.elementValues ?? const <String, dynamic>{};

  dynamic lookup(String dotted) {
    final parts = dotted.split('.');
    if (parts.isEmpty) return null;
    dynamic cur = switch (parts.first) {
      'session' => session,
      'form' => form,
      'route' => route,
      'query' => query,
      'element' => element,
      _ => null,
    };
    for (final p in parts.skip(1)) {
      if (cur is Map) {
        cur = cur[p];
      } else {
        return null;
      }
    }
    return cur;
  }

  bool apply(dynamic actual, String op, dynamic expected) {
    switch (op) {
      case 'equals':
      case '==':
        return '$actual' == '$expected';
      case 'not_equals':
      case '!=':
        return '$actual' != '$expected';
      case 'empty':
        if (actual == null) return true;
        if (actual is String) return actual.isEmpty;
        if (actual is Iterable) return actual.isEmpty;
        if (actual is Map) return actual.isEmpty;
        return false;
      case 'not_empty':
        return !apply(actual, 'empty', null);
      case 'contains':
        if (actual is String) return actual.contains('$expected');
        if (actual is Iterable) return actual.contains(expected);
        return false;
      case 'in':
        if (expected is Iterable) return expected.contains(actual);
        return false;
      default:
        return false;
    }
  }

  bool eval(Map c) => apply(
        lookup(c['field'] as String? ?? ''),
        c['operator'] as String? ?? 'equals',
        c['value'],
      );

  final results = conditions.map((c) => c is Map ? eval(c) : false);
  final passes =
      combinator == 'or' ? results.any((b) => b) : results.every((b) => b);
  return action == 'hide' ? !passes : passes;
}
