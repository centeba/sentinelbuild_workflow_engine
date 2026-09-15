import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Brand enum ────────────────────────────────────────────────────────────────
/// Selects which brand palette to use. Stored in secure storage as a string.
enum ThemeBrand {
  restoration,
  finance,
  construction;

  String get label => switch (this) {
        ThemeBrand.restoration  => 'Restoration',
        ThemeBrand.finance      => 'Finance',
        ThemeBrand.construction => 'Construction',
      };

  // Default brand is restoration (teal) — the unified pd-design-tokens brand
  // shared with the restoration + technician apps. Unknown/legacy values fall
  // back to restoration rather than finance.
  static ThemeBrand fromString(String? s) => switch (s) {
        'finance'      => ThemeBrand.finance,
        'construction' => ThemeBrand.construction,
        _              => ThemeBrand.restoration,
      };
}

// ── Palette (private) ─────────────────────────────────────────────────────────
/// Holds every colour token for one brand × brightness combination.
class _Palette {
  final Brightness brightness;
  // Backgrounds
  final Color bgPage, bgSurface, bgRaised, bgSubtle, bgHover;
  // Borders
  final Color borderSubtle, borderStrong, borderFocus;
  // Text
  final Color textPrimary, textSecondary, textMuted, textInverse, textBright;
  // Primary
  final Color primary, primaryHover, primaryLight, primaryText;
  // Secondary
  final Color secondary, secondaryHover, secondaryLight, secondaryText;
  // Accent
  final Color accent, accentHover, accentLight, accentText;
  // Semantic
  final Color success, successLight, successText;
  final Color warning, warningLight, warningText;
  final Color error,   errorLight,   errorText;
  final Color info,    infoLight,    infoText;

  const _Palette({
    required this.brightness,
    required this.bgPage, required this.bgSurface, required this.bgRaised,
    required this.bgSubtle, required this.bgHover,
    required this.borderSubtle, required this.borderStrong, required this.borderFocus,
    required this.textPrimary, required this.textSecondary, required this.textMuted,
    required this.textInverse, required this.textBright,
    required this.primary, required this.primaryHover,
    required this.primaryLight, required this.primaryText,
    required this.secondary, required this.secondaryHover,
    required this.secondaryLight, required this.secondaryText,
    required this.accent, required this.accentHover,
    required this.accentLight, required this.accentText,
    required this.success, required this.successLight, required this.successText,
    required this.warning, required this.warningLight, required this.warningText,
    required this.error,   required this.errorLight,   required this.errorText,
    required this.info,    required this.infoLight,    required this.infoText,
  });

  // ── Finance Dark ─────────────────────────────────────────────────────────
  static const _Palette financeDark = _Palette(
    brightness:     Brightness.dark,
    bgPage:         Color(0xFF0B1120),
    bgSurface:      Color(0xFF1E293B),
    bgRaised:       Color(0xFF334155),
    bgSubtle:       Color(0xFF111827),
    bgHover:        Color(0xFF263248),
    borderSubtle:   Color(0xFF334155),
    borderStrong:   Color(0xFF475569),
    borderFocus:    Color(0xFF60A5FA),
    textPrimary:    Color(0xFFE2E8F0),
    textSecondary:  Color(0xFF94A3B8),
    textMuted:      Color(0xFF64748B),
    textInverse:    Color(0xFF1F2937),
    textBright:     Color(0xFFF8FAFC),
    primary:        Color(0xFF60A5FA),
    primaryHover:   Color(0xFF93C5FD),
    primaryLight:   Color(0xFF1E3A5F),
    primaryText:    Color(0xFF0B1120),
    secondary:      Color(0xFF93C5FD),
    secondaryHover: Color(0xFFBFDBFE),
    secondaryLight: Color(0xFF172554),
    secondaryText:  Color(0xFF0B1120),
    accent:         Color(0xFFFBBF24),
    accentHover:    Color(0xFFFCD34D),
    accentLight:    Color(0xFF422006),
    accentText:     Color(0xFF1F2937),
    success:        Color(0xFF34D399),
    successLight:   Color(0xFF064E3B),
    successText:    Color(0xFFA7F3D0),
    warning:        Color(0xFFFBBF24),
    warningLight:   Color(0xFF451A03),
    warningText:    Color(0xFFFDE68A),
    error:          Color(0xFFF87171),
    errorLight:     Color(0xFF450A0A),
    errorText:      Color(0xFFFECACA),
    info:           Color(0xFF60A5FA),
    infoLight:      Color(0xFF172554),
    infoText:       Color(0xFFBFDBFE),
  );

  // ── Finance Light ─────────────────────────────────────────────────────────
  static const _Palette financeLight = _Palette(
    brightness:     Brightness.light,
    bgPage:         Color(0xFFFFFFFF),
    bgSurface:      Color(0xFFFFFFFF),
    bgRaised:       Color(0xFFF1F5F9),
    bgSubtle:       Color(0xFFF8FAFC),
    bgHover:        Color(0xFFEEF2F8),
    borderSubtle:   Color(0xFFE2E8F0),
    borderStrong:   Color(0xFFCBD5E1),
    borderFocus:    Color(0xFF3B82F6),
    textPrimary:    Color(0xFF1F2937),
    textSecondary:  Color(0xFF4B5563),
    textMuted:      Color(0xFF6B7280),
    textInverse:    Color(0xFFF9FAFB),
    textBright:     Color(0xFF111827),
    primary:        Color(0xFF1B365D),
    primaryHover:   Color(0xFF152B4D),
    primaryLight:   Color(0xFFE8EEF6),
    primaryText:    Color(0xFFFFFFFF),
    secondary:      Color(0xFF3B82F6),
    secondaryHover: Color(0xFF2563EB),
    secondaryLight: Color(0xFFEFF6FF),
    secondaryText:  Color(0xFFFFFFFF),
    accent:         Color(0xFFF59E0B),
    accentHover:    Color(0xFFD97706),
    accentLight:    Color(0xFFFEF3C7),
    accentText:     Color(0xFF1F2937),
    success:        Color(0xFF059669),
    successLight:   Color(0xFFECFDF5),
    successText:    Color(0xFF065F46),
    warning:        Color(0xFFD97706),
    warningLight:   Color(0xFFFFFBEB),
    warningText:    Color(0xFF92400E),
    error:          Color(0xFFDC2626),
    errorLight:     Color(0xFFFEF2F2),
    errorText:      Color(0xFF991B1B),
    info:           Color(0xFF2563EB),
    infoLight:      Color(0xFFEFF6FF),
    infoText:       Color(0xFF1E40AF),
  );

