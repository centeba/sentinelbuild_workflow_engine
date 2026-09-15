import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:web_builder_renderer/web_builder_renderer.dart';
import '../services/site_storage_service.dart';

const _uuid = Uuid();

/// Pre-built lookup of default configs from the element registry.
/// Used by [PageBuilderNotifier._defaultConfigFor] to seed new elements
/// with sensible initial values rather than empty `{}` configs.
final Map<PageElementType, Map<String, dynamic>> _kDefaultConfigs = {
  for (final meta in kElementRegistry) meta.type: meta.defaultConfig,
};

class PageBuilderState {
  final SiteDefinition site;
  final String activePageId;
  final String? selectedElementId;
  final bool saving;
  final List<SiteDefinition> undoStack;
  final int undoPointer;

  const PageBuilderState({
    required this.site,
    required this.activePageId,
    this.selectedElementId,
    this.saving = false,
    this.undoStack = const [],
    this.undoPointer = -1,
  });

  PageBuilderState copyWith({
    SiteDefinition? site,
    String? activePageId,
    Object? selectedElementId = _sentinel,
    bool? saving,
    List<SiteDefinition>? undoStack,
    int? undoPointer,
  }) {
    return PageBuilderState(
      site: site ?? this.site,
      activePageId: activePageId ?? this.activePageId,
      selectedElementId: identical(selectedElementId, _sentinel)
          ? this.selectedElementId
          : selectedElementId as String?,
      saving: saving ?? this.saving,
      undoStack: undoStack ?? this.undoStack,
      undoPointer: undoPointer ?? this.undoPointer,
    );
  }

  PageDefinition? get activePage {
    try {
      return site.pages.firstWhere((p) => p.id == activePageId);
    } catch (_) {
      return null;
    }
  }

  PageElement? get selectedElement {
    if (selectedElementId == null || activePage == null) return null;
    return _findInTree(activePage!.elements, selectedElementId!);
  }

  static PageElement? _findInTree(List<PageElement> elements, String id) {
    for (final el in elements) {
      if (el.id == id) return el;
      if (el.children != null && el.children!.isNotEmpty) {
        final found = _findInTree(el.children!, id);
        if (found != null) return found;
      }
    }
    return null;
  }
}

const _sentinel = Object();

class PageBuilderNotifier extends Notifier<PageBuilderState> {
  // Resolved on first use from the Riverpod scope so the host app can
  // override [siteStorageProvider] with a [RemoteSiteStorage] (the
  // SentinelBuild chassis does this so saves go to pages-api instead
  // of the designer's SharedPreferences).
  SiteStorage get _storage => ref.read(siteStorageProvider);

  @override
  PageBuilderState build() {
    final site = SiteDefinition(
      id: _uuid.v4(),
      name: 'Untitled Site',
      slug: 'untitled',
    );
    return PageBuilderState(
      site: site,
      activePageId: '',
    );
  }

  void loadSite(SiteDefinition site) {
    final firstPageId =
        site.pages.isNotEmpty ? site.sortedPages.first.id : '';
    state = PageBuilderState(
      site: site,
      activePageId: firstPageId,
    );
  }

  void setSiteName(String name) {
    _pushUndo();
    state = state.copyWith(site: state.site.copyWith(name: name));
  }

  void setSiteSlug(String slug) {
    _pushUndo();
    state = state.copyWith(site: state.site.copyWith(slug: slug));
  }

  // --- Pages ---

  void addPage({String? title}) {
    _pushUndo();
    final id = _uuid.v4();
    final order = state.site.pages.length;
    final defaultSection = PageSection(
      id: _uuid.v4(),
      pageId: id,
      title: 'Section 1',
      order: 0,
    );
    final newPage = PageDefinition(
      id: id,
      title: title ?? 'Page ${order + 1}',
      slug: 'page-${order + 1}',
      order: order,
      sections: [defaultSection],
    );
    final updatedPages = [...state.site.pages, newPage];
    state = state.copyWith(
      site: state.site.copyWith(pages: updatedPages),
      activePageId: id,
    );
  }

  void renamePage(String pageId, String title) {
    _pushUndo();
    _updatePage(pageId, (p) => p.copyWith(title: title));
  }

