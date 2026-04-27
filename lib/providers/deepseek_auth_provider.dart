/// Riverpod provider for DeepSeek API key auth state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/deepseek_auth_service.dart';

export '../services/deepseek_auth_service.dart' show DeepSeekAuthStatus;

class DeepSeekAuthNotifier extends AsyncNotifier<DeepSeekAuthStatus> {
  @override
  Future<DeepSeekAuthStatus> build() => DeepSeekAuthService.checkStatus();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await DeepSeekAuthService.checkStatus());
  }

  Future<void> saveKey(String key) async {
    await DeepSeekAuthService.saveKey(key);
    await refresh();
  }

  Future<void> clearKey() async {
    await DeepSeekAuthService.clearKey();
    await refresh();
  }
}

final deepseekAuthProvider =
    AsyncNotifierProvider<DeepSeekAuthNotifier, DeepSeekAuthStatus>(
  DeepSeekAuthNotifier.new,
);
