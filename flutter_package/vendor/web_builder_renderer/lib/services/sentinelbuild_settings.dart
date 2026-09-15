import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted SentinelBuild connection settings.
///
/// Bases default to EMPTY (not a baked localhost URL) — these are
/// user-configured per deployment, and an empty base means "unconfigured"
/// rather than silently pointing at the user's own machine. On a real
/// deployment (e.g. Railway) an admin enters the real URLs; nothing here is
/// compiled to a dev port.
class SentinelBuildSettings {
  final String mitStackBase;
  final String vaultBase;
  final String? jwtToken;

  const SentinelBuildSettings({
    this.mitStackBase = '',
    this.vaultBase = '',
    this.jwtToken,
  });

  SentinelBuildSettings copyWith({
    String? mitStackBase,
    String? vaultBase,
    String? jwtToken,
    bool clearToken = false,
  }) =>
      SentinelBuildSettings(
        mitStackBase: mitStackBase ?? this.mitStackBase,
        vaultBase: vaultBase ?? this.vaultBase,
        jwtToken: clearToken ? null : (jwtToken ?? this.jwtToken),
      );

  static const _keyMitBase = 'sb_mit_base';
  static const _keyVaultBase = 'sb_vault_base';
  static const _keyToken = 'sb_token';

  static Future<SentinelBuildSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SentinelBuildSettings(
      mitStackBase: prefs.getString(_keyMitBase) ?? '',
      vaultBase: prefs.getString(_keyVaultBase) ?? '',
      jwtToken: prefs.getString(_keyToken),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMitBase, mitStackBase);
    await prefs.setString(_keyVaultBase, vaultBase);
    if (jwtToken != null) {
      await prefs.setString(_keyToken, jwtToken!);
    } else {
      await prefs.remove(_keyToken);
    }
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SentinelBuildSettingsNotifier
    extends Notifier<SentinelBuildSettings> {
  @override
  SentinelBuildSettings build() => const SentinelBuildSettings();

  Future<void> load() async {
    state = await SentinelBuildSettings.load();
  }

  Future<void> update(SentinelBuildSettings settings) async {
    state = settings;
    await settings.save();
  }

  Future<void> setToken(String token) async {
    final updated = state.copyWith(jwtToken: token);
    state = updated;
    await updated.save();
  }

  Future<void> clearToken() async {
    final updated = state.copyWith(clearToken: true);
    state = updated;
    await updated.save();
  }
}

final sentinelBuildSettingsProvider =
    NotifierProvider<SentinelBuildSettingsNotifier, SentinelBuildSettings>(
  SentinelBuildSettingsNotifier.new,
);