  /// Append a fully-formed PageDefinition (e.g. from the AI generator)
  /// to the active site as a new page. Re-stamps every id (page,
  /// sections, elements, params) with fresh UUIDs so two appends of the
  /// same generated page don't collide. Sets the new page active.
  void appendGeneratedPage(PageDefinition generated) {
    _pushUndo();
    final stamped = _restampIds(generated, order: state.site.pages.length);
    final updatedPages = [...state.site.pages, stamped];
    state = state.copyWith(
      site: state.site.copyWith(pages: updatedPages),
      activePageId: stamped.id,
      selectedElementId: null,
    );
  }

  /// Replace the currently-active page with a freshly generated one,
  /// preserving the old page's id + slug + order so existing links stay
  /// valid. Element ids are re-stamped (the old elements are gone).
  void replaceActivePage(PageDefinition generated) {
    final active = state.activePage;
    if (active == null) {
      // No active page — fall back to append.
      appendGeneratedPage(generated);
      return;
    }
    _pushUndo();
    // Restamp element + section ids but keep the page id/slug/order.
    final stamped = _restampIds(generated, order: active.order)
        .copyWith(id: active.id, slug: active.slug);
    final updatedPages =
        state.site.pages.map((p) => p.id == active.id ? stamped : p).toList();
    state = state.copyWith(
      site: state.site.copyWith(pages: updatedPages),
      activePageId: stamped.id,
      selectedElementId: null,
    );
  }

  /// Re-stamp every id inside a generated PageDefinition with fresh UUIDs.
  /// Section / element / child references are rewritten so the tree
  /// remains internally consistent.
  PageDefinition _restampIds(PageDefinition src, {required int order}) {
    final newPageId = _uuid.v4();
    final sectionIdMap = <String, String>{};
    final newSections = src.sections.map((s) {
      final newId = _uuid.v4();
      sectionIdMap[s.id] = newId;
      return s.copyWith(id: newId, pageId: newPageId);
    }).toList();

    PageElement restampElement(PageElement el) {
      final newId = _uuid.v4();
      final newSectionId = el.sectionId == null
          ? null
          : (sectionIdMap[el.sectionId!] ?? el.sectionId);
      final newChildren = el.children?.map(restampElement).toList();
      return el.copyWith(
        id: newId,
        sectionId: newSectionId,
        children: newChildren,
      );
    }

    final newElements = src.elements.map(restampElement).toList();

    return src.copyWith(
      id: newPageId,
      order: order,
      sections: newSections,
      elements: newElements,
    );
  }

  /// Phase 5 + 6 page-level visibility / anti-abuse settings.
  /// Pass null to leave a field unchanged; pass an explicit map / list / bool
  /// to overwrite. The renderer + remote storage forward these to pages-api.
  void updatePagePublishSettings(
    String pageId, {
    bool? publicAccess,
    Map<String, dynamic>? rateLimits,
    Map<String, dynamic>? captchaConfig,
    Map<String, dynamic>? submissionConfig,
    List<String>? roleVisibility,
    bool clearRateLimits = false,
    bool clearCaptchaConfig = false,
    bool clearSubmissionConfig = false,
    bool clearRoleVisibility = false,
  }) {
    _pushUndo();
    _updatePage(pageId, (p) {
      return p.copyWith(
        publicAccess: publicAccess ?? p.publicAccess,
        rateLimits: clearRateLimits
            ? null
            : (rateLimits ?? p.rateLimits),
        captchaConfig: clearCaptchaConfig
            ? null
            : (captchaConfig ?? p.captchaConfig),
        submissionConfig: clearSubmissionConfig
            ? null
            : (submissionConfig ?? p.submissionConfig),
        roleVisibility: clearRoleVisibility
            ? null
            : (roleVisibility ?? p.roleVisibility),
      );
    });
  }

  void deletePage(String pageId) {
    _pushUndo();
    final updatedPages =
        state.site.pages.where((p) => p.id != pageId).toList();
    final newActiveId = updatedPages.isNotEmpty
        ? updatedPages.first.id
        : '';
    state = state.copyWith(
      site: state.site.copyWith(pages: updatedPages),
      activePageId: newActiveId,
      selectedElementId: null,
    );
  }

  void setActivePage(String pageId) {
    state = state.copyWith(
        activePageId: pageId, selectedElementId: null);
  }

  // --- Sections ---

  void addSection({String? title}) {
    _pushUndo();
    final page = state.activePage;
    if (page == null) return;
    final order = page.sections.length;
    final section = PageSection(
      id: _uuid.v4(),
      pageId: page.id,
      title: title ?? 'Section ${order + 1}',
      order: order,
    );
    _updatePage(page.id,
        (p) => p.copyWith(sections: [...p.sections, section]));
  }

