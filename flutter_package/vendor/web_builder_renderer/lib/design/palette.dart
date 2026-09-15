import 'package:flutter/material.dart';

import '../models/site_theme.dart';
import 'pd_tokens.gen.dart';

/// Parse a `#RRGGBB` (or `#AARRGGBB`) hex string to a [Color]. Falls back to
/// [fallback] when the string is malformed.
Color _hexColor(String hex, Color fallback) {
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// Resolvable palette (unified PD design tokens).
///
/// MIGRATION: `OPalette.*` static consts remain the **default** (unchanged
/// values) so the 700+ existing call sites are pixel-identical until migrated.
/// New/migrated code reads `OPaletteScope.of(context).x`, which resolves to the
/// generated [PdPalette] when an [OPaletteScope] is installed (e.g. the
/// restoration host wraps pages in one), or the legacy defaults otherwise.
@immutable
class OPaletteData {
  const OPaletteData({
    required this.bgCanvas, required this.bgPage, required this.bgGlass,
    required this.bgGlassBorder, required this.bgSurface, required this.bgRaised,
    required this.bgHover, required this.primaryBlue, required this.primarySlate,
    required this.accentCyan, required this.accentViolet, required this.gainGreen,
    required this.lossRed, required this.warningAmber, required this.neutralBlue,
    required this.textBright, required this.textPrimary, required this.textSecondary,
    required this.textMuted, required this.textInverse, required this.borderSubtle,
    required this.borderStrong, required this.borderFocus,
    required this.successLight, required this.warningLight,
    required this.errorLight, required this.infoLight,
  });

  final Color bgCanvas, bgPage, bgGlass, bgGlassBorder, bgSurface, bgRaised, bgHover;
  final Color primaryBlue, primarySlate, accentCyan, accentViolet;
  final Color gainGreen, lossRed, warningAmber, neutralBlue;
  final Color textBright, textPrimary, textSecondary, textMuted, textInverse;
  final Color borderSubtle, borderStrong, borderFocus;
  /// Tinted status surfaces — the readable background behind a success /
  /// warning / error / info callout. These flip with brightness, which a
  /// literal hex baked into a page definition cannot.
  final Color successLight, warningLight, errorLight, infoLight;

  /// Map a generated unified [PdPalette] onto the renderer's role names.
  factory OPaletteData.fromPd(PdPalette p) => OPaletteData(
        bgCanvas: p.bgCanvas, bgPage: p.bgPage, bgGlass: p.bgSurface,
        bgGlassBorder: p.borderSubtle, bgSurface: p.bgSurface, bgRaised: p.bgRaised,
        bgHover: p.bgHover, primaryBlue: p.brand, primarySlate: p.secondary,
        accentCyan: p.accent, accentViolet: p.accent, gainGreen: p.successBase,
        lossRed: p.errorBase, warningAmber: p.warningBase, neutralBlue: p.infoBase,
        textBright: p.textBright, textPrimary: p.textPrimary,
        textSecondary: p.textSecondary, textMuted: p.textMuted,
        textInverse: p.textInverse, borderSubtle: p.borderSubtle,
        borderStrong: p.borderStrong, borderFocus: p.borderFocus,
        successLight: p.successLight, warningLight: p.warningLight,
        errorLight: p.errorLight, infoLight: p.infoLight,
      );

  /// Build a renderer palette from a page's [SiteTheme]. The site's
  /// primary/accent/background hex drive the brand roles; text/border/surface
  /// roles come from a light or dark base chosen by `theme.brightness`. This is
  /// what makes rendered page content follow each site's brand (e.g.
  /// restoration sets its SiteTheme to the teal PD brand).
  factory OPaletteData.fromSiteTheme(SiteTheme theme) {
    final primary = _hexColor(theme.primaryColor, fallback.primaryBlue);
    final accent = _hexColor(theme.accentColor, fallback.accentCyan);
    final bg = _hexColor(theme.bgColor, fallback.bgCanvas);
    final base = theme.brightness == 'dark' ? _darkBase : fallback;
    return OPaletteData(
      bgCanvas: bg,
      bgPage: base.bgPage, bgGlass: base.bgGlass, bgGlassBorder: base.bgGlassBorder,
      bgSurface: base.bgSurface, bgRaised: base.bgRaised, bgHover: base.bgHover,
      primaryBlue: primary, primarySlate: base.primarySlate,
      accentCyan: accent, accentViolet: accent,
      gainGreen: base.gainGreen, lossRed: base.lossRed,
      warningAmber: base.warningAmber, neutralBlue: base.neutralBlue,
      textBright: base.textBright, textPrimary: base.textPrimary,
      textSecondary: base.textSecondary, textMuted: base.textMuted,
      textInverse: base.textInverse, borderSubtle: base.borderSubtle,
      borderStrong: base.borderStrong, borderFocus: primary,
      successLight: base.successLight, warningLight: base.warningLight,
      errorLight: base.errorLight, infoLight: base.infoLight,
    );
  }

  /// Look a role up by its token name. Backs the `token:<role>` colour
  /// references a page definition can carry in place of a literal hex, so
  /// published page content follows the brand and brightness. Returns null for
  /// an unknown name, which reads as "no colour set" at the call site.
  Color? role(String name) => switch (name) {
        'bgCanvas' => bgCanvas,
        'bgPage' => bgPage,
        'bgGlass' => bgGlass,
        'bgGlassBorder' => bgGlassBorder,
        'bgSurface' => bgSurface,
        'bgRaised' => bgRaised,
        'bgHover' => bgHover,
        'primaryBlue' => primaryBlue,
        'primarySlate' => primarySlate,
        'accentCyan' => accentCyan,
        'accentViolet' => accentViolet,
        'gainGreen' => gainGreen,
        'lossRed' => lossRed,
        'warningAmber' => warningAmber,
        'neutralBlue' => neutralBlue,
        'textBright' => textBright,
        'textPrimary' => textPrimary,
        'textSecondary' => textSecondary,
        'textMuted' => textMuted,
        'textInverse' => textInverse,
        'borderSubtle' => borderSubtle,
        'borderStrong' => borderStrong,
        'borderFocus' => borderFocus,
        'successLight' => successLight,
        'warningLight' => warningLight,
        'errorLight' => errorLight,
        'infoLight' => infoLight,
        _ => null,
      };

  /// Legacy default = current OPalette values (keeps unmigrated apps identical).
  static const OPaletteData fallback = OPaletteData(
    bgCanvas: OPalette.bgCanvas, bgPage: OPalette.bgPage, bgGlass: OPalette.bgGlass,
    bgGlassBorder: OPalette.bgGlassBorder, bgSurface: OPalette.bgSurface,
    bgRaised: OPalette.bgRaised, bgHover: OPalette.bgHover,
    primaryBlue: OPalette.primaryBlue, primarySlate: OPalette.primarySlate,
    accentCyan: OPalette.accentCyan, accentViolet: OPalette.accentViolet,
    gainGreen: OPalette.gainGreen, lossRed: OPalette.lossRed,
    warningAmber: OPalette.warningAmber, neutralBlue: OPalette.neutralBlue,
    textBright: OPalette.textBright, textPrimary: OPalette.textPrimary,
    textSecondary: OPalette.textSecondary, textMuted: OPalette.textMuted,
    textInverse: OPalette.textInverse, borderSubtle: OPalette.borderSubtle,
    borderStrong: OPalette.borderStrong, borderFocus: OPalette.borderFocus,
    successLight: OPalette.successLight, warningLight: OPalette.warningLight,
    errorLight: OPalette.errorLight, infoLight: OPalette.infoLight,
  );

  /// Dark base for `fromSiteTheme` when `brightness == 'dark'` — slate-dark
  /// text/border/surface roles (brand/accent/bg are overridden per site).
  static const OPaletteData _darkBase = OPaletteData(
    bgCanvas: Color(0xFF0B1120), bgPage: Color(0xFF0F172A),
    bgGlass: Color(0xFF1E293B), bgGlassBorder: Color(0xFF334155),
    bgSurface: Color(0xFF1E293B), bgRaised: Color(0xFF334155),
    bgHover: Color(0xFF334155), primaryBlue: Color(0xFF60A5FA),
    primarySlate: Color(0xFF94A3B8), accentCyan: Color(0xFF22D3EE),
    accentViolet: Color(0xFFA78BFA), gainGreen: Color(0xFF34D399),
    lossRed: Color(0xFFF87171), warningAmber: Color(0xFFFBBF24),
    neutralBlue: Color(0xFF60A5FA), textBright: Color(0xFFF8FAFC),
    textPrimary: Color(0xFFE2E8F0), textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF64748B), textInverse: Color(0xFF0B1120),
    borderSubtle: Color(0xFF334155), borderStrong: Color(0xFF475569),
    borderFocus: Color(0xFF60A5FA),
    successLight: Color(0xFF064E3B), warningLight: Color(0xFF451A03),
    errorLight: Color(0xFF450A0A), infoLight: Color(0xFF172554),
  );
}

