import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'theme.dart';

class ThemeSettings {
  final ThemeBrand brand;
  final ThemeMode mode;

  /// A runtime per-tenant white-label brand (C4). When set it overrides [brand];
  /// when null the built-in [brand] preset is used.
  final BrandConfig? customBrand;

  const ThemeSettings({
    this.brand = ThemeBrand.restoration,
    this.mode = ThemeMode.light,
    this.customBrand,
  });

  /// The brand config actually in effect — the custom white-label if present,
  /// else the selected built-in preset. Feed this to
  /// `AppTheme.buildFromConfig(settings.effectiveBrand, brightness)`.
  BrandConfig get effectiveBrand => customBrand ?? BrandConfig.preset(brand);

  ThemeSettings copyWith({ThemeBrand? brand, ThemeMode? mode}) => ThemeSettings(
        brand: brand ?? this.brand,
        mode: mode ?? this.mode,
        customBrand: customBrand,
      );

  String get modeLabel => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };
}

class ThemeNotifier extends Notifier<ThemeSettings> {
  static const _storage = FlutterSecureStorage();
  static const _keyBrand = 'sb_theme_brand';
  static const _keyMode = 'sb_theme_mode';
  static const _keyCustomBrand = 'sb_theme_custom_brand';

  @override
  ThemeSettings build() {
    _load();
    return const ThemeSettings();
  }

  Future<void> setBrand(ThemeBrand brand) async {
    await _storage.write(key: _keyBrand, value: brand.name);
    // Selecting a built-in brand clears any custom white-label.
    await _storage.delete(key: _keyCustomBrand);
    state = ThemeSettings(brand: brand, mode: state.mode);
  }

  Future<void> setMode(ThemeMode mode) async {
    await _storage.write(key: _keyMode, value: _modeKey(mode));
    state = state.copyWith(mode: mode);
  }

  /// Apply a runtime per-tenant white-label brand (C4). Persists it so it
  /// survives restarts; pass null to clear back to the built-in [brand].
  Future<void> setCustomBrand(BrandConfig? config) async {
    if (config == null) {
      await _storage.delete(key: _keyCustomBrand);
    } else {
      await _storage.write(key: _keyCustomBrand, value: jsonEncode(config.toJson()));
    }
    state = ThemeSettings(brand: state.brand, mode: state.mode, customBrand: config);
  }

  Future<void> _load() async {
    final brandStr = await _storage.read(key: _keyBrand);
    final modeStr = await _storage.read(key: _keyMode);
    final customStr = await _storage.read(key: _keyCustomBrand);
    BrandConfig? custom;
    if (customStr != null) {
      try {
        custom = BrandConfig.fromJson(jsonDecode(customStr) as Map<String, dynamic>);
      } catch (_) {
        custom = null; // ignore corrupt stored config
      }
    }
    if (brandStr == null || modeStr == null) {
      await _storage.write(key: _keyBrand, value: ThemeBrand.restoration.name);
      await _storage.write(key: _keyMode, value: 'light');
      if (custom != null) state = ThemeSettings(customBrand: custom);
      return;
    }
    state = ThemeSettings(
      brand: ThemeBrand.fromString(brandStr),
      mode: _parseMode(modeStr),
      customBrand: custom,
    );
  }

  static String _modeKey(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode _parseMode(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.light, // default to light — matches ThemeSettings default
      };
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeSettings>(ThemeNotifier.new);