  // ── Construction Dark ─────────────────────────────────────────────────────
  // Dark steel-gray base, orange primary. Cohesive with the light variant.
  static const _Palette constructionDark = _Palette(
    brightness:     Brightness.dark,
    bgPage:         Color(0xFF111827),  // gray-900
    bgSurface:      Color(0xFF1F2937),  // gray-800
    bgRaised:       Color(0xFF374151),  // gray-700
    bgSubtle:       Color(0xFF1F2937),  // gray-800
    bgHover:        Color(0xFF2D3748),  // gray-750
    borderSubtle:   Color(0xFF374151),  // gray-700
    borderStrong:   Color(0xFF4B5563),  // gray-600
    borderFocus:    Color(0xFFFB923C),  // orange-400
    textPrimary:    Color(0xFFF9FAFB),  // gray-50
    textSecondary:  Color(0xFFD1D5DB),  // gray-300
    textMuted:      Color(0xFF6B7280),  // gray-500
    textInverse:    Color(0xFF111827),  // gray-900
    textBright:     Color(0xFFFFFFFF),  // white
    primary:        Color(0xFFFB923C),  // orange-400
    primaryHover:   Color(0xFFF97316),  // orange-500
    primaryLight:   Color(0xFF431407),  // orange-950
    primaryText:    Color(0xFF111827),  // gray-900
    secondary:      Color(0xFF9CA3AF),  // gray-400
    secondaryHover: Color(0xFFD1D5DB),  // gray-300
    secondaryLight: Color(0xFF374151),  // gray-700
    secondaryText:  Color(0xFF111827),  // gray-900
    accent:         Color(0xFFFBBF24),  // amber-400
    accentHover:    Color(0xFFF59E0B),  // amber-500
    accentLight:    Color(0xFF451A03),  // amber-950
    accentText:     Color(0xFF111827),  // gray-900
    success:        Color(0xFF4ADE80),  // green-400
    successLight:   Color(0xFF14532D),  // green-900
    successText:    Color(0xFFBBF7D0),  // green-200
    warning:        Color(0xFFFBBF24),  // amber-400
    warningLight:   Color(0xFF422006),  // amber-950
    warningText:    Color(0xFFFEF08A),  // amber-200
    error:          Color(0xFFF87171),  // red-400
    errorLight:     Color(0xFF450A0A),  // red-950
    errorText:      Color(0xFFFECACA),  // red-200
    info:           Color(0xFF60A5FA),  // blue-400
    infoLight:      Color(0xFF172554),  // blue-950
    infoText:       Color(0xFFBFDBFE),  // blue-200
  );

  // ── Construction Light ────────────────────────────────────────────────────
  // Modern white base with safety-orange primary and steel-gray secondary.
  static const _Palette constructionLight = _Palette(
    brightness:     Brightness.light,
    bgPage:         Color(0xFFFFFFFF),  // pure white
    bgSurface:      Color(0xFFFFFFFF),  // pure white
    bgRaised:       Color(0xFFF9FAFB),  // gray-50
    bgSubtle:       Color(0xFFF3F4F6),  // gray-100
    bgHover:        Color(0xFFF3F4F6),  // gray-100
    borderSubtle:   Color(0xFFE5E7EB),  // gray-200
    borderStrong:   Color(0xFFD1D5DB),  // gray-300
    borderFocus:    Color(0xFFF97316),  // orange-500
    textPrimary:    Color(0xFF111827),  // gray-900
    textSecondary:  Color(0xFF374151),  // gray-700
    textMuted:      Color(0xFF9CA3AF),  // gray-400
    textInverse:    Color(0xFFFFFFFF),  // white
    textBright:     Color(0xFF030712),  // gray-950
    primary:        Color(0xFFF97316),  // orange-500 — construction orange
    primaryHover:   Color(0xFFEA580C),  // orange-600
    primaryLight:   Color(0xFFFFF7ED),  // orange-50
    primaryText:    Color(0xFFFFFFFF),  // white
    secondary:      Color(0xFF374151),  // gray-700 — steel gray
    secondaryHover: Color(0xFF1F2937),  // gray-800
    secondaryLight: Color(0xFFF3F4F6),  // gray-100
    secondaryText:  Color(0xFFFFFFFF),  // white
    accent:         Color(0xFFF59E0B),  // amber-400 — safety yellow
    accentHover:    Color(0xFFD97706),  // amber-500
    accentLight:    Color(0xFFFFFBEB),  // amber-50
    accentText:     Color(0xFF1F2937),  // gray-800
    success:        Color(0xFF16A34A),  // green-600
    successLight:   Color(0xFFF0FDF4),  // green-50
    successText:    Color(0xFF166534),  // green-800
    warning:        Color(0xFFD97706),  // amber-600
    warningLight:   Color(0xFFFFFBEB),  // amber-50
    warningText:    Color(0xFF92400E),  // amber-900
    error:          Color(0xFFDC2626),  // red-600
    errorLight:     Color(0xFFFEF2F2),  // red-50
    errorText:      Color(0xFF991B1B),  // red-800
    info:           Color(0xFF2563EB),  // blue-600
    infoLight:      Color(0xFFEFF6FF),  // blue-50
    infoText:       Color(0xFF1E40AF),  // blue-800
  );

