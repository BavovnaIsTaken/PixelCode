/// Riverpod provider for Kimi K2.6 (Moonshot AI) API key auth state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kimi_auth_service.dart';

export '../services/kimi_auth_service.dart' show KimiAuthStatus;

class KimiAuthNotifier extends AsyncNotifier<KimiAuthStatus> {
  @override
  Future<KimiAuthStatus> build() => KimiAuthService.checkStatus();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await KimiAuthService.checkStatus());
  }

  Future<void> saveKey(String key) async {
    await KimiAuthService.saveKey(key);
    await refresh();
  }

  Future<void> clearKey() async {
    await KimiAuthService.clearKey();
    await refresh();
  }
}

final kimiAuthProvider =
    AsyncNotifierProvider<KimiAuthNotifier, KimiAuthStatus>(
  KimiAuthNotifier.new,
);
