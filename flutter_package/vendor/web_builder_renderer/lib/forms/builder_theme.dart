// Phase WB-theme — host-overridable tokens for the form builder.
//
// `BuilderTheme` is now a Material 3 `ThemeExtension`: hosts register
// a concrete instance on `ThemeData.extensions`, and the form_builder
// reads the active tokens via `BuilderTheme.of(context)` (or the
// shorthand `context.bt.<token>`).
//
// Hosts on the unified design tokens register `BuilderTheme.fromPd(...)`,
// which recolours with the brand and brightness. The `.light()` / `.dark()`
// presets remain for hosts that have not adopted the tokens.
//
// Static helpers (`labelStyle`, `captionStyle`, `sectionLabel`,
// `body`, `mono`, `pill`) stay class-level since they're style
// constructors that don't need theming — they accept a `Color`
// param so callers can pass theme-derived values.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/pd_tokens.gen.dart';

@immutable
class BuilderTheme extends ThemeExtension<BuilderTheme> {
  // ── Backgrounds ──────────────────────────────────────────────────────────
  final Color bgPage;
  final Color bgSurface;
  final Color bgRaised;
  final Color bgSubtle;
  final Color bgHover;

  // ── Borders ──────────────────────────────────────────────────────────────
  final Color borderSubtle;
  final Color borderStrong;

  // ── Text ─────────────────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textBright;

  // ── Brand ────────────────────────────────────────────────────────────────
  final Color primary;
  final Color primaryLight;
  final Color primaryText;

  // ── Status ───────────────────────────────────────────────────────────────
  final Color success;
  final Color successLight;
  final Color successText;
  final Color successBorder;
  final Color successBg;
  final Color error;
  final Color errorLight;
  final Color errorText;
  final Color errorBorder;
  final Color errorBg;
  final Color warning;
  final Color warningLight;
  final Color warningText;
  final Color warningBorder;
  final Color warningBg;
  final Color info;
  final Color infoLight;
  final Color infoText;
  final Color infoBorder;
  final Color infoBg;

  // ── Code (mono) text ─────────────────────────────────────────────────────
  final Color codeText;

  // ── Purple accent ────────────────────────────────────────────────────────
  final Color purpleBorder;
  final Color purpleText;
  final Color purpleBg;

  const BuilderTheme({
    required this.bgPage,
    required this.bgSurface,
    required this.bgRaised,
    required this.bgSubtle,
    required this.bgHover,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textBright,
    required this.primary,
    required this.primaryLight,
    required this.primaryText,
    required this.success,
    required this.successLight,
    required this.successText,
    required this.successBorder,
    required this.successBg,
    required this.error,
    required this.errorLight,
    required this.errorText,
    required this.errorBorder,
    required this.errorBg,
    required this.warning,
    required this.warningLight,
    required this.warningText,
    required this.warningBorder,
    required this.warningBg,
    required this.info,
    required this.infoLight,
    required this.infoText,
    required this.infoBorder,
    required this.infoBg,
    required this.codeText,
    required this.purpleBorder,
    required this.purpleText,
    required this.purpleBg,
  });

  /// Mit Stack "Construction Light" preset — original palette.
  /// Build the form-builder tokens from a generated [PdPalette] so the form
  /// builder matches the host chrome for any brand and brightness. Each status
  /// state takes its base/tint/text triple straight from the token source,
  /// which is where the contrast pairings are decided.
  factory BuilderTheme.fromPd(PdPalette p) => BuilderTheme(
        bgPage: p.bgCanvas,
        bgSurface: p.bgPage,
        bgRaised: p.bgRaised,
        bgSubtle: p.bgSubtle,
        bgHover: p.bgHover,
        borderSubtle: p.borderSubtle,
        borderStrong: p.borderStrong,
        textPrimary: p.textPrimary,
        textSecondary: p.textSecondary,
        textMuted: p.textMuted,
        textBright: p.textBright,
        primary: p.brand,
        primaryLight: p.brandLight,
        primaryText: p.onBrand,
        success: p.successBase,
        successLight: p.successLight,
        successText: p.successText,
        successBorder: p.successBase,
        successBg: p.successLight,
        error: p.errorBase,
        errorLight: p.errorLight,
        errorText: p.errorText,
        errorBorder: p.errorBase,
        errorBg: p.errorLight,
        warning: p.warningBase,
        warningLight: p.warningLight,
        warningText: p.warningText,
        warningBorder: p.warningBase,
        warningBg: p.warningLight,
        info: p.infoBase,
        infoLight: p.infoLight,
        infoText: p.infoText,
        infoBorder: p.infoBase,
        infoBg: p.infoLight,
        // Mono/code text — the info role reads as "literal" on either surface.
        codeText: p.infoText,
        // Accent callouts (the "purple" slot in this vocabulary) take the
        // brand's accent role; PD has no purple.
        purpleBorder: p.accent,
        purpleText: p.accentHover,
        purpleBg: p.accentLight,
      );

