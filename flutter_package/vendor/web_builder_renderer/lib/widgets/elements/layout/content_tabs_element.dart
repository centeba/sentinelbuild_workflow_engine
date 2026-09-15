import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../binding/expression_resolver.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../../page_renderer_widget.dart';
import '../element_renderer.dart';

class ContentTabsElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const ContentTabsElement({
    super.key,
    required this.element,
    required this.mode,
    this.pageId = '',
  });

  @override
  ConsumerState<ContentTabsElement> createState() => _ContentTabsElementState();
}

class _ContentTabsElementState extends ConsumerState<ContentTabsElement> {
  int _activeTab = 0;

  /// Handle a tab tap. If the tab declares a `route`, navigate to that
  /// page (resolving `{{route.id}}` etc. against the page's binding
  /// context) — this is how a project's tab bar jumps between the
  /// Overview / Documents / Compliance pages. Otherwise fall back to
  /// switching in-page content for the legacy content-panel shape.
  void _onTabTap(int i, Map tab) {
    final route = (tab['route'] as String?)?.trim();
    if (route == null || route.isEmpty) {
      setState(() => _activeTab = i);
      return;
    }
    // Navigate to another page — same proven mechanism as ButtonElement:
    // typed callbacks lookup + synchronous token resolution + onNavigate.
    // Prefer the callback registered for this exact page, but FALL BACK to any
    // registered callback — the page id can momentarily mismatch under rebuild
    // churn, and there is normally only one page rendered at a time.
    final cbReg = ref.read(pageRendererCallbacksProvider);
    final rawCb = cbReg[widget.pageId] ??
        (cbReg.values.isNotEmpty ? cbReg.values.first : null);
    if (rawCb is! PageRendererCallbacks) {
      setState(() => _activeTab = i);
      return;
    }
    var target = route;
    final ctxReg = ref.read(bindingContextProvider);
    final bindingCtx = ctxReg[widget.pageId] ??
        (ctxReg.values.isNotEmpty ? ctxReg.values.first : null);
    if (bindingCtx != null && target.contains('{{')) {
      try {
        target =
            ExpressionResolver(bindingCtx).resolveValueSync(target).toString();
      } catch (_) {/* fall back to the raw route */}
    }
    rawCb.onNavigate?.call(target, const <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    final rawTabs = widget.element.config['tabs'];
    final tabs = (rawTabs is List) ? rawTabs.cast<Map>() : <Map>[];
    if (tabs.isEmpty) return const SizedBox.shrink();

    final accent = OPaletteScope.of(context).primaryBlue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Underline tab bar: active tab = brand-coloured text + a thick brand
        // underline; the whole strip has a hairline bottom border.
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: OPaletteScope.of(context).borderSubtle, width: 1),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: tabs.asMap().entries.map((entry) {
                final i = entry.key;
                final tab = entry.value;
                final isActive = i == _activeTab;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onTabTap(i, tab),
                  child: Container(
                    margin: const EdgeInsets.only(right: OTokens.s3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: OTokens.s2, vertical: OTokens.s3),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isActive ? accent : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Text(
                      (tab['title'] as String?) ??
                          (tab['label'] as String?) ??
                          'Tab ${i + 1}',
                      style: GoogleFonts.inter(
                        fontSize: OTokens.textSm,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w600,
                        color: isActive
                            ? accent
                            : OPaletteScope.of(context).textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        const SizedBox(height: OTokens.s5),

        // Active tab content. Two shapes supported:
        //  1. Children-based (preferred): the element has child containers
        //     each with `config.tabId` matching one of the declared tab
        //     ids. We render that container's grandchildren when active.
        //  2. Legacy inline string: `tab.content` text shown as-is.
        //
        // No AnimatedSwitcher here — it wraps the child in a Stack which
        // collapses to zero height inside a Column with MainAxisSize.min,
        // hiding any real content. Plain re-render is fine; transitions
        // can be added later via an explicit AnimatedSize if needed.
        _buildTabBody(tabs, _activeTab),
      ],
    );
  }

  Widget _buildTabBody(List<Map> tabs, int activeIdx) {
    final children = widget.element.children ?? [];
    if (children.isNotEmpty) {
      final activeTabId = tabs[activeIdx]['id'] as String?;
      // Find the child whose config.tabId matches the active tab id. When
      // no child has a tabId at all, treat children as positional and pick
      // by activeIdx. When tabIds are declared but no match exists, show
      // an empty body rather than guessing — surfacing pages that
      // declared a tab without authoring its content.
      PageElement? body;
      final anyHasTabId = children.any((c) => c.config['tabId'] != null);
      if (activeTabId != null && anyHasTabId) {
        for (final c in children) {
          if (c.config['tabId'] == activeTabId) {
            body = c;
            break;
          }
        }
      } else if (!anyHasTabId && activeIdx < children.length) {
        body = children[activeIdx];
      }
      if (body != null) {
        return KeyedSubtree(
          key: ValueKey('tab-body-$activeIdx'),
          child: ElementRenderer(
            element: body,
            mode: widget.mode,
            pageId: widget.pageId,
          ),
        );
      }
      // Tab declared but no matching child container — friendly placeholder.
      return Padding(
        key: ValueKey('tab-empty-$activeIdx'),
        padding: const EdgeInsets.symmetric(vertical: OTokens.s6),
        child: Text(
          'Nothing here yet.',
          style: GoogleFonts.inter(
            fontSize: OTokens.textSm,
            color: OPaletteScope.of(context).textMuted,
          ),
        ),
      );
    }
    return Align(
      key: ValueKey('tab-content-$activeIdx'),
      alignment: Alignment.topLeft,
      child: Text(
        tabs[activeIdx]['content'] as String? ?? '',
        style: GoogleFonts.inter(
          fontSize: OTokens.textSm,
          color: OPaletteScope.of(context).textPrimary,
          height: 1.6,
        ),
      ),
    );
  }
}
