// Drift guard: the restoration palette in theme.dart is hand-maintained to
// mirror pd-design-tokens (the const blocks + the public static AppTheme.*
// tokens were transcribed from tokens/brand/restoration.json). This test
// asserts the public restoration-light static tokens still equal the generated
// `pd_tokens.gen.dart`, so a token regeneration that isn't reflected here fails
// CI instead of silently drifting the chassis brand away from the restoration +
// technician apps.
//
// We compare the static `AppTheme.*` tokens (not `AppTheme.build(...)`, which
// pulls in GoogleFonts and can't load font assets under `flutter test`). Those
// statics are restoration-light and are what custom widgets read directly.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel_branding/sentinel_branding.dart';
import 'package:sentinel_branding/src/pd_tokens.gen.dart';

void main() {
  test('AppTheme static tokens match restoration-light generated tokens', () {
    final pd = pdPalette(PdBrand.restoration, Brightness.light);
    expect(AppTheme.primary, pd.brand, reason: 'brand (teal) drifted');
    expect(AppTheme.primaryHover, pd.brandHover);
    expect(AppTheme.primaryLight, pd.brandLight);
    expect(AppTheme.accent, pd.accent, reason: 'accent (orange) drifted');
    expect(AppTheme.error, pd.errorBase);
    expect(AppTheme.success, pd.successBase);
    expect(AppTheme.warning, pd.warningBase);
    expect(AppTheme.textPrimary, pd.textPrimary);
    expect(AppTheme.textSecondary, pd.textSecondary);
    expect(AppTheme.bgPage, pd.bgPage);
    expect(AppTheme.borderSubtle, pd.borderSubtle);
    expect(AppTheme.borderFocus, pd.brand);
  });

  test('restoration is the default brand', () {
    expect(const ThemeSettings().brand, ThemeBrand.restoration);
    expect(ThemeBrand.fromString(null), ThemeBrand.restoration);
    expect(ThemeBrand.fromString('finance'), ThemeBrand.finance);
  });
}
