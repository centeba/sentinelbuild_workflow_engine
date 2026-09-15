class SiteTheme {
  final String primaryColor;
  final String accentColor;
  final String bgColor;
  final String headingFont;
  final String bodyFont;
  final double baseFontSize;
  final double borderRadius;
  final String brightness; // 'dark' | 'light'

  const SiteTheme({
    this.primaryColor = '#4F7FFF',
    this.accentColor = '#06B6D4',
    this.bgColor = '#060B18',
    this.headingFont = 'Plus Jakarta Sans',
    this.bodyFont = 'Inter',
    this.baseFontSize = 14,
    this.borderRadius = 12,
    this.brightness = 'dark',
  });

  SiteTheme copyWith({
    String? primaryColor,
    String? accentColor,
    String? bgColor,
    String? headingFont,
    String? bodyFont,
    double? baseFontSize,
    double? borderRadius,
    String? brightness,
  }) {
    return SiteTheme(
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
      bgColor: bgColor ?? this.bgColor,
      headingFont: headingFont ?? this.headingFont,
      bodyFont: bodyFont ?? this.bodyFont,
      baseFontSize: baseFontSize ?? this.baseFontSize,
      borderRadius: borderRadius ?? this.borderRadius,
      brightness: brightness ?? this.brightness,
    );
  }

  Map<String, dynamic> toJson() => {
        'primaryColor': primaryColor,
        'accentColor': accentColor,
        'bgColor': bgColor,
        'headingFont': headingFont,
        'bodyFont': bodyFont,
        'baseFontSize': baseFontSize,
        'borderRadius': borderRadius,
        'brightness': brightness,
      };

  factory SiteTheme.fromJson(Map<String, dynamic> json) => SiteTheme(
        primaryColor: json['primaryColor'] as String? ?? '#4F7FFF',
        accentColor: json['accentColor'] as String? ?? '#06B6D4',
        bgColor: json['bgColor'] as String? ?? '#060B18',
        headingFont:
            json['headingFont'] as String? ?? 'Plus Jakarta Sans',
        bodyFont: json['bodyFont'] as String? ?? 'Inter',
        baseFontSize: (json['baseFontSize'] as num?)?.toDouble() ?? 14,
        borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 12,
        brightness: json['brightness'] as String? ?? 'dark',
      );
}
