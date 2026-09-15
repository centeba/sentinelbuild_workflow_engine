// Node-type registry — Riverpod provider that fetches
// `GET /api/v1/node-types/registry` and exposes the merged palette
// (built-in groups + pack-contributed triggers/actions/groups) to
// `NodePalette` and `NodeConfigPanel`.
//
// Cached per app lifecycle: the registry rarely changes (only when a
// pack is installed/uninstalled, which requires a host restart), so
// a single `FutureProvider` is enough. Pull-to-refresh in the
// builder UI can invalidate it via `ref.invalidate`.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';

class NodeTypeRegistry {
  final List<Map<String, dynamic>> builtInGroups;
  final List<Map<String, dynamic>> builtInNodeTypes;
  final List<Map<String, dynamic>> packGroups;
  final List<Map<String, dynamic>> packTriggers;
  final List<Map<String, dynamic>> packActions;
  // No-code condition-builder schema: one entry per pack-contributed domain
  // (entities → fields → selectable values). Consumed by SchemaConditionBuilder.
  final List<Map<String, dynamic>> packDataDomains;
  // Authenticated-scraper templates (multi-tenant). One entry per connector a
  // pack contributes. Consumed by the Integration Hub Scraper tab.
  final List<Map<String, dynamic>> packScraperConnectors;

  const NodeTypeRegistry({
    required this.builtInGroups,
    required this.builtInNodeTypes,
    required this.packGroups,
    required this.packTriggers,
    required this.packActions,
    this.packDataDomains = const [],
    this.packScraperConnectors = const [],
  });

  factory NodeTypeRegistry.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String key) =>
        List<Map<String, dynamic>>.from(
          (json[key] as List? ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map)),
        );
    return NodeTypeRegistry(
      builtInGroups: list('built_in_groups'),
      builtInNodeTypes: list('built_in_node_types'),
      packGroups: list('pack_groups'),
      packTriggers: list('pack_triggers'),
      packActions: list('pack_actions'),
      packDataDomains: list('pack_data_domains'),
      packScraperConnectors: list('pack_scraper_connectors'),
    );
  }

  /// All domains across installed packs, in stable order.
  List<Map<String, dynamic>> get domains => packDataDomains;

  /// All scraper connectors across installed packs.
  List<Map<String, dynamic>> get scraperConnectors => packScraperConnectors;

  /// Lookup a domain spec by its key (e.g. "restoration").
  Map<String, dynamic>? lookupDomain(String key) {
    for (final d in packDataDomains) {
      if (d['key'] == key) return d;
    }
    return null;
  }

  /// Lookup the full spec for a node by its key. Used by
  /// `NodeConfigPanel` when the user selects a node on the canvas
  /// and the config form needs to render from its JSON Schema.
  Map<String, dynamic>? lookup(String key) {
    for (final t in packTriggers) {
      if (t['key'] == key) return t;
    }
    for (final a in packActions) {
      if (a['key'] == key) return a;
    }
    for (final b in builtInNodeTypes) {
      if (b['key'] == key) return b;
    }
    return null;
  }

  /// True if a node key was contributed by an installed pack (vs a
  /// platform built-in). Used to route the config panel into the
  /// schema-driven form path.
  bool isPackContributed(String key) {
    return packTriggers.any((t) => t['key'] == key) ||
        packActions.any((a) => a['key'] == key);
  }
}

final nodeTypeRegistryProvider =
    FutureProvider<NodeTypeRegistry>((ref) async {
  final dio = ref.watch(dioProvider);
  final r = await dio.get('/node-types/registry');
  return NodeTypeRegistry.fromJson(Map<String, dynamic>.from(r.data as Map));
});