  // ── Restoration (unified pd-design-tokens brand: teal + safety-orange) ────
  // Values mirror pd-design-tokens/tokens/brand/restoration.json (see the
  // generated pd_tokens.gen.dart). primary=brand, accent=accent, etc.
  static const _Palette restorationLight = _Palette(
    brightness:     Brightness.light,
    bgPage:         Color(0xFFFFFFFF),
    bgSurface:      Color(0xFFFFFFFF),
    bgRaised:       Color(0xFFF8FAFC),
    bgSubtle:       Color(0xFFF1F5F9),
    bgHover:        Color(0xFFF1F5F9),
    borderSubtle:   Color(0xFFDDE3EA),
    borderStrong:   Color(0xFFCBD5E1),
    borderFocus:    Color(0xFF00C2B2),
    textPrimary:    Color(0xFF1E293B),
    textSecondary:  Color(0xFF46586E),
    textMuted:      Color(0xFF94A3B8),
    textInverse:    Color(0xFFFFFFFF),
    textBright:     Color(0xFF0F172A),
    primary:        Color(0xFF00C2B2),
    primaryHover:   Color(0xFF00A899),
    primaryLight:   Color(0xFFE8FDF9),
    primaryText:    Color(0xFFFFFFFF),
    secondary:      Color(0xFF334155),
    secondaryHover: Color(0xFF1E293B),
    secondaryLight: Color(0xFFF1F5F9),
    secondaryText:  Color(0xFFFFFFFF),
    accent:         Color(0xFFE65F2D),
    accentHover:    Color(0xFFC24A1E),
    accentLight:    Color(0xFFFCE9E0),
    accentText:     Color(0xFFFFFFFF),
    success:        Color(0xFF2E9E6B),
    successLight:   Color(0xFFECFDF5),
    successText:    Color(0xFF065F46),
    warning:        Color(0xFFE0A100),
    warningLight:   Color(0xFFFFFBEB),
    warningText:    Color(0xFF92400E),
    error:          Color(0xFFDC2626),
    errorLight:     Color(0xFFFEF2F2),
    errorText:      Color(0xFF991B1B),
    info:           Color(0xFF2563EB),
    infoLight:      Color(0xFFEFF6FF),
    infoText:       Color(0xFF1E40AF),
  );

  static const _Palette restorationDark = _Palette(
    brightness:     Brightness.dark,
    bgPage:         Color(0xFF0B1120),
    bgSurface:      Color(0xFF1E293B),
    bgRaised:       Color(0xFF334155),
    bgSubtle:       Color(0xFF0F172A),
    bgHover:        Color(0xFF334155),
    borderSubtle:   Color(0xFF334155),
    borderStrong:   Color(0xFF475569),
    borderFocus:    Color(0xFF3BA98F),
    textPrimary:    Color(0xFFE2E8F0),
    textSecondary:  Color(0xFF94A3B8),
    textMuted:      Color(0xFF64748B),
    textInverse:    Color(0xFF0F172A),
    textBright:     Color(0xFFF8FAFC),
    primary:        Color(0xFF3BA98F),
    primaryHover:   Color(0xFF0E7C66),
    primaryLight:   Color(0xFF0A5C4C),
    primaryText:    Color(0xFF0B1120),
    secondary:      Color(0xFF94A3B8),
    secondaryHover: Color(0xFFCBD5E1),
    secondaryLight: Color(0xFF334155),
    secondaryText:  Color(0xFF0B1120),
    accent:         Color(0xFFF0814E),
    accentHover:    Color(0xFFE65F2D),
    accentLight:    Color(0xFFC24A1E),
    accentText:     Color(0xFF0B1120),
    success:        Color(0xFF34D399),
    successLight:   Color(0xFF064E3B),
    successText:    Color(0xFFA7F3D0),
    warning:        Color(0xFFFBBF24),
    warningLight:   Color(0xFF451A03),
    warningText:    Color(0xFFFDE68A),
    error:          Color(0xFFF87171),
    errorLight:     Color(0xFF450A0A),
    errorText:      Color(0xFFFECACA),
    info:           Color(0xFF60A5FA),
    infoLight:      Color(0xFF172554),
    infoText:       Color(0xFFBFDBFE),
  );

}

// ── Runtime per-tenant white-label (C4) ──────────────────────────────────────
// The built-in `ThemeBrand` presets stay exactly as they are (compile-time,
// hand-tuned). `BrandConfig` adds a RUNTIME path: a tenant supplies brand
// colours (+ optional logo / Google-Fonts family names) — from a config
// service, pack theme, or JSON — and the theme is derived on the fly. Brand
// colours drive primary/secondary/accent (+ hover/light/text variants and the
// focus ring); neutral scaffolding and semantic colours are inherited from a
// base palette so a tenant only has to pick its brand colours.

Color _darken(Color c, [double amount = 0.09]) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness - amount).clamp(0.0, 1.0)).toColor();
}

/// A soft "container/light" tint of [c] for the current [brightness].
Color _container(Color c, Brightness brightness) {
  final h = HSLColor.fromColor(c);
  return brightness == Brightness.light
      ? h.withLightness(0.93).withSaturation((h.saturation * 0.55).clamp(0.0, 1.0)).toColor()
      : h.withLightness(0.20).toColor();
}