/// Installs an [OPaletteData] for the subtree. Restoration's host (and any app
/// wanting the unified brand) wraps its page renderer in one built from the
/// generated tokens: `OPaletteScope(data: OPaletteData.fromPd(pdPalette(...)))`.
class OPaletteScope extends InheritedWidget {
  const OPaletteScope({super.key, required this.data, required super.child});

  final OPaletteData data;

  static OPaletteData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OPaletteScope>()?.data ??
      OPaletteData.fallback;

  @override
  bool updateShouldNotify(OPaletteScope oldWidget) => data != oldWidget.data;
}

/// Legacy static palette. Values are kept in lock-step with the canonical
/// generated `pdPalette(PdBrand.restoration, Brightness.light)` (see
/// `pd_tokens.gen.dart`) so the ~35 widgets that still reference `OPalette.x`
/// statically render the SAME brand as `OPaletteScope`-aware widgets and the
/// `pd_design_system` app chrome. (Longer term these refs migrate to
/// `OPaletteScope.of(context)` and this shim is generated.)
abstract final class OPalette {
  // --- Backgrounds (canonical restoration-light = Mitigation-Tracker mockup) ---
  static const bgCanvas    = Color(0xFFF0F4F8); // p.bgCanvas
  static const bgPage      = Color(0xFFFFFFFF); // p.bgPage
  static const bgGlass     = Color(0xFFFFFFFF); // p.bgSurface (card fill)
  static const bgGlassBorder = Color(0xFFDDE3EA); // p.borderSubtle
  static const bgSurface   = Color(0xFFFFFFFF); // p.bgSurface
  static const bgRaised    = Color(0xFFF8FAFC); // p.bgRaised
  static const bgHover     = Color(0xFFF0F4F8); // p.bgHover

