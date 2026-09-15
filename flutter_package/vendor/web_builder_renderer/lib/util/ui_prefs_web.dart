// Web implementation: persists to localStorage so UI preferences survive
// reloads. All access is guarded — a privacy mode that blocks storage must
// never crash rendering.
import 'dart:html' as html;

String? loadUiPref(String key) {
  try {
    return html.window.localStorage[key];
  } catch (_) {
    return null;
  }
}

void saveUiPref(String key, String value) {
  try {
    html.window.localStorage[key] = value;
  } catch (_) {/* storage unavailable — preference just won't persist */}
}
