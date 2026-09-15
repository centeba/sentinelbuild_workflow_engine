import 'element_style.dart';

class PageSection {
  final String id;
  final String pageId;
  final String title;
  final String description;
  final int order;
  final bool collapsible;
  final bool collapsed;
  final ElementStyle? style;

  const PageSection({
    required this.id,
    required this.pageId,
    this.title = 'Section',
    this.description = '',
    this.order = 0,
    this.collapsible = false,
    this.collapsed = false,
    this.style,
  });

  PageSection copyWith({
    String? id,
    String? pageId,
    String? title,
    String? description,
    int? order,
    bool? collapsible,
    bool? collapsed,
    Object? style = _sentinel,
  }) {
    return PageSection(
      id: id ?? this.id,
      pageId: pageId ?? this.pageId,
      title: title ?? this.title,
      description: description ?? this.description,
      order: order ?? this.order,
      collapsible: collapsible ?? this.collapsible,
      collapsed: collapsed ?? this.collapsed,
      style:
          identical(style, _sentinel) ? this.style : style as ElementStyle?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageId': pageId,
        'title': title,
        'description': description,
        'order': order,
        'collapsible': collapsible,
        'collapsed': collapsed,
        if (style != null) 'style': style!.toJson(),
      };

  factory PageSection.fromJson(Map<String, dynamic> json) => PageSection(
        id: json['id'] as String,
        pageId: json['pageId'] as String,
        title: json['title'] as String? ?? 'Section',
        description: json['description'] as String? ?? '',
        order: json['order'] as int? ?? 0,
        collapsible: json['collapsible'] as bool? ?? false,
        collapsed: json['collapsed'] as bool? ?? false,
        style: json['style'] != null
            ? ElementStyle.fromJson(json['style'] as Map<String, dynamic>)
            : null,
      );
}

const _sentinel = Object();