/// Readable text/foreground colour to place on top of [c].
Color _onColor(Color c) =>
    ThemeData.estimateBrightnessForColor(c) == Brightness.dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF0B1120);

/// Build a palette that keeps [base]'s neutral + semantic tokens but swaps in a
/// tenant's brand colours (with derived hover/light/text variants).
_Palette _brandedPalette({
  required _Palette base,
  required Color primary,
  required Color secondary,
  required Color accent,
  required Brightness brightness,
}) =>
    _Palette(
      brightness: brightness,
      bgPage: base.bgPage, bgSurface: base.bgSurface, bgRaised: base.bgRaised,
      bgSubtle: base.bgSubtle, bgHover: base.bgHover,
      borderSubtle: base.borderSubtle, borderStrong: base.borderStrong,
      borderFocus: primary,
      textPrimary: base.textPrimary, textSecondary: base.textSecondary,
      textMuted: base.textMuted, textInverse: base.textInverse, textBright: base.textBright,
      primary: primary, primaryHover: _darken(primary),
      primaryLight: _container(primary, brightness), primaryText: _onColor(primary),
      secondary: secondary, secondaryHover: _darken(secondary),
      secondaryLight: _container(secondary, brightness), secondaryText: _onColor(secondary),
      accent: accent, accentHover: _darken(accent),
      accentLight: _container(accent, brightness), accentText: _onColor(accent),
      success: base.success, successLight: base.successLight, successText: base.successText,
      warning: base.warning, warningLight: base.warningLight, warningText: base.warningText,
      error: base.error, errorLight: base.errorLight, errorText: base.errorText,
      info: base.info, infoLight: base.infoLight, infoText: base.infoText,
    );

int _colorFromHex(String? s, int fallback) {
  if (s == null) return fallback;
  var h = s.replaceFirst('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  return int.tryParse(h, radix: 16) ?? fallback;
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Runtime brand colours + identity, exposed to widgets as a [ThemeExtension] so
/// they can read the ACTIVE tenant's brand instead of the compile-time static
/// `AppTheme.*` tokens. Read via `Theme.of(context).extension<BrandColors>()`.
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  final Color primary, primaryHover, primaryLight, primaryText;
  final Color secondary, secondaryHover, secondaryLight, secondaryText;
  final Color accent, accentHover, accentLight, accentText;
  final Color borderFocus;
  final String? logoUrl;
  final String headingFont, bodyFont;

  const BrandColors({
    required this.primary, required this.primaryHover,
    required this.primaryLight, required this.primaryText,
    required this.secondary, required this.secondaryHover,
    required this.secondaryLight, required this.secondaryText,
    required this.accent, required this.accentHover,
    required this.accentLight, required this.accentText,
    required this.borderFocus,
    this.logoUrl,
    this.headingFont = 'Plus Jakarta Sans',
    this.bodyFont = 'Inter',
  });

  factory BrandColors._fromPalette(
    _Palette p, {
    String? logoUrl,
    String headingFont = 'Plus Jakarta Sans',
    String bodyFont = 'Inter',
  }) =>
      BrandColors(
        primary: p.primary, primaryHover: p.primaryHover,
        primaryLight: p.primaryLight, primaryText: p.primaryText,
        secondary: p.secondary, secondaryHover: p.secondaryHover,
        secondaryLight: p.secondaryLight, secondaryText: p.secondaryText,
        accent: p.accent, accentHover: p.accentHover,
        accentLight: p.accentLight, accentText: p.accentText,
        borderFocus: p.borderFocus,
        logoUrl: logoUrl, headingFont: headingFont, bodyFont: bodyFont,
      );

  @override
  BrandColors copyWith({
    Color? primary, Color? primaryHover, Color? primaryLight, Color? primaryText,
    Color? secondary, Color? secondaryHover, Color? secondaryLight, Color? secondaryText,
    Color? accent, Color? accentHover, Color? accentLight, Color? accentText,
    Color? borderFocus, String? logoUrl, String? headingFont, String? bodyFont,
  }) =>
      BrandColors(
        primary: primary ?? this.primary, primaryHover: primaryHover ?? this.primaryHover,
        primaryLight: primaryLight ?? this.primaryLight, primaryText: primaryText ?? this.primaryText,
        secondary: secondary ?? this.secondary, secondaryHover: secondaryHover ?? this.secondaryHover,
        secondaryLight: secondaryLight ?? this.secondaryLight, secondaryText: secondaryText ?? this.secondaryText,
        accent: accent ?? this.accent, accentHover: accentHover ?? this.accentHover,
        accentLight: accentLight ?? this.accentLight, accentText: accentText ?? this.accentText,
        borderFocus: borderFocus ?? this.borderFocus,
        logoUrl: logoUrl ?? this.logoUrl,
        headingFont: headingFont ?? this.headingFont, bodyFont: bodyFont ?? this.bodyFont,
      );

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return BrandColors(
      primary: l(primary, other.primary), primaryHover: l(primaryHover, other.primaryHover),
      primaryLight: l(primaryLight, other.primaryLight), primaryText: l(primaryText, other.primaryText),
      secondary: l(secondary, other.secondary), secondaryHover: l(secondaryHover, other.secondaryHover),
      secondaryLight: l(secondaryLight, other.secondaryLight), secondaryText: l(secondaryText, other.secondaryText),
      accent: l(accent, other.accent), accentHover: l(accentHover, other.accentHover),
      accentLight: l(accentLight, other.accentLight), accentText: l(accentText, other.accentText),
      borderFocus: l(borderFocus, other.borderFocus),
      logoUrl: t < 0.5 ? logoUrl : other.logoUrl,
      headingFont: t < 0.5 ? headingFont : other.headingFont,
      bodyFont: t < 0.5 ? bodyFont : other.bodyFont,
    );
  }
}