  factory BuilderTheme.light() => const BuilderTheme(
        bgPage: Color(0xFFFFFFFF),
        bgSurface: Color(0xFFFFFFFF),
        bgRaised: Color(0xFFF9FAFB),
        bgSubtle: Color(0xFFF3F4F6),
        bgHover: Color(0xFFF3F4F6),
        borderSubtle: Color(0xFFE5E7EB),
        borderStrong: Color(0xFFD1D5DB),
        textPrimary: Color(0xFF111827),
        textSecondary: Color(0xFF374151),
        textMuted: Color(0xFF9CA3AF),
        textBright: Color(0xFF030712),
        primary: Color(0xFFF97316),
        primaryLight: Color(0xFFFFF7ED),
        primaryText: Color(0xFFFFFFFF),
        success: Color(0xFF16A34A),
        successLight: Color(0xFFF0FDF4),
        successText: Color(0xFF166534),
        successBorder: Color(0xFF16A34A),
        successBg: Color(0xFFF0FDF4),
        error: Color(0xFFDC2626),
        errorLight: Color(0xFFFEF2F2),
        errorText: Color(0xFF991B1B),
        errorBorder: Color(0xFFDC2626),
        errorBg: Color(0xFFFEF2F2),
        warning: Color(0xFFD97706),
        warningLight: Color(0xFFFFFBEB),
        warningText: Color(0xFF92400E),
        warningBorder: Color(0xFFD97706),
        warningBg: Color(0xFFFFFBEB),
        info: Color(0xFF2563EB),
        infoLight: Color(0xFFEFF6FF),
        infoText: Color(0xFF1E40AF),
        infoBorder: Color(0xFF2563EB),
        infoBg: Color(0xFFEFF6FF),
        codeText: Color(0xFF7DD3FC),
        purpleBorder: Color(0xFF7C3AED),
        purpleText: Color(0xFFC4B5FD),
        purpleBg: Color(0xFF2D1B5E),
      );

  /// Dark preset matched to web_builder's glassmorphic chrome.
  factory BuilderTheme.dark() => const BuilderTheme(
        bgPage: Color(0xFF0F172A),       // slate-900
        bgSurface: Color(0xFF1E293B),    // slate-800
        bgRaised: Color(0xFF334155),     // slate-700
        bgSubtle: Color(0xFF1E293B),
        bgHover: Color(0xFF334155),
        borderSubtle: Color(0xFF475569), // slate-600
        borderStrong: Color(0xFF64748B), // slate-500
        textPrimary: Color(0xFFE2E8F0),  // slate-200
        textSecondary: Color(0xFFCBD5E1),// slate-300
        textMuted: Color(0xFF94A3B8),    // slate-400
        textBright: Color(0xFFF8FAFC),   // slate-50
        primary: Color(0xFF60A5FA),      // blue-400
        primaryLight: Color(0x3360A5FA), // primary @ 20% alpha
        primaryText: Color(0xFFFFFFFF),
        success: Color(0xFF34D399),      // emerald-400
        successLight: Color(0x3334D399),
        successText: Color(0xFF6EE7B7),  // emerald-300
        successBorder: Color(0xFF34D399),
        successBg: Color(0x3334D399),
        error: Color(0xFFF87171),        // red-400
        errorLight: Color(0x33F87171),
        errorText: Color(0xFFFCA5A5),    // red-300
        errorBorder: Color(0xFFF87171),
        errorBg: Color(0x33F87171),
        warning: Color(0xFFFBBF24),      // amber-400
        warningLight: Color(0x33FBBF24),
        warningText: Color(0xFFFCD34D),  // amber-300
        warningBorder: Color(0xFFFBBF24),
        warningBg: Color(0x33FBBF24),
        info: Color(0xFF60A5FA),         // blue-400
        infoLight: Color(0x3360A5FA),
        infoText: Color(0xFF93C5FD),     // blue-300
        infoBorder: Color(0xFF60A5FA),
        infoBg: Color(0x3360A5FA),
        codeText: Color(0xFF7DD3FC),     // unchanged — sky-300 reads on dark
        purpleBorder: Color(0xFF7C3AED),
        purpleText: Color(0xFFC4B5FD),
        purpleBg: Color(0xFF2D1B5E),
      );

  /// Read the host-registered tokens. Falls back to `light()` when
  /// no host has registered an extension — matches the pre-WB-theme
  /// mit_stack behaviour.
  static BuilderTheme of(BuildContext context) =>
      Theme.of(context).extension<BuilderTheme>() ?? BuilderTheme.light();

