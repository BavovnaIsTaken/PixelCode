/// App settings with persistence via SharedPreferences.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Keys ───────────────────────────────────────────────────────────────────

const _keyServerUrl = 'settings_server_url';
const _keyShowArkanoidButton = 'settings_show_arkanoid_button';
const defaultServerUrl = 'ws://localhost:9720';

// ─── Settings model ─────────────────────────────────────────────────────────

class AppSettings {
  final String serverUrl;
  final bool showArkanoidButton;

  const AppSettings({
    this.serverUrl = defaultServerUrl,
    this.showArkanoidButton = false,
  });

  AppSettings copyWith({String? serverUrl, bool? showArkanoidButton}) =>
      AppSettings(
        serverUrl: serverUrl ?? this.serverUrl,
        showArkanoidButton: showArkanoidButton ?? this.showArkanoidButton,
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
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
