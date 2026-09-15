import 'page_section.dart';
import 'page_element.dart';

class PageParam {
  final String key;
  final String type; // 'string' | 'number' | 'boolean' | 'object'
  final dynamic defaultValue;
  final bool required;

  const PageParam({
    required this.key,
    this.type = 'string',
    this.defaultValue,
    this.required = false,
  });

  PageParam copyWith({
    String? key,
    String? type,
    dynamic defaultValue,
    bool? required,
  }) {
    return PageParam(
      key: key ?? this.key,
      type: type ?? this.type,
      defaultValue: defaultValue ?? this.defaultValue,
      required: required ?? this.required,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type,
        if (defaultValue != null) 'defaultValue': defaultValue,
        'required': required,
      };

  factory PageParam.fromJson(Map<String, dynamic> json) => PageParam(
        key: json['key'] as String,
        type: json['type'] as String? ?? 'string',
        defaultValue: json['defaultValue'],
        required: json['required'] as bool? ?? false,
      );
}

class PageDefinition {
  final String id;
  final String title;
  final String slug;
  final int order;
  final List<PageSection> sections;
  final List<PageElement> elements;
  final List<PageParam> inputParams;
  final String? parentPageId;

  // ── Phase 5 / 6 publish + visibility fields ────────────────────────────────
  /// Anonymous access flag. Server-side enforced — flipping `false → true`
  /// on the pages-api endpoint requires an admin.
  final bool publicAccess;
  /// Per-page IP rate limit override. Shape:
  /// `{ "per_min": 5, "per_day": 100 }`. Null = use service default.
  final Map<String, dynamic>? rateLimits;
  /// CAPTCHA configuration. Shape:
  /// `{ "provider": "recaptcha_v3", "site_key": "...", "min_score": 0.5 }`.
  final Map<String, dynamic>? captchaConfig;
  /// Submission size + field-count limits. Shape:
  /// `{ "max_size_kb": 100, "max_fields": 50 }`.
  final Map<String, dynamic>? submissionConfig;
  /// Page-level role-visibility filter. Empty / null = visible to all
  /// authenticated users in the org. The renderer uses this to gate the
  /// entire page; element-level [PageElement.roleVisibility] handles
  /// finer-grained sub-page filtering.
  final List<String>? roleVisibility;

  const PageDefinition({
    required this.id,
    required this.title,
    this.slug = '',
    this.order = 0,
    this.sections = const [],
    this.elements = const [],
    this.inputParams = const [],
    this.parentPageId,
    this.publicAccess = false,
    this.rateLimits,
    this.captchaConfig,
    this.submissionConfig,
    this.roleVisibility,
  });

  PageDefinition copyWith({
    String? id,
    String? title,
    String? slug,
    int? order,
    List<PageSection>? sections,
    List<PageElement>? elements,
    List<PageParam>? inputParams,
    Object? parentPageId = _sentinel,
    bool? publicAccess,
    Object? rateLimits = _sentinel,
    Object? captchaConfig = _sentinel,
    Object? submissionConfig = _sentinel,
    Object? roleVisibility = _sentinel,
  }) {
    return PageDefinition(
      id: id ?? this.id,
      title: title ?? this.title,
      slug: slug ?? this.slug,
      order: order ?? this.order,
      sections: sections ?? this.sections,
      elements: elements ?? this.elements,
      inputParams: inputParams ?? this.inputParams,
      parentPageId: identical(parentPageId, _sentinel)
          ? this.parentPageId
          : parentPageId as String?,
      publicAccess: publicAccess ?? this.publicAccess,
      rateLimits: identical(rateLimits, _sentinel)
          ? this.rateLimits
          : rateLimits as Map<String, dynamic>?,
      captchaConfig: identical(captchaConfig, _sentinel)
          ? this.captchaConfig
          : captchaConfig as Map<String, dynamic>?,
      submissionConfig: identical(submissionConfig, _sentinel)
          ? this.submissionConfig
          : submissionConfig as Map<String, dynamic>?,
      roleVisibility: identical(roleVisibility, _sentinel)
          ? this.roleVisibility
          : roleVisibility as List<String>?,
    );
  }

  List<PageSection> get sortedSections {
    final sorted = [...sections];
    sorted.sort((a, b) => a.order.compareTo(b.order));
    return sorted;
  }

  List<PageElement> elementsInSection(String sectionId) {
    return elements.where((e) => e.sectionId == sectionId).toList();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'slug': slug,
        'order': order,
        'sections': sections.map((s) => s.toJson()).toList(),
        'elements': elements.map((e) => e.toJson()).toList(),
        'inputParams': inputParams.map((p) => p.toJson()).toList(),
        if (parentPageId != null) 'parentPageId': parentPageId,
        if (publicAccess) 'publicAccess': true,
        if (rateLimits != null) 'rateLimits': rateLimits,
        if (captchaConfig != null) 'captchaConfig': captchaConfig,
        if (submissionConfig != null) 'submissionConfig': submissionConfig,
        if (roleVisibility != null && roleVisibility!.isNotEmpty)
          'roleVisibility': roleVisibility,
      };

  factory PageDefinition.fromJson(Map<String, dynamic> json) =>
      PageDefinition(
        id: json['id'] as String,
        title: json['title'] as String,
        slug: json['slug'] as String? ?? '',
        order: json['order'] as int? ?? 0,
        sections: (json['sections'] as List<dynamic>? ?? [])
            .map((s) =>
                PageSection.fromJson(s as Map<String, dynamic>))
            .toList(),
        elements: (json['elements'] as List<dynamic>? ?? [])
            .map((e) =>
                PageElement.fromJson(e as Map<String, dynamic>))
            .toList(),
        inputParams: (json['inputParams'] as List<dynamic>? ?? [])
            .map((p) => PageParam.fromJson(p as Map<String, dynamic>))
            .toList(),
        parentPageId: json['parentPageId'] as String?,
        publicAccess: json['publicAccess'] as bool? ?? false,
        rateLimits: (json['rateLimits'] as Map?)?.cast<String, dynamic>(),
        captchaConfig:
            (json['captchaConfig'] as Map?)?.cast<String, dynamic>(),
        submissionConfig:
            (json['submissionConfig'] as Map?)?.cast<String, dynamic>(),
        roleVisibility: (json['roleVisibility'] is List)
            ? List<String>.from(
                (json['roleVisibility'] as List).map((e) => e.toString()))
            : null,
      );
}

const _sentinel = Object();
