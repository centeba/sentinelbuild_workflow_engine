// Runtime per-tenant white-label (C4). Verifies BrandConfig without building a
// full ThemeData (which pulls in GoogleFonts and can't load fonts under
// `flutter test`) — we exercise the pure-colour path via AppTheme.brandColors.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel_branding/sentinel_branding.dart';

void main() {
  test('restoration preset reproduces the static AppTheme tokens', () {
    final c = AppTheme.brandColors(BrandConfig.restoration, Brightness.light);
    expect(c.primary, AppTheme.primary);
    expect(c.primaryHover, AppTheme.primaryHover);
    expect(c.primaryLight, AppTheme.primaryLight);
    expect(c.accent, AppTheme.accent);
    expect(c.secondary, AppTheme.secondary);
    // Focus ring is the brand colour.
    expect(c.borderFocus, AppTheme.primary);
  });

  test('preset() maps every ThemeBrand to a matching-colour config', () {
    for (final b in ThemeBrand.values) {
      expect(BrandConfig.preset(b).name, b.name);
    }
    // Presets carry explicit palettes, so light/dark differ.
    final rLight = AppTheme.brandColors(BrandConfig.restoration, Brightness.light);
    final rDark = AppTheme.brandColors(BrandConfig.restoration, Brightness.dark);
    expect(rLight.primary == rDark.primary, isFalse);
  });

  test('a custom tenant brand drives primary/secondary/accent at runtime', () {
    const purple = Color(0xFF7C3AED);
    const teal = Color(0xFF0EA5A4);
    const amber = Color(0xFFF59E0B);
    const cfg = BrandConfig(
      name: 'acme', primary: purple, secondary: teal, accent: amber,
      logoUrl: 'https://cdn.acme.test/logo.svg', headingFont: 'Poppins', bodyFont: 'Roboto',
    );
    final c = AppTheme.brandColors(cfg, Brightness.light);
    expect(c.primary, purple);
    expect(c.secondary, teal);
    expect(c.accent, amber);
    expect(c.borderFocus, purple);
    expect(c.logoUrl, 'https://cdn.acme.test/logo.svg');
    expect(c.headingFont, 'Poppins');
    // Derived variants are present and contrast text is readable on the seed.
    expect(c.primaryHover, isNot(purple));
    expect(c.primaryText, const Color(0xFFFFFFFF)); // white on a dark purple
  });

  test('BrandConfig JSON round-trips', () {
    const cfg = BrandConfig(
      name: 'acme', primary: Color(0xFF112233),
      secondary: Color(0xFF445566), accent: Color(0xFF778899), logoUrl: 'x',
    );
    final back = BrandConfig.fromJson(cfg.toJson());
    expect(back.name, 'acme');
    expect(back.primary, cfg.primary);
    expect(back.secondary, cfg.secondary);
    expect(back.accent, cfg.accent);
    expect(back.logoUrl, 'x');
  });

  test('effectiveBrand prefers the custom white-label over the preset', () {
    const custom = BrandConfig(
      name: 'acme', primary: Color(0xFF7C3AED),
      secondary: Color(0xFF334155), accent: Color(0xFFE65F2D),
    );
    expect(const ThemeSettings().effectiveBrand.name, 'restoration');
    expect(
      const ThemeSettings(customBrand: custom).effectiveBrand.name,
      'acme',
    );
  });
}
