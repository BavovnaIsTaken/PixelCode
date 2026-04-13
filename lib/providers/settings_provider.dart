/// App settings with persistence via SharedPreferences.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Keys ───────────────────────────────────────────────────────────────────

const _keyShowArkanoidButton = 'settings_show_arkanoid_button';
const _keyDeskHeight = 'settings_desk_height';

// ─── Settings model ─────────────────────────────────────────────────────────

class AppSettings {
  final bool showArkanoidButton;
  final double deskHeight;

  const AppSettings({
    this.showArkanoidButton = false,
    this.deskHeight = 74.0,
  });

  AppSettings copyWith({
    bool? showArkanoidButton,
    double? deskHeight,
  }) =>
      AppSettings(
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
      showArkanoidButton: prefs.getBool(_keyShowArkanoidButton) ?? false,
      deskHeight: prefs.getDouble(_keyDeskHeight) ?? 74.0,
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
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