/// A tenant brand: seed colours + optional logo and Google-Fonts family names.
/// The built-in [ThemeBrand]s are exposed as presets that reproduce their exact
/// hand-tuned palettes; a custom tenant supplies its own colours and the rest is
/// derived. Serializable so it can come from a per-tenant config source.
@immutable
class BrandConfig {
  final String name;
  final Color primary, secondary, accent;
  final String? logoUrl;
  final String headingFont, bodyFont, monoFont;

  /// Explicit palettes — set only for the built-in presets to reproduce their
  /// exact values. Custom brands leave these null and derive from the seeds.
  final _Palette? _lightOverride, _darkOverride;

  const BrandConfig({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.accent,
    this.logoUrl,
    this.headingFont = 'Plus Jakarta Sans',
    this.bodyFont = 'Inter',
    this.monoFont = 'JetBrains Mono',
    _Palette? lightOverride,
    _Palette? darkOverride,
  })  : _lightOverride = lightOverride,
        _darkOverride = darkOverride;

  factory BrandConfig.fromJson(Map<String, dynamic> j) => BrandConfig(
        name: (j['name'] as String?) ?? 'custom',
        primary: Color(_colorFromHex(j['primary'] as String?, 0xFF00C2B2)),
        secondary: Color(_colorFromHex((j['secondary'] ?? j['primary']) as String?, 0xFF334155)),
        accent: Color(_colorFromHex((j['accent'] ?? j['primary']) as String?, 0xFFE65F2D)),
        logoUrl: j['logoUrl'] as String?,
        headingFont: (j['headingFont'] as String?) ?? 'Plus Jakarta Sans',
        bodyFont: (j['bodyFont'] as String?) ?? 'Inter',
        monoFont: (j['monoFont'] as String?) ?? 'JetBrains Mono',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'primary': _hex(primary),
        'secondary': _hex(secondary),
        'accent': _hex(accent),
        if (logoUrl != null) 'logoUrl': logoUrl,
        'headingFont': headingFont,
        'bodyFont': bodyFont,
        'monoFont': monoFont,
      };

  /// The palette for [brightness] — the exact preset palette when this is a
  /// built-in brand, otherwise derived from the seed colours.
  _Palette paletteFor(Brightness brightness) {
    final override = brightness == Brightness.light ? _lightOverride : _darkOverride;
    if (override != null) return override;
    final base = brightness == Brightness.light
        ? _Palette.restorationLight
        : _Palette.restorationDark;
    return _brandedPalette(
      base: base, primary: primary, secondary: secondary, accent: accent,
      brightness: brightness,
    );
  }

  /// The built-in preset for [brand] (reproduces its exact palettes).
  static BrandConfig preset(ThemeBrand brand) => switch (brand) {
        ThemeBrand.restoration => restoration,
        ThemeBrand.finance => finance,
        ThemeBrand.construction => construction,
      };

  static const BrandConfig restoration = BrandConfig(
    name: 'restoration',
    primary: Color(0xFF00C2B2), secondary: Color(0xFF334155), accent: Color(0xFFE65F2D),
    lightOverride: _Palette.restorationLight, darkOverride: _Palette.restorationDark,
  );
  static const BrandConfig finance = BrandConfig(
    name: 'finance',
    primary: Color(0xFF1B365D), secondary: Color(0xFF3B82F6), accent: Color(0xFFF59E0B),
    lightOverride: _Palette.financeLight, darkOverride: _Palette.financeDark,
  );
  static const BrandConfig construction = BrandConfig(
    name: 'construction',
    primary: Color(0xFFF97316), secondary: Color(0xFF374151), accent: Color(0xFFF59E0B),
    lightOverride: _Palette.constructionLight, darkOverride: _Palette.constructionDark,
  );
}

// ── AppTheme ──────────────────────────────────────────────────────────────────
/// Design tokens and ThemeData factory for Mit Stack.
///
/// Usage:
///   MaterialApp(
///     theme:     AppTheme.build(brand, Brightness.light),
///     darkTheme: AppTheme.build(brand, Brightness.dark),
///     themeMode: themeMode,
///   )
///
/// Typography  : Plus Jakarta Sans (headings) · Inter (body) · JetBrains Mono (code)
/// Base unit   : 4 px
abstract class AppTheme {
  // ── Public colour constants (Restoration Light — unified default brand) ──
  // These are static const tokens used directly by screens. They mirror the
  // restorationLight palette (pd-design-tokens teal/orange) so all custom
  // widgets render in the unified brand out of the box. Material-themed
  // components use the runtime ColorScheme from AppTheme.build() and respond
  // to brand/mode switching automatically. (Const, so brand-invariant — same
  // as before, just defaulted to restoration instead of construction.)
  static const Color bgPage         = Color(0xFFFFFFFF);
  static const Color bgSurface      = Color(0xFFFFFFFF);
  static const Color bgRaised       = Color(0xFFF8FAFC);
  static const Color bgSubtle       = Color(0xFFF1F5F9);
  static const Color bgHover        = Color(0xFFF1F5F9);
  static const Color borderSubtle   = Color(0xFFDDE3EA);
  static const Color borderStrong   = Color(0xFFCBD5E1);
  static const Color borderFocus    = Color(0xFF00C2B2);  // teal — brand
  static const Color textPrimary    = Color(0xFF1E293B);
  static const Color textSecondary  = Color(0xFF46586E);
  static const Color textMuted      = Color(0xFF94A3B8);
  static const Color textInverse    = Color(0xFFFFFFFF);
  static const Color textBright     = Color(0xFF0F172A);
  static const Color primary        = Color(0xFF00C2B2);  // teal — brand
  static const Color primaryHover   = Color(0xFF00A899);
  static const Color primaryLight   = Color(0xFFE8FDF9);
  static const Color primaryText    = Color(0xFFFFFFFF);
  static const Color secondary      = Color(0xFF334155);
  static const Color secondaryHover = Color(0xFF1E293B);
  static const Color secondaryLight = Color(0xFFF1F5F9);
  static const Color secondaryText  = Color(0xFFFFFFFF);
  static const Color accent         = Color(0xFFE65F2D);  // safety orange
  static const Color accentHover    = Color(0xFFC24A1E);
  static const Color accentLight    = Color(0xFFFCE9E0);
  static const Color accentText     = Color(0xFFFFFFFF);
  static const Color success        = Color(0xFF2E9E6B);
  static const Color successLight   = Color(0xFFECFDF5);
  static const Color successText    = Color(0xFF065F46);
  static const Color warning        = Color(0xFFE0A100);
  static const Color warningLight   = Color(0xFFFFFBEB);
  static const Color warningText    = Color(0xFF92400E);
  static const Color error          = Color(0xFFDC2626);
  static const Color errorLight     = Color(0xFFFEF2F2);
  static const Color errorText      = Color(0xFF991B1B);
  static const Color info           = Color(0xFF2563EB);
  static const Color infoLight      = Color(0xFFEFF6FF);
  static const Color infoText       = Color(0xFF1E40AF);