  // --- Brand accents (mockup teal / safety orange) ---
  static const primaryBlue  = Color(0xFF00C2B2); // p.brand (teal)
  static const primarySlate = Color(0xFF334155); // p.secondary
  static const accentCyan   = Color(0xFFE65F2D); // p.accent (orange)
  static const accentViolet = Color(0xFFE65F2D); // p.accent

  // --- Semantic ---
  static const gainGreen    = Color(0xFF2E9E6B); // p.successBase
  static const lossRed      = Color(0xFFDC2626); // p.errorBase
  static const warningAmber = Color(0xFFE0A100); // p.warningBase
  static const neutralBlue  = Color(0xFF2563EB); // p.infoBase

  // --- Text hierarchy (navy on light) ---
  static const textBright    = Color(0xFF0A1628); // p.textBright (navy)
  static const textPrimary   = Color(0xFF1E293B); // p.textPrimary
  static const textSecondary = Color(0xFF46586E); // p.textSecondary
  static const textMuted     = Color(0xFF8899AA); // p.textMuted
  static const textInverse   = Color(0xFFFFFFFF); // p.textInverse

  // --- Borders ---
  static const borderSubtle = Color(0xFFDDE3EA); // p.borderSubtle
  static const borderStrong = Color(0xFFC3CCD8); // p.borderStrong
  static const borderFocus  = Color(0xFF00C2B2); // p.borderFocus (brand)

  // --- Status tints (light) ---
  static const successLight = Color(0xFFECFDF5); // p.successLight
  static const warningLight = Color(0xFFFFFBEB); // p.warningLight
  static const errorLight   = Color(0xFFFEF2F2); // p.errorLight
  static const infoLight    = Color(0xFFEFF6FF); // p.infoLight

  // --- Shadows (light) ---
  static const shadowDeep = Color(0x0F000000); // 6% black
  static const shadowGlow = Color(0x1A00C2B2); // 10% brand teal
}
