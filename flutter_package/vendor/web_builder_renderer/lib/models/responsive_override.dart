class ResponsiveOverride {
  final int? colWidth;
  final bool? hidden;

  const ResponsiveOverride({this.colWidth, this.hidden});

  ResponsiveOverride copyWith({int? colWidth, bool? hidden}) {
    return ResponsiveOverride(
      colWidth: colWidth ?? this.colWidth,
      hidden: hidden ?? this.hidden,
    );
  }

  Map<String, dynamic> toJson() => {
        if (colWidth != null) 'colWidth': colWidth,
        if (hidden != null) 'hidden': hidden,
      };

  factory ResponsiveOverride.fromJson(Map<String, dynamic> json) =>
      ResponsiveOverride(
        colWidth: json['colWidth'] as int?,
        hidden: json['hidden'] as bool?,
      );
}