  // ── Code colours (theme-invariant — always dark, used on canvas) ──────────
  static const Color codeText = Color(0xFF7DD3FC);
  static const Color codeBg   = Color(0xFF1E2235);

  // ── Workflow node accent palette (architecture theme — always dark) ────────
  static const Color nodeFrontendBg     = Color(0xFF1E2545);
  static const Color nodeFrontendBorder = Color(0xFF3B4FD0);
  static const Color nodeFrontendText   = Color(0xFFA5B4FC);
  static const Color nodeBackendBg      = Color(0xFF0D2D22);
  static const Color nodeBackendBorder  = Color(0xFF0D7A5F);
  static const Color nodeBackendText    = Color(0xFF6EE7B7);
  static const Color nodeDbBg           = Color(0xFF2D0D0D);
  static const Color nodeDbBorder       = Color(0xFFB91C1C);
  static const Color nodeDbText         = Color(0xFFFCA5A5);
  static const Color nodeServiceBg      = Color(0xFF2D1A04);
  static const Color nodeServiceBorder  = Color(0xFFB45309);
  static const Color nodeServiceText    = Color(0xFFFBBF24);
  static const Color nodeTemporalBg     = Color(0xFF2D1B5E);
  static const Color nodeTemporalBorder = Color(0xFF7C3AED);
  static const Color nodeTemporalText   = Color(0xFFC4B5FD);
  static const Color nodeExternalBg     = Color(0xFF061E2D);
  static const Color nodeExternalBorder = Color(0xFF0E6B8F);
  static const Color nodeExternalText   = Color(0xFF7DD3FC);

  // ── Backwards-compat aliases ──────────────────────────────────────────────
  static const Color purpleBg     = nodeTemporalBg;
  static const Color purpleBorder = nodeTemporalBorder;
  static const Color purpleText   = nodeTemporalText;
  static const Color primaryBg     = primaryLight;
  static const Color successBorder = success;
  static const Color successBg     = successLight;
  static const Color errorBorder   = error;
  static const Color errorBg       = errorLight;
  static const Color warningBorder = warning;
  static const Color warningBg     = warningLight;
  static const Color infoBorder    = info;
  static const Color infoBg        = infoLight;

  // ── Spacing scale (4 px base) ─────────────────────────────────────────────
  static const double space1  = 4;
  static const double space2  = 8;
  static const double space3  = 12;
  static const double space4  = 16;
  static const double space5  = 20;
  static const double space6  = 24;
  static const double space8  = 32;
  static const double space10 = 40;
  static const double space12 = 48;
  static const double space16 = 64;

  // ── Border radius ─────────────────────────────────────────────────────────
  static const double radiusSm   = 4;
  static const double radiusMd   = 8;
  static const double radiusLg   = 12;
  static const double radiusXl   = 16;
  static const double radiusFull = 9999;

