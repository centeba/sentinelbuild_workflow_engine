import 'package:flutter/material.dart';

import '../design/palette.dart';

class ElementStyle {
  final String? backgroundColor;
  final String? backgroundGradient;
  final String? color;
  final double? fontSize;
  final String? fontWeight;
  final String? textAlign;
  final double? paddingTop;
  final double? paddingBottom;
  final double? paddingLeft;
  final double? paddingRight;
  final double? marginTop;
  final double? marginBottom;
  final double? marginLeft;
  final double? marginRight;
  final double? borderRadius;
  final String? borderColor;
  final double? borderWidth;
  final double? width;
  final double? height;
  final double? minHeight;
  final String? shadow;
  final double? opacity;

  const ElementStyle({
    this.backgroundColor,
    this.backgroundGradient,
    this.color,
    this.fontSize,
    this.fontWeight,
    this.textAlign,
    this.paddingTop,
    this.paddingBottom,
    this.paddingLeft,
    this.paddingRight,
    this.marginTop,
    this.marginBottom,
    this.marginLeft,
    this.marginRight,
    this.borderRadius,
    this.borderColor,
    this.borderWidth,
    this.width,
    this.height,
    this.minHeight,
    this.shadow,
    this.opacity,
  });

  EdgeInsets get padding => EdgeInsets.only(
        top: paddingTop ?? 0,
        bottom: paddingBottom ?? 0,
        left: paddingLeft ?? 0,
        right: paddingRight ?? 0,
      );

  EdgeInsets get margin => EdgeInsets.only(
        top: marginTop ?? 0,
        bottom: marginBottom ?? 0,
        left: marginLeft ?? 0,
        right: marginRight ?? 0,
      );

  FontWeight get resolvedFontWeight {
    return switch (fontWeight) {
      'bold' || '700' => FontWeight.w700,
      'semibold' || '600' => FontWeight.w600,
      'medium' || '500' => FontWeight.w500,
      'light' || '300' => FontWeight.w300,
      _ => FontWeight.w400,
    };
  }

  TextAlign get resolvedTextAlign {
    return switch (textAlign) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.left,
    };
  }

  /// Resolve one of the colour strings a page definition can carry:
  /// `#RRGGBB` is a literal, `token:<role>` names a role on [palette] so the
  /// page follows the active brand and brightness instead of freezing one hex
  /// into the saved page. Anything else (and an unknown role) is "unset".
  static Color? _resolve(String? value, OPaletteData palette) {
    if (value == null) return null;
    if (value.startsWith('#')) {
      final hex = value.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    }
    if (value.startsWith('token:')) return palette.role(value.substring(6));
    return null;
  }

  Color? resolvedBackgroundColor(OPaletteData palette) =>
      _resolve(backgroundColor, palette);

  Color? resolvedColor(OPaletteData palette) => _resolve(color, palette);

  Color? resolvedBorderColor(OPaletteData palette) =>
      _resolve(borderColor, palette);

  ElementStyle copyWith({
    String? backgroundColor,
    String? backgroundGradient,
    String? color,
    double? fontSize,
    String? fontWeight,
    String? textAlign,
    double? paddingTop,
    double? paddingBottom,
    double? paddingLeft,
    double? paddingRight,
    double? marginTop,
    double? marginBottom,
    double? marginLeft,
    double? marginRight,
    double? borderRadius,
    String? borderColor,
    double? borderWidth,
    double? width,
    double? height,
    double? minHeight,
    String? shadow,
    double? opacity,
  }) {
    return ElementStyle(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      textAlign: textAlign ?? this.textAlign,
      paddingTop: paddingTop ?? this.paddingTop,
      paddingBottom: paddingBottom ?? this.paddingBottom,
      paddingLeft: paddingLeft ?? this.paddingLeft,
      paddingRight: paddingRight ?? this.paddingRight,
      marginTop: marginTop ?? this.marginTop,
      marginBottom: marginBottom ?? this.marginBottom,
      marginLeft: marginLeft ?? this.marginLeft,
      marginRight: marginRight ?? this.marginRight,
      borderRadius: borderRadius ?? this.borderRadius,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      width: width ?? this.width,
      height: height ?? this.height,
      minHeight: minHeight ?? this.minHeight,
      shadow: shadow ?? this.shadow,
      opacity: opacity ?? this.opacity,
    );
  }

  Map<String, dynamic> toJson() => {
        if (backgroundColor != null) 'backgroundColor': backgroundColor,
        if (backgroundGradient != null)
          'backgroundGradient': backgroundGradient,
        if (color != null) 'color': color,
        if (fontSize != null) 'fontSize': fontSize,
        if (fontWeight != null) 'fontWeight': fontWeight,
        if (textAlign != null) 'textAlign': textAlign,
        if (paddingTop != null) 'paddingTop': paddingTop,
        if (paddingBottom != null) 'paddingBottom': paddingBottom,
        if (paddingLeft != null) 'paddingLeft': paddingLeft,
        if (paddingRight != null) 'paddingRight': paddingRight,
        if (marginTop != null) 'marginTop': marginTop,
        if (marginBottom != null) 'marginBottom': marginBottom,
        if (marginLeft != null) 'marginLeft': marginLeft,
        if (marginRight != null) 'marginRight': marginRight,
        if (borderRadius != null) 'borderRadius': borderRadius,
        if (borderColor != null) 'borderColor': borderColor,
        if (borderWidth != null) 'borderWidth': borderWidth,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (minHeight != null) 'minHeight': minHeight,
        if (shadow != null) 'shadow': shadow,
        if (opacity != null) 'opacity': opacity,
      };

  factory ElementStyle.fromJson(Map<String, dynamic> json) => ElementStyle(
        backgroundColor: json['backgroundColor'] as String?,
        backgroundGradient: json['backgroundGradient'] as String?,
        color: json['color'] as String?,
        fontSize: (json['fontSize'] as num?)?.toDouble(),
        fontWeight: json['fontWeight'] as String?,
        textAlign: json['textAlign'] as String?,
        paddingTop: (json['paddingTop'] as num?)?.toDouble(),
        paddingBottom: (json['paddingBottom'] as num?)?.toDouble(),
        paddingLeft: (json['paddingLeft'] as num?)?.toDouble(),
        paddingRight: (json['paddingRight'] as num?)?.toDouble(),
        marginTop: (json['marginTop'] as num?)?.toDouble(),
        marginBottom: (json['marginBottom'] as num?)?.toDouble(),
        marginLeft: (json['marginLeft'] as num?)?.toDouble(),
        marginRight: (json['marginRight'] as num?)?.toDouble(),
        borderRadius: (json['borderRadius'] as num?)?.toDouble(),
        borderColor: json['borderColor'] as String?,
        borderWidth: (json['borderWidth'] as num?)?.toDouble(),
        width: (json['width'] as num?)?.toDouble(),
        height: (json['height'] as num?)?.toDouble(),
        minHeight: (json['minHeight'] as num?)?.toDouble(),
        shadow: json['shadow'] as String?,
        opacity: (json['opacity'] as num?)?.toDouble(),
      );
}
