import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'palette.dart';
import 'tokens.dart';

/// Build the studio theme from a resolvable [palette]. Defaults to
/// [OPaletteData.fallback] (== the legacy `OPalette` values) so existing
/// callers are pixel-identical; pass a palette built from the site/brand
/// tokens (e.g. `OPaletteData.fromSiteTheme(...)`) to recolour rendered pages.
ThemeData buildStudioTheme({OPaletteData palette = OPaletteData.fallback}) {
  final base = ThemeData.light(useMaterial3: true);
  final textTheme = _buildTextTheme(palette);

  return base.copyWith(
    scaffoldBackgroundColor: palette.bgCanvas,
    colorScheme: ColorScheme.light(
      primary: palette.primaryBlue,
      secondary: palette.accentCyan,
      tertiary: palette.accentViolet,
      surface: palette.bgSurface,
      error: palette.lossRed,
      onPrimary: palette.textInverse,
      onSecondary: palette.textInverse,
      onSurface: palette.textPrimary,
      onError: palette.textInverse,
      outline: palette.borderSubtle,
      outlineVariant: palette.borderStrong,
    ),
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.bgRaised,
      hoverColor: palette.bgHover,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: OTokens.s4, vertical: OTokens.s3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OTokens.radiusSm),
        borderSide: BorderSide(color: palette.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OTokens.radiusSm),
        borderSide: BorderSide(color: palette.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OTokens.radiusSm),
        borderSide:
            BorderSide(color: palette.borderFocus, width: 1.5),
      ),
      labelStyle:
          TextStyle(color: palette.textSecondary, fontSize: OTokens.textSm),
      hintStyle:
          TextStyle(color: palette.textMuted, fontSize: OTokens.textBase),
    ),
    dividerTheme: DividerThemeData(
      color: palette.borderSubtle,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: palette.textSecondary, size: 18),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.textPrimary,
        borderRadius: BorderRadius.circular(OTokens.radiusSm),
      ),
      textStyle: TextStyle(
          color: palette.textInverse, fontSize: OTokens.textSm),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(palette.borderStrong),
      trackColor: WidgetStateProperty.all(Colors.transparent),
      radius: const Radius.circular(OTokens.radiusFull),
      thickness: WidgetStateProperty.all(4),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorColor: palette.primaryBlue,
      labelColor: palette.textPrimary,
      unselectedLabelColor: palette.textMuted,
      dividerColor: palette.borderSubtle,
      labelStyle: GoogleFonts.inter(
        fontSize: OTokens.textSm,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: GoogleFonts.inter(
        fontSize: OTokens.textSm,
        fontWeight: FontWeight.w500,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.primaryBlue,
        foregroundColor: palette.textInverse,
        padding: const EdgeInsets.symmetric(
            horizontal: OTokens.s5, vertical: OTokens.s3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OTokens.radiusSm),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: OTokens.textSm,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.borderStrong),
        padding: const EdgeInsets.symmetric(
            horizontal: OTokens.s5, vertical: OTokens.s3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OTokens.radiusSm),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: OTokens.textSm,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.primaryBlue,
        padding: const EdgeInsets.symmetric(
            horizontal: OTokens.s3, vertical: OTokens.s2),
        textStyle: GoogleFonts.inter(
          fontSize: OTokens.textSm,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.bgRaised,
      selectedColor: palette.primaryBlue.withValues(alpha: 0.12),
      side: BorderSide(color: palette.borderSubtle),
      labelStyle: GoogleFonts.inter(
          fontSize: OTokens.textSm, color: palette.textSecondary),
      padding: const EdgeInsets.symmetric(
          horizontal: OTokens.s3, vertical: OTokens.s1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OTokens.radiusFull),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.textPrimary,
      contentTextStyle: GoogleFonts.inter(
          color: palette.textInverse, fontSize: OTokens.textBase),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OTokens.radiusSm)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

TextTheme _buildTextTheme(OPaletteData palette) {
  final jakartaBold = GoogleFonts.plusJakartaSans(
    fontWeight: FontWeight.w700,
    color: palette.textBright,
  );
  final jakartaSemibold = GoogleFonts.plusJakartaSans(
    fontWeight: FontWeight.w600,
    color: palette.textBright,
  );
  final inter = GoogleFonts.inter(color: palette.textPrimary);
  final interMuted = GoogleFonts.inter(color: palette.textSecondary);

  return TextTheme(
    displayLarge:
        jakartaBold.copyWith(fontSize: OTokens.text4xl, height: 1.1),
    displayMedium:
        jakartaBold.copyWith(fontSize: OTokens.text3xl, height: 1.15),
    displaySmall:
        jakartaBold.copyWith(fontSize: OTokens.text2xl, height: 1.2),
    headlineLarge:
        jakartaSemibold.copyWith(fontSize: OTokens.textXl, height: 1.3),
    headlineMedium:
        jakartaSemibold.copyWith(fontSize: OTokens.textLg, height: 1.3),
    headlineSmall:
        jakartaSemibold.copyWith(fontSize: OTokens.textMd, height: 1.4),
    titleLarge: jakartaSemibold.copyWith(
        fontSize: OTokens.textMd, height: 1.4),
    titleMedium: inter.copyWith(
        fontSize: OTokens.textBase,
        fontWeight: FontWeight.w600,
        height: 1.4),
    titleSmall: inter.copyWith(
        fontSize: OTokens.textSm,
        fontWeight: FontWeight.w600,
        height: 1.4),
    bodyLarge: inter.copyWith(fontSize: OTokens.textMd, height: 1.6),
    bodyMedium: inter.copyWith(fontSize: OTokens.textBase, height: 1.6),
    bodySmall: interMuted.copyWith(fontSize: OTokens.textSm, height: 1.5),
    labelLarge: inter.copyWith(
        fontSize: OTokens.textBase,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.01),
    labelMedium: interMuted.copyWith(
        fontSize: OTokens.textSm,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.05),
    labelSmall: interMuted.copyWith(
        fontSize: OTokens.textXs,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.08),
  );
}