  // ── Shadows ───────────────────────────────────────────────────────────────
  static List<BoxShadow> shadowSm(Brightness b) => [
        BoxShadow(
          color: b == Brightness.dark ? const Color(0x4D000000) : const Color(0x0D000000),
          blurRadius: 2, offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> shadowMd(Brightness b) => [
        BoxShadow(
          color: b == Brightness.dark ? const Color(0x66000000) : const Color(0x1A000000),
          blurRadius: 6, spreadRadius: -1, offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: b == Brightness.dark ? const Color(0x4D000000) : const Color(0x1A000000),
          blurRadius: 4, spreadRadius: -2, offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> shadowLg(Brightness b) => [
        BoxShadow(
          color: b == Brightness.dark ? const Color(0x66000000) : const Color(0x1A000000),
          blurRadius: 15, spreadRadius: -3, offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: b == Brightness.dark ? const Color(0x4D000000) : const Color(0x1A000000),
          blurRadius: 6, spreadRadius: -4, offset: const Offset(0, 4),
        ),
      ];

  // ── Typography helpers ────────────────────────────────────────────────────
  static TextStyle heading({double size = 24, FontWeight weight = FontWeight.w700, Color color = textPrimary}) =>
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: weight, color: color, height: 1.25);

  static TextStyle body({double size = 14, FontWeight weight = FontWeight.w400, Color color = textPrimary}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: 1.5);

  static TextStyle mono({double size = 13, Color color = codeText}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, color: color, height: 1.5);

  static TextStyle get labelStyle   => body(size: 12, weight: FontWeight.w500);
  static TextStyle get captionStyle => body(size: 11, color: textMuted);
  static TextStyle get sectionLabel => body(size: 10, weight: FontWeight.w600, color: textMuted)
      .copyWith(letterSpacing: 0.8);

  static TextStyle get h1 => heading(size: 36, weight: FontWeight.w700);
  static TextStyle get h2 => heading(size: 30, weight: FontWeight.w700);
  static TextStyle get h3 => heading(size: 24, weight: FontWeight.w600);
  static TextStyle get h4 => heading(size: 20, weight: FontWeight.w600);
  static TextStyle get h5 => heading(size: 18, weight: FontWeight.w600);

  // ── Reusable decorations (use p.xxx in palette-aware code) ────────────────
  static BoxDecoration card({Color? color, double radius = radiusLg, bool elevated = false, Color? border}) =>
      BoxDecoration(
        color: color ?? AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? AppTheme.borderSubtle),
        boxShadow: elevated ? shadowMd(Brightness.light) : shadowSm(Brightness.light),
      );

  static BoxDecoration pill({required Color bg, required Color border}) => BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(radiusFull),
        border: Border.all(color: border),
      );

  static BoxDecoration get badgeSuccess => pill(bg: successLight, border: success);
  static BoxDecoration get badgeWarning => pill(bg: warningLight, border: warning);
  static BoxDecoration get badgeError   => pill(bg: errorLight,   border: error);
  static BoxDecoration get badgeInfo    => pill(bg: infoLight,    border: info);
  static BoxDecoration get badgePrimary => pill(bg: primaryLight, border: primary);

  // ── Legacy single-theme getter (Restoration Light — unified default) ──────
  static ThemeData get themeData => build(ThemeBrand.restoration, Brightness.light);

  // ── Multi-theme factory ───────────────────────────────────────────────────
  /// Build a complete [ThemeData] for [brand] × [brightness].
  static ThemeData build(ThemeBrand brand, Brightness brightness) =>
      buildFromConfig(BrandConfig.preset(brand), brightness);

  /// Build a complete [ThemeData] from a runtime [BrandConfig] (C4 white-label).
  /// [build] delegates here via [BrandConfig.preset], so both share one
  /// implementation and the built-in brands render exactly as before. The
  /// resulting theme carries a [BrandColors] extension so widgets can read the
  /// active tenant's brand at runtime.
  /// The runtime brand colours for [config] × [brightness], without building a
  /// full [ThemeData] (no font loading) — the same [BrandColors] attached to the
  /// theme. Handy for widgets/tests that only need the brand palette.
  static BrandColors brandColors(BrandConfig config, Brightness brightness) =>
      BrandColors._fromPalette(config.paletteFor(brightness),
          logoUrl: config.logoUrl,
          headingFont: config.headingFont, bodyFont: config.bodyFont);

  static ThemeData buildFromConfig(BrandConfig config, Brightness brightness) {
    final p = config.paletteFor(brightness);
    final textTheme = _textTheme(p, brightness == Brightness.dark,
        headingFont: config.headingFont, bodyFont: config.bodyFont);
    return _themeData(p, textTheme,
        logoUrl: config.logoUrl,
        headingFont: config.headingFont, bodyFont: config.bodyFont);
  }

  static TextTheme _textTheme(_Palette p, bool isDark,
      {String headingFont = 'Plus Jakarta Sans', String bodyFont = 'Inter'}) {
    return GoogleFonts.getTextTheme(
      bodyFont, isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ).copyWith(
      displayLarge:   _h(48, 700, p, font: headingFont),
      displayMedium:  _h(36, 700, p, font: headingFont),
      displaySmall:   _h(30, 700, p, font: headingFont),
      headlineLarge:  _h(24, 700, p, font: headingFont),
      headlineMedium: _h(20, 600, p, font: headingFont),
      headlineSmall:  _h(18, 600, p, font: headingFont),
      titleLarge:     _b(18, 600, p, font: bodyFont),
      titleMedium:    _b(16, 600, p, font: bodyFont),
      titleSmall:     _b(14, 600, p, font: bodyFont),
      bodyLarge:      _b(16, 400, p, font: bodyFont),
      bodyMedium:     _b(14, 400, p, font: bodyFont),
      bodySmall:      _b(12, 400, p, font: bodyFont),
      labelLarge:     _b(14, 600, p, font: bodyFont),
      labelMedium:    _b(12, 500, p, font: bodyFont),
      labelSmall:     _b(10, 500, p, muted: true, font: bodyFont),
    );
  }

  static ThemeData _themeData(_Palette p, TextTheme textTheme,
      {String? logoUrl,
      String headingFont = 'Plus Jakarta Sans',
      String bodyFont = 'Inter'}) {
    final brightness = p.brightness;
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      textTheme: textTheme,
      colorScheme: isDark
          ? ColorScheme.dark(
              primary:              p.primary,
              onPrimary:            p.primaryText,
              primaryContainer:     p.primaryLight,
              onPrimaryContainer:   p.textPrimary,
              secondary:            p.secondary,
              onSecondary:          p.secondaryText,
              secondaryContainer:   p.secondaryLight,
              onSecondaryContainer: p.textPrimary,
              tertiary:             p.accent,
              onTertiary:           p.accentText,
              tertiaryContainer:    p.accentLight,
              surface:              p.bgSurface,
              onSurface:            p.textPrimary,
              onSurfaceVariant:     p.textSecondary,
              outline:              p.borderSubtle,
              outlineVariant:       p.borderStrong,
              error:                p.error,
              onError:              p.errorText,
              errorContainer:       p.errorLight,
              onErrorContainer:     p.errorText,
            )
          : ColorScheme.light(
              primary:              p.primary,
              onPrimary:            p.primaryText,
              primaryContainer:     p.primaryLight,
              onPrimaryContainer:   p.textPrimary,
              secondary:            p.secondary,
              onSecondary:          p.secondaryText,
              secondaryContainer:   p.secondaryLight,
              onSecondaryContainer: p.textPrimary,
              tertiary:             p.accent,
              onTertiary:           p.accentText,
              tertiaryContainer:    p.accentLight,
              surface:              p.bgSurface,
              onSurface:            p.textPrimary,
              onSurfaceVariant:     p.textSecondary,
              outline:              p.borderSubtle,
              outlineVariant:       p.borderStrong,
              error:                p.error,
              onError:              p.errorText,
              errorContainer:       p.errorLight,
              onErrorContainer:     p.errorText,
            ),
      scaffoldBackgroundColor: p.bgPage,
      cardColor:    p.bgSurface,
      dividerColor: p.borderSubtle,

      cardTheme: CardThemeData(
        color: p.bgSurface, elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: p.borderSubtle),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: p.bgHover,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: p.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: p.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: p.borderFocus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: p.error),
        ),
        labelStyle: TextStyle(color: p.textSecondary, fontSize: 14),
        hintStyle:  TextStyle(color: p.textMuted,     fontSize: 14),
        errorStyle: TextStyle(color: p.error,         fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: p.bgSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(radiusLg)),
          side: BorderSide(color: p.borderSubtle),
        ),
      ),

      listTileTheme: ListTileThemeData(
        selectedTileColor: p.primaryLight,
        tileColor: Colors.transparent,
        textColor: p.textPrimary,
        iconColor: p.textSecondary,
        selectedColor: p.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: space4, vertical: space1),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primary : p.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primaryLight : p.borderSubtle,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primary : p.borderStrong,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.primaryText,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          padding: const EdgeInsets.symmetric(horizontal: space4, vertical: space2),
          minimumSize: const Size(0, 36),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          side: BorderSide(color: p.borderStrong),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          padding: const EdgeInsets.symmetric(horizontal: space4, vertical: space2),
          minimumSize: const Size(0, 36),
        ).copyWith(
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(color: s.contains(WidgetState.hovered) ? p.borderFocus : p.borderStrong),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2),
          minimumSize: const Size(0, 36),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: p.bgRaised,
        selectedColor:   p.primaryLight,
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: p.textPrimary),
        side: BorderSide(color: p.borderSubtle),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusFull)),
        padding: const EdgeInsets.symmetric(horizontal: space2, vertical: 0),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.bgRaised,
        contentTextStyle: GoogleFonts.inter(color: p.textPrimary, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: p.borderSubtle),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.bgRaised,
          borderRadius: BorderRadius.circular(radiusSm),
          border: Border.all(color: p.borderSubtle),
          boxShadow: shadowSm(brightness),
        ),
        textStyle: GoogleFonts.inter(color: p.textPrimary, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: space2, vertical: space1),
        waitDuration: const Duration(milliseconds: 400),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: p.bgRaised, elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: p.borderSubtle),
        ),
        textStyle: GoogleFonts.inter(color: p.textPrimary, fontSize: 14),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: p.bgSurface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),

      dividerTheme: DividerThemeData(color: p.borderSubtle, thickness: 1, space: 0),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.textMuted.withValues(alpha: 0.3)),
        radius: const Radius.circular(radiusFull),
        thickness: const WidgetStatePropertyAll(4),
        crossAxisMargin: 2,
      ),

      iconTheme:        IconThemeData(color: p.textSecondary, size: 18),
      primaryIconTheme: IconThemeData(color: p.primary,       size: 18),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primary : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(p.primaryText),
        side: BorderSide(color: p.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primary : p.textMuted,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary, linearTrackColor: p.primaryLight, circularTrackColor: p.primaryLight,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: p.primary, unselectedLabelColor: p.textSecondary,
        indicatorColor: p.primary, dividerColor: p.borderSubtle,
        labelStyle:           GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: p.bgSurface, foregroundColor: p.textPrimary,
        elevation: 0, scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16, fontWeight: FontWeight.w600, color: p.textPrimary),
        iconTheme:        IconThemeData(color: p.textSecondary, size: 18),
        actionsIconTheme: IconThemeData(color: p.textSecondary, size: 18),
        shape: Border(bottom: BorderSide(color: p.borderSubtle)),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.bgSurface, modalBackgroundColor: p.bgSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(radiusLg)),
          side: BorderSide(color: p.borderSubtle),
        ),
      ),

      // Runtime brand tokens for widgets (C4): Theme.of(context).extension<BrandColors>().
      extensions: [
        BrandColors._fromPalette(p,
            logoUrl: logoUrl, headingFont: headingFont, bodyFont: bodyFont),
      ],
    );
  }

  // ── Private text-style builders ───────────────────────────────────────────
  static TextStyle _h(double size, int weight, _Palette p,
          {String font = 'Plus Jakarta Sans'}) =>
      GoogleFonts.getFont(font,
          fontSize: size, fontWeight: FontWeight.values.firstWhere((w) => w.value == weight),
          color: p.textPrimary, height: 1.25);

  static TextStyle _b(double size, int weight, _Palette p,
          {bool muted = false, String font = 'Inter'}) =>
      GoogleFonts.getFont(font,
          fontSize: size, fontWeight: FontWeight.values.firstWhere((w) => w.value == weight),
          color: muted ? p.textMuted : p.textPrimary, height: 1.5);
}
