// Intentionally empty.
//
// Upstream lucide_icons 0.257.0 defined `class LucideIconData extends IconData`
// here, which no longer compiles ("IconData can't be extended ... it's a final
// class"). The vendored icon map in ../lucide_icons.dart now uses plain
// `const IconData(...)` directly, so this helper is no longer referenced.
// Kept as an empty file so any stray import still resolves.
