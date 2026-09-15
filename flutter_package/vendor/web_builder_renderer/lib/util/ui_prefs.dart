// Tiny key/value store for lightweight UI preferences (e.g. which collapsible
// sections a user has open). Web uses localStorage so the choice persists
// across reloads; other platforms fall back to an in-memory map. Conditional
// import keeps the renderer package portable (no hard dart:html dependency).
import 'ui_prefs_stub.dart' if (dart.library.html) 'ui_prefs_web.dart' as impl;

/// Returns the stored string for [key], or null if unset / unavailable.
String? loadUiPref(String key) => impl.loadUiPref(key);

/// Persists [value] under [key]. Best-effort; never throws.
void saveUiPref(String key, String value) => impl.saveUiPref(key, value);
