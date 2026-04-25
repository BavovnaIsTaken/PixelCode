/// Provider for local-server configuration (apiKey, autoStart preference).
///
/// The actual server lifecycle (spawn / restart / kill) lives outside the
/// app — the launcher daemon (server/src/launcher.ts) owns it, the PixelDock
/// admin app drives it. This file only persists the user's preferences.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/local_server_config.dart';
import 'settings_provider.dart';

export '../models/local_server_config.dart';

const _keyLocalServer = 'local_server_config';

// ─── Config notifier ─────────────────────────────────────────────────────────

class LocalServerNotifier extends Notifier<LocalServerConfig> {
  @override
  LocalServerConfig build() {
    final raw = ref.read(sharedPrefsProvider).getString(_keyLocalServer);
    return raw != null ? LocalServerConfig.decode(raw) : const LocalServerConfig();
  }

  Future<void> _save(LocalServerConfig config) async {
    state = config;
    await ref.read(sharedPrefsProvider).setString(_keyLocalServer, config.encode());
  }

  Future<void> setApiKey(String? key) async {
    final trimmed = key?.trim();
    await _save(state.copyWith(apiKey: () => (trimmed?.isEmpty ?? true) ? null : trimmed));
  }

  Future<void> setAutoStart(bool value) async =>
      _save(state.copyWith(autoStart: value));

  /// Migrates an apiKey that was previously stored on a SessionProfile.
  /// Only called once during first launch if no config exists yet.
  Future<void> migrateApiKey(String apiKey) async {
    if (state.hasApiKey) return; // already configured
    await _save(state.copyWith(apiKey: () => apiKey, autoStart: true));
  }
}

final localServerProvider =
    NotifierProvider<LocalServerNotifier, LocalServerConfig>(
  LocalServerNotifier.new,
);
