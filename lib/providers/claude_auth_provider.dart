/// Riverpod provider for Claude OAuth auth state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/claude_auth_service.dart';

export '../services/claude_auth_service.dart' show ClaudeAuthStatus;

class ClaudeAuthNotifier extends AsyncNotifier<ClaudeAuthStatus> {
  @override
  Future<ClaudeAuthStatus> build() => ClaudeAuthService.checkStatus();

  /// Re-check auth status (e.g. after login/logout).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await ClaudeAuthService.checkStatus());
  }

  /// Launch OAuth login flow, then refresh status.
  Future<void> login() async {
    await ClaudeAuthService.login();
    await refresh();
  }

  /// Logout, then refresh status.
  Future<void> logout() async {
    await ClaudeAuthService.logout();
    await refresh();
  }
}

final claudeAuthProvider =
    AsyncNotifierProvider<ClaudeAuthNotifier, ClaudeAuthStatus>(
  ClaudeAuthNotifier.new,
);
