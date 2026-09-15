// mit_stack's design system is now the shared `sentinel_branding` package —
// it previously kept a full byte-for-byte duplicate of AppTheme / ThemeBrand
// / _Palette here, which drifted from the chassis. This file re-exports the
// canonical symbols so all ~925 `AppTheme.*` and `ThemeBrand` references in
// mit_stack resolve to the unified, restoration-default (teal) tokens with no
// call-site changes.
//
// `themeProvider` / `ThemeSettings` / `ThemeNotifier` are intentionally
// HIDDEN from this re-export: mit_stack doesn't drive theme state itself (the
// chassis uses sentinel_branding's provider directly), so leaking those names
// through mit_stack's surface would only invite accidental, conflicting use.
export 'package:sentinel_branding/sentinel_branding.dart'
    hide themeProvider, ThemeSettings, ThemeNotifier;
