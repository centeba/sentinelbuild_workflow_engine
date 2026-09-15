// Non-web fallback: in-memory only (does not persist across restarts).
final Map<String, String> _mem = {};

String? loadUiPref(String key) => _mem[key];

void saveUiPref(String key, String value) {
  _mem[key] = value;
}
