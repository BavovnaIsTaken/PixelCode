/// Provider for local server configuration and running-status stream.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/local_server_config.dart';
import 'agent_provider.dart' show serverProcessProvider;
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

// ─── Running-status stream ────────────────────────────────────────────────────

/// Emits `true` while the local server process is running, `false` otherwise.
/// Only meaningful on macOS/desktop.
final serverRunningProvider = StreamProvider<bool>((ref) {
  if (Platform.isIOS || Platform.isAndroid) {
    return const Stream.empty();
  }
  return ref.watch(serverProcessProvider).runningStatus;
});
