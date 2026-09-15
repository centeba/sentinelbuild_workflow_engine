import 'page_definition.dart';
import 'site_theme.dart';

class SiteDefinition {
  final String id;
  final String name;
  final String slug;
  final SiteTheme theme;
  final List<PageDefinition> pages;
  final Map<String, dynamic> globalContext;
  /// Phase 6 of documents/platform/web-builder-roadmap.md — vertical-app the site belongs to.
  /// Pages-api uses this for `/api/v1/apps/{app_id}/pages` lookups; null
  /// means the site is unaffiliated (visible only via direct site/page id).
  final String? appId;

  /// Company-type site templates — the audience this site targets (a
  /// CompanyType key like "franchisee"). Only meaningful on a central
  /// template site. Null = an ordinary org site.
  final String? audienceCompanyType;

  /// When true, asking pages-api to create this site as a central template
  /// (owned by the nil org so it renders to every company of the audience).
  /// Only honored for system admins; ignored otherwise. Write-only hint —
  /// not round-tripped from the server.
  final bool asTemplate;

  const SiteDefinition({
    required this.id,
    required this.name,
    this.slug = '',
    this.theme = const SiteTheme(),
    this.pages = const [],
    this.globalContext = const {},
    this.appId,
    this.audienceCompanyType,
    this.asTemplate = false,
  });

  SiteDefinition copyWith({
    String? id,
    String? name,
    String? slug,
    SiteTheme? theme,
    List<PageDefinition>? pages,
    Map<String, dynamic>? globalContext,
    Object? appId = _siteSentinel,
    Object? audienceCompanyType = _siteSentinel,
    bool? asTemplate,
  }) {
    return SiteDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      theme: theme ?? this.theme,
      pages: pages ?? this.pages,
      globalContext: globalContext ?? this.globalContext,
      appId: identical(appId, _siteSentinel)
          ? this.appId
          : appId as String?,
      audienceCompanyType: identical(audienceCompanyType, _siteSentinel)
          ? this.audienceCompanyType
          : audienceCompanyType as String?,
      asTemplate: asTemplate ?? this.asTemplate,
    );
  }

  List<PageDefinition> get sortedPages {
    final sorted = [...pages];
    sorted.sort((a, b) => a.order.compareTo(b.order));
    return sorted;
  }

  PageDefinition? pageById(String id) {
    try {
      return pages.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'theme': theme.toJson(),
        'pages': pages.map((p) => p.toJson()).toList(),
        if (globalContext.isNotEmpty) 'globalContext': globalContext,
        if (appId != null) 'appId': appId,
      };

  factory SiteDefinition.fromJson(Map<String, dynamic> json) =>
      SiteDefinition(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String? ?? '',
        theme: json['theme'] != null
            ? SiteTheme.fromJson(json['theme'] as Map<String, dynamic>)
            : const SiteTheme(),
        pages: (json['pages'] as List<dynamic>? ?? [])
            .map((p) =>
                PageDefinition.fromJson(p as Map<String, dynamic>))
            .toList(),
        globalContext: Map<String, dynamic>.from(
            json['globalContext'] as Map? ?? {}),
        appId: json['appId'] as String?,
      );
}

const _siteSentinel = Object();