  void updateSection(PageSection updated) {
    _pushUndo();
    final page = state.activePage;
    if (page == null) return;
    final sections = page.sections
        .map((s) => s.id == updated.id ? updated : s)
        .toList();
    _updatePage(page.id, (p) => p.copyWith(sections: sections));
  }

  void deleteSection(String sectionId) {
    _pushUndo();
    final page = state.activePage;
    if (page == null) return;
    final sections =
        page.sections.where((s) => s.id != sectionId).toList();
    final elements = page.elements
        .where((e) => e.sectionId != sectionId)
        .toList();
    _updatePage(page.id,
        (p) => p.copyWith(sections: sections, elements: elements));
    if (state.selectedElement?.sectionId == sectionId) {
      state = state.copyWith(selectedElementId: null);
    }
  }

  // --- Elements ---

  void addElement(
    PageElementType type,
    String sectionId, {
    int? targetRowIndex,
    int colWidth = 12,
    Map<String, dynamic>? config,
  }) {
    _pushUndo();
    final page = state.activePage;
    if (page == null) return;

    final existingRows = page.elements
        .where((e) => e.sectionId == sectionId)
        .map((e) => e.rowIndex)
        .toSet();
    final row = targetRowIndex ??
        (existingRows.isEmpty
            ? 0
            : existingRows.reduce((a, b) => a > b ? a : b) + 1);

    final element = PageElement(
      id: _uuid.v4(),
      type: type,
      sectionId: sectionId,
      rowIndex: row,
      colWidth: colWidth,
      config: config ?? _defaultConfigFor(type),
    );
    _updatePage(page.id,
        (p) => p.copyWith(elements: [...p.elements, element]));
    state = state.copyWith(selectedElementId: element.id);
  }

  /// Add a child element to any container-type element (Container, Row, etc.)
  void addChildElement(String parentId, PageElementType childType,
      {Map<String, dynamic>? config}) {
    _pushUndo();
    final page = state.activePage;
    if (page == null) return;

    final parent = _findElement(page.elements, parentId);
    if (parent == null) return;

    final child = PageElement(
      id: _uuid.v4(),
      type: childType,
      rowIndex: 0,
      colWidth: 12,
      config: config ?? _defaultConfigFor(childType),
    );

    final updatedParent = parent.copyWith(
      children: <PageElement>[...?parent.children, child],
    );
    final elements = _replaceById(page.elements, parentId, updatedParent);
    _updatePage(page.id, (p) => p.copyWith(elements: elements));
    state = state.copyWith(selectedElementId: child.id);
  }

  /// Wrap an existing element with a new container/row/column
  void wrapWith(String elementId, PageElementType wrapperType) {
    _pushUndo();
    final page = state.activePage;
    if (page == null) return;

    final element = _findElement(page.elements, elementId);
    if (element == null) return;

    final wrapper = PageElement(
      id: _uuid.v4(),
      type: wrapperType,
      sectionId: element.sectionId,
      rowIndex: element.rowIndex,
      colWidth: element.colWidth,
      config: {},
      children: [element.copyWith(sectionId: null, rowIndex: 0)],
    );

    final elements = _replaceById(page.elements, elementId, wrapper);
    _updatePage(page.id, (p) => p.copyWith(elements: elements));
    state = state.copyWith(selectedElementId: wrapper.id);
  }

