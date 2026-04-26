/// Riverpod provider for Gemini OAuth auth state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/gemini_auth_service.dart';

export '../services/gemini_auth_service.dart' show GeminiAuthStatus;

class GeminiAuthNotifier extends AsyncNotifier<GeminiAuthStatus> {
  @override
  Future<GeminiAuthStatus> build() => GeminiAuthService.checkStatus();

  /// Re-check auth status (e.g. after login/logout).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await GeminiAuthService.checkStatus());
  }

  /// Launch OAuth login flow, then refresh status.
  Future<void> login() async {
    await GeminiAuthService.login();
    await refresh();
  }

  /// Logout, then refresh status.
  Future<void> logout() async {
    await GeminiAuthService.logout();
    await refresh();
  }
}

final geminiAuthProvider =
    AsyncNotifierProvider<GeminiAuthNotifier, GeminiAuthStatus>(
  GeminiAuthNotifier.new,
);
