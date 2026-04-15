/// App settings with persistence via SharedPreferences.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Keys ───────────────────────────────────────────────────────────────────

const _keyShowArkanoidButton = 'settings_show_arkanoid_button';
const _keyDeskHeight = 'settings_desk_height';
const _keyGlitchEnabled = 'settings_glitch_enabled';
const _keyGlitchIntensity = 'settings_glitch_intensity';
const _keyGlitchSpeed = 'settings_glitch_speed';
const _keyNickname = 'settings_nickname';

// ─── Settings model ─────────────────────────────────────────────────────────

class AppSettings {
  final bool showArkanoidButton;
  final double deskHeight;
  final bool glitchEnabled;

  /// Fraction of pixel blocks affected during glitch (0.01–0.30).
  final double glitchIntensity;

  /// Animation speed multiplier (0.5–3.0). Higher = faster.
  final double glitchSpeed;
  final String nickname;

  const AppSettings({
    this.showArkanoidButton = false,
    this.deskHeight = 74.0,
    this.glitchEnabled = true,
    this.glitchIntensity = 0.06,
    this.glitchSpeed = 1.0,
    this.nickname = '',
  });

  AppSettings copyWith({
    bool? showArkanoidButton,
    double? deskHeight,
    bool? glitchEnabled,
    double? glitchIntensity,
    double? glitchSpeed,
    String? nickname,
  }) =>
      AppSettings(
        showArkanoidButton: showArkanoidButton ?? this.showArkanoidButton,
        deskHeight: deskHeight ?? this.deskHeight,
        glitchEnabled: glitchEnabled ?? this.glitchEnabled,
        glitchIntensity: glitchIntensity ?? this.glitchIntensity,
        glitchSpeed: glitchSpeed ?? this.glitchSpeed,
        nickname: nickname ?? this.nickname,
      );
}

// ─── SharedPreferences instance ─────────────────────────────────────────────

final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden at startup');
});

// ─── Settings notifier ──────────────────────────────────────────────────────

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final prefs = ref.read(sharedPrefsProvider);
    return AppSettings(
      showArkanoidButton: prefs.getBool(_keyShowArkanoidButton) ?? false,
      deskHeight: prefs.getDouble(_keyDeskHeight) ?? 74.0,
      glitchEnabled: prefs.getBool(_keyGlitchEnabled) ?? true,
      glitchIntensity: prefs.getDouble(_keyGlitchIntensity) ?? 0.06,
      glitchSpeed: prefs.getDouble(_keyGlitchSpeed) ?? 1.0,
      nickname: prefs.getString(_keyNickname) ?? '',
    );
  }

  Future<void> setShowArkanoidButton(bool value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_keyShowArkanoidButton, value);
    state = state.copyWith(showArkanoidButton: value);
  }

  Future<void> setDeskHeight(double value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setDouble(_keyDeskHeight, value);
    state = state.copyWith(deskHeight: value);
  }

  Future<void> setGlitchEnabled(bool value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_keyGlitchEnabled, value);
    state = state.copyWith(glitchEnabled: value);
  }

  Future<void> setGlitchIntensity(double value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setDouble(_keyGlitchIntensity, value);
    state = state.copyWith(glitchIntensity: value);
  }

  Future<void> setGlitchSpeed(double value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setDouble(_keyGlitchSpeed, value);
    state = state.copyWith(glitchSpeed: value);
  }

  Future<void> setNickname(String value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString(_keyNickname, value);
    state = state.copyWith(nickname: value);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