  /// Find (parentElementId, indexInChildren) for a nested element.
  /// Returns null if the element is at section level (not inside a container).
  (String, int)? _findParentOf(List<PageElement> elements, String id) {
    for (final el in elements) {
      if (el.children != null) {
        for (int i = 0; i < el.children!.length; i++) {
          if (el.children![i].id == id) return (el.id, i);
        }
        final found = _findParentOf(el.children!, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  void moveUp(String id) {
    _pushUndo();
    final page = state.activePage;
    if (page == null) return;

    final parentInfo = _findParentOf(page.elements, id);
    if (parentInfo != null) {
      final (parentId, idx) = parentInfo;
      if (idx == 0) return;
      final parent = _findElement(page.elements, parentId)!;
      final children = List<PageElement>.from(parent.children!);
      final item = children.removeAt(idx);
      children.insert(idx - 1, item);
      final updated = parent.copyWith(children: children);
      _updatePage(page.id,
          (p) => p.copyWith(elements: _replaceById(page.elements, parentId, updated)));
      return;
    }

    final el = page.elements.where((e) => e.id == id).firstOrNull;
    if (el == null) return;
    final siblings = page.elements
        .where((e) => e.sectionId == el.sectionId)
        .toList()
      ..sort((a, b) => a.rowIndex.compareTo(b.rowIndex));
    final idx = siblings.indexWhere((e) => e.id == id);
    if (idx <= 0) return;
    final prev = siblings[idx - 1];
    final updated = page.elements.map((e) {
      if (e.id == id) return e.copyWith(rowIndex: prev.rowIndex);
      if (e.id == prev.id) return e.copyWith(rowIndex: el.rowIndex);
      return e;
    }).toList();
    _updatePage(page.id, (p) => p.copyWith(elements: updated));
  }

  void moveDown(String id) {
    _pushUndo();
    final page = state.activePage;
    if (page == null) return;

    final parentInfo = _findParentOf(page.elements, id);
    if (parentInfo != null) {
      final (parentId, idx) = parentInfo;
      final parent = _findElement(page.elements, parentId)!;
      if (idx >= parent.children!.length - 1) return;
      final children = List<PageElement>.from(parent.children!);
      final item = children.removeAt(idx);
      children.insert(idx + 1, item);
      final updated = parent.copyWith(children: children);
      _updatePage(page.id,
          (p) => p.copyWith(elements: _replaceById(page.elements, parentId, updated)));
      return;
    }

    final el = page.elements.where((e) => e.id == id).firstOrNull;
    if (el == null) return;
    final siblings = page.elements
        .where((e) => e.sectionId == el.sectionId)
        .toList()
      ..sort((a, b) => a.rowIndex.compareTo(b.rowIndex));
    final idx = siblings.indexWhere((e) => e.id == id);
    if (idx >= siblings.length - 1) return;
    final next = siblings[idx + 1];
    final updated = page.elements.map((e) {
      if (e.id == id) return e.copyWith(rowIndex: next.rowIndex);
      if (e.id == next.id) return e.copyWith(rowIndex: el.rowIndex);
      return e;
    }).toList();
    _updatePage(page.id, (p) => p.copyWith(elements: updated));
  }

  /// Reorder children within a parent container
  void reorderChild(String parentId, int oldIndex, int newIndex) {
    _pushUndo();
    final page = state.activePage;
    if (page == null) return;

    final parent = _findElement(page.elements, parentId);
    if (parent == null || parent.children == null) return;

    final children = List<PageElement>.from(parent.children!);
    final item = children.removeAt(oldIndex);
    children.insert(newIndex, item);

    final updatedParent = parent.copyWith(children: children);
    final elements = _replaceById(page.elements, parentId, updatedParent);
    _updatePage(page.id, (p) => p.copyWith(elements: elements));
  }

  void setColumnChild(String parentId, int colIndex, PageElementType type) {
    _pushUndo();
    final page = state.activePage;
    if (page == null) return;
    final parent = _findElement(page.elements, parentId);
    if (parent == null) return;
    final count = parent.config['columnCount'] as int? ?? 2;

    List<PageElement> children = List.from(parent.children ?? []);
    while (children.length < count) {
      children.add(PageElement(
        id: '_empty_${_uuid.v4()}',
        type: PageElementType.spacer,
        rowIndex: 0,
        colWidth: 12,
      ));
    }
    children[colIndex] = PageElement(
      id: _uuid.v4(),
      type: type,
      rowIndex: 0,
      colWidth: 12,
    );
    final updated = parent.copyWith(children: children);
    final elements = _replaceById(page.elements, parentId, updated);
    _updatePage(page.id, (p) => p.copyWith(elements: elements));
    state = state.copyWith(selectedElementId: children[colIndex].id);
  }

  void updateElement(PageElement updated) {
    final page = state.activePage;
    if (page == null) return;
    final elements = _replaceById(page.elements, updated.id, updated);
    _updatePage(page.id, (p) => p.copyWith(elements: elements));
  }

  void updateElementConfig(String elementId, Map<String, dynamic> config) {
    final page = state.activePage;
    if (page == null) return;
    final existing = _findElement(page.elements, elementId);
    if (existing == null) return;
    final updated =
        existing.copyWith(config: {...existing.config, ...config});
    final elements = _replaceById(page.elements, elementId, updated);
    _updatePage(page.id, (p) => p.copyWith(elements: elements));
  }

  void updateElementStyle(String elementId, ElementStyle style) {
    final page = state.activePage;
    if (page == null) return;
    final existing = _findElement(page.elements, elementId);
    if (existing == null) return;
    final updated = existing.copyWith(style: style);
    final elements = _replaceById(page.elements, elementId, updated);
    _updatePage(page.id, (p) => p.copyWith(elements: elements));
  }

  void deleteElement(String elementId) {
    _pushUndo();
    final page = state.activePage;
    if (page == null) return;
    final elements = _removeElement(page.elements, elementId);
    _updatePage(page.id, (p) => p.copyWith(elements: elements));
    if (state.selectedElementId == elementId) {
      state = state.copyWith(selectedElementId: null);
    }
  }

  void selectElement(String? elementId) {
    state = state.copyWith(selectedElementId: elementId);
  }

  void moveElement({
    required String elementId,
    required String targetSectionId,
    required int targetRowIndex,
    int? colWidth,
  }) {
    _pushUndo();
    final page = state.activePage;
    if (page == null) return;
    final elements = page.elements.map((e) {
      if (e.id != elementId) return e;
      return e.copyWith(
        sectionId: targetSectionId,
        rowIndex: targetRowIndex,
        colWidth: colWidth ?? e.colWidth,
      );
    }).toList();
    _updatePage(page.id, (p) => p.copyWith(elements: elements));
  }

  void resizeElement(String elementId, int newColWidth) {
    final page = state.activePage;
    if (page == null) return;
    final existing = _findElement(page.elements, elementId);
    if (existing == null) return;
    final updated = existing.copyWith(colWidth: newColWidth.clamp(1, 12));
    final elements = _replaceById(page.elements, elementId, updated);
    _updatePage(page.id, (p) => p.copyWith(elements: elements));
  }

  // --- Undo / Redo ---

  void undo() {
    if (state.undoPointer < 0) return;
    final previous = state.undoStack[state.undoPointer];
    state = state.copyWith(
      site: previous,
      undoPointer: state.undoPointer - 1,
    );
  }

  void redo() {
    if (state.undoPointer >= state.undoStack.length - 1) return;
    final next = state.undoStack[state.undoPointer + 1];
    state = state.copyWith(
      site: next,
      undoPointer: state.undoPointer + 1,
    );
  }

  // --- Persistence ---

  Future<void> save() async {
    state = state.copyWith(saving: true);
    try {
      await _storage.save(state.site);
    } finally {
      state = state.copyWith(saving: false);
    }
  }

  // --- Default config lookup ---

  Map<String, dynamic> _defaultConfigFor(PageElementType type) {
    // Lazily import from registry — avoids circular imports by keeping this thin
    final registry = _kDefaultConfigs;
    return Map<String, dynamic>.from(registry[type] ?? {});
  }

  // --- Recursive element tree helpers ---

  PageElement? _findElement(List<PageElement> elements, String id) {
    for (final el in elements) {
      if (el.id == id) return el;
      if (el.children != null && el.children!.isNotEmpty) {
        final found = _findElement(el.children!, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  List<PageElement> _replaceById(
      List<PageElement> elements, String oldId, PageElement replacement) {
    return elements.map((el) {
      if (el.id == oldId) return replacement;
      if (el.children != null && el.children!.isNotEmpty) {
        return el.copyWith(
            children: _replaceById(el.children!, oldId, replacement));
      }
      return el;
    }).toList();
  }

  List<PageElement> _removeElement(
      List<PageElement> elements, String id) {
    final result = <PageElement>[];
    for (final el in elements) {
      if (el.id == id) continue;
      if (el.children != null && el.children!.isNotEmpty) {
        result.add(
            el.copyWith(children: _removeElement(el.children!, id)));
      } else {
        result.add(el);
      }
    }
    return result;
  }

  // --- Internal ---

  void _pushUndo() {
    const maxUndo = 50;
    final trimmed = state.undoStack.length >= maxUndo
        ? state.undoStack.sublist(state.undoStack.length - maxUndo + 1)
        : [...state.undoStack];
    state = state.copyWith(
      undoStack: [...trimmed, state.site],
      undoPointer: trimmed.length,
    );
  }

  void _updatePage(
      String pageId, PageDefinition Function(PageDefinition) fn) {
    final pages = state.site.pages.map((p) {
      if (p.id != pageId) return p;
      return fn(p);
    }).toList();
    state = state.copyWith(site: state.site.copyWith(pages: pages));
  }
}

final builderProvider =
    NotifierProvider<PageBuilderNotifier, PageBuilderState>(
  PageBuilderNotifier.new,
);