  // ─── ThemeExtension contract ─────────────────────────────────────────────
  @override
  BuilderTheme copyWith({
    Color? bgPage,
    Color? bgSurface,
    Color? bgRaised,
    Color? bgSubtle,
    Color? bgHover,
    Color? borderSubtle,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textBright,
    Color? primary,
    Color? primaryLight,
    Color? primaryText,
    Color? success,
    Color? successLight,
    Color? successText,
    Color? successBorder,
    Color? successBg,
    Color? error,
    Color? errorLight,
    Color? errorText,
    Color? errorBorder,
    Color? errorBg,
    Color? warning,
    Color? warningLight,
    Color? warningText,
    Color? warningBorder,
    Color? warningBg,
    Color? info,
    Color? infoLight,
    Color? infoText,
    Color? infoBorder,
    Color? infoBg,
    Color? codeText,
    Color? purpleBorder,
    Color? purpleText,
    Color? purpleBg,
  }) =>
      BuilderTheme(
        bgPage: bgPage ?? this.bgPage,
        bgSurface: bgSurface ?? this.bgSurface,
        bgRaised: bgRaised ?? this.bgRaised,
        bgSubtle: bgSubtle ?? this.bgSubtle,
        bgHover: bgHover ?? this.bgHover,
        borderSubtle: borderSubtle ?? this.borderSubtle,
        borderStrong: borderStrong ?? this.borderStrong,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        textBright: textBright ?? this.textBright,
        primary: primary ?? this.primary,
        primaryLight: primaryLight ?? this.primaryLight,
        primaryText: primaryText ?? this.primaryText,
        success: success ?? this.success,
        successLight: successLight ?? this.successLight,
        successText: successText ?? this.successText,
        successBorder: successBorder ?? this.successBorder,
        successBg: successBg ?? this.successBg,
        error: error ?? this.error,
        errorLight: errorLight ?? this.errorLight,
        errorText: errorText ?? this.errorText,
        errorBorder: errorBorder ?? this.errorBorder,
        errorBg: errorBg ?? this.errorBg,
        warning: warning ?? this.warning,
        warningLight: warningLight ?? this.warningLight,
        warningText: warningText ?? this.warningText,
        warningBorder: warningBorder ?? this.warningBorder,
        warningBg: warningBg ?? this.warningBg,
        info: info ?? this.info,
        infoLight: infoLight ?? this.infoLight,
        infoText: infoText ?? this.infoText,
        infoBorder: infoBorder ?? this.infoBorder,
        infoBg: infoBg ?? this.infoBg,
        codeText: codeText ?? this.codeText,
        purpleBorder: purpleBorder ?? this.purpleBorder,
        purpleText: purpleText ?? this.purpleText,
        purpleBg: purpleBg ?? this.purpleBg,
      );

  @override
  BuilderTheme lerp(ThemeExtension<BuilderTheme>? other, double t) {
    if (other is! BuilderTheme) return this;
    return BuilderTheme(
      bgPage: Color.lerp(bgPage, other.bgPage, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgRaised: Color.lerp(bgRaised, other.bgRaised, t)!,
      bgSubtle: Color.lerp(bgSubtle, other.bgSubtle, t)!,
      bgHover: Color.lerp(bgHover, other.bgHover, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textBright: Color.lerp(textBright, other.textBright, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      success: Color.lerp(success, other.success, t)!,
      successLight: Color.lerp(successLight, other.successLight, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      successBorder: Color.lerp(successBorder, other.successBorder, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorLight: Color.lerp(errorLight, other.errorLight, t)!,
      errorText: Color.lerp(errorText, other.errorText, t)!,
      errorBorder: Color.lerp(errorBorder, other.errorBorder, t)!,
      errorBg: Color.lerp(errorBg, other.errorBg, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningLight: Color.lerp(warningLight, other.warningLight, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
      warningBorder: Color.lerp(warningBorder, other.warningBorder, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoLight: Color.lerp(infoLight, other.infoLight, t)!,
      infoText: Color.lerp(infoText, other.infoText, t)!,
      infoBorder: Color.lerp(infoBorder, other.infoBorder, t)!,
      infoBg: Color.lerp(infoBg, other.infoBg, t)!,
      codeText: Color.lerp(codeText, other.codeText, t)!,
      purpleBorder: Color.lerp(purpleBorder, other.purpleBorder, t)!,
      purpleText: Color.lerp(purpleText, other.purpleText, t)!,
      purpleBg: Color.lerp(purpleBg, other.purpleBg, t)!,
    );
  }

  // ─── Static text-style helpers (host-theme-agnostic) ─────────────────────
  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = const Color(0xFF111827),
  }) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: 1.5);

  static TextStyle mono({double size = 13, Color color = const Color(0xFF7DD3FC)}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, color: color, height: 1.5);

  static TextStyle get labelStyle => body(size: 12, weight: FontWeight.w500);
  static TextStyle get captionStyle =>
      body(size: 11, color: const Color(0xFF9CA3AF));
  static TextStyle get sectionLabel =>
      body(size: 10, weight: FontWeight.w600, color: const Color(0xFF9CA3AF))
          .copyWith(letterSpacing: 0.8);

  static BoxDecoration pill({required Color bg, required Color border}) =>
      BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: border),
      );
}

/// Ergonomic shorthand: `context.bt.bgPage`.
extension BuilderThemeContext on BuildContext {
  BuilderTheme get bt => BuilderTheme.of(this);
}
