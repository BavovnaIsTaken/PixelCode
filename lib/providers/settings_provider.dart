/// App settings with persistence via SharedPreferences.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Keys ───────────────────────────────────────────────────────────────────

const _keyServerUrl = 'settings_server_url';
const _keyShowArkanoidButton = 'settings_show_arkanoid_button';
const _keyDeskHeight = 'settings_desk_height';
const defaultServerUrl = 'ws://localhost:9720';

// ─── Settings model ─────────────────────────────────────────────────────────

class AppSettings {
  final String serverUrl;
  final bool showArkanoidButton;
  final double deskHeight;

  const AppSettings({
    this.serverUrl = defaultServerUrl,
    this.showArkanoidButton = false,
    this.deskHeight = 74.0,
  });

  AppSettings copyWith({
    String? serverUrl,
    bool? showArkanoidButton,
    double? deskHeight,
  }) =>
      AppSettings(
        serverUrl: serverUrl ?? this.serverUrl,
        showArkanoidButton: showArkanoidButton ?? this.showArkanoidButton,
        deskHeight: deskHeight ?? this.deskHeight,
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
      serverUrl: prefs.getString(_keyServerUrl) ?? defaultServerUrl,
      showArkanoidButton: prefs.getBool(_keyShowArkanoidButton) ?? false,
      deskHeight: prefs.getDouble(_keyDeskHeight) ?? 74.0,
    );
  }

  Future<void> setServerUrl(String url) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString(_keyServerUrl, url);
    state = state.copyWith(serverUrl: url);
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
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
