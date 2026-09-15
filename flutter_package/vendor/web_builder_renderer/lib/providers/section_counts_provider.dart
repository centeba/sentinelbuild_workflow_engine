import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks how many items each section's primary data element is showing, so a
/// collapsible section header can display a count badge (e.g. "Media (312)")
/// without the user having to expand it. Data elements (list / dataGrid /
/// mediaGallery) call [SectionCounts.report] after they load; the section
/// header watches the matching key.
class SectionCounts extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  static String keyOf(String pageId, String sectionId) => '$pageId::$sectionId';

  void report(String pageId, String? sectionId, int count) {
    if (sectionId == null || sectionId.isEmpty) return;
    final key = keyOf(pageId, sectionId);
    if (state[key] == count) return; // no-op when unchanged (avoids rebuild loops)
    state = {...state, key: count};
  }

  int? countFor(String pageId, String sectionId) =>
      state[keyOf(pageId, sectionId)];
}

final sectionCountsProvider =
    NotifierProvider<SectionCounts, Map<String, int>>(SectionCounts.new);
