/// Riverpod provider for Gemini OAuth auth state.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/gemini_auth_service.dart';

export '../services/gemini_auth_service.dart' show GeminiAuthStatus;

class GeminiAuthNotifier extends AsyncNotifier<GeminiAuthStatus> {
  Timer? _pollTimer;

  @override
  Future<GeminiAuthStatus> build() {
    ref.onDispose(_cancelPolling);
    return GeminiAuthService.checkStatus();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await GeminiAuthService.checkStatus());
  }

  /// Spawns a terminal with `gemini` for interactive OAuth, then polls
  /// `~/.gemini/oauth_creds.json` for up to ~3 minutes until creds appear.
  Future<void> login() async {
    final launched = await GeminiAuthService.login();
    if (!launched) {
      await refresh();
      return;
    }

    final initialMtime = _credsMtime();
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    _cancelPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (DateTime.now().isAfter(deadline)) {
        timer.cancel();
        _pollTimer = null;
        return;
      }
      final mtime = _credsMtime();
      if (mtime != null && (initialMtime == null || mtime.isAfter(initialMtime))) {
        timer.cancel();
        _pollTimer = null;
        await refresh();
      }
    });
  }

  Future<void> logout() async {
    _cancelPolling();
    await GeminiAuthService.logout();
    await refresh();
  }

  DateTime? _credsMtime() {
    try {
      final file = GeminiAuthService.oauthCredsFile;
      if (!file.existsSync()) return null;
      return file.statSync().modified;
    } catch (_) {
      return null;
    }
  }

  void _cancelPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}

final geminiAuthProvider =
    AsyncNotifierProvider<GeminiAuthNotifier, GeminiAuthStatus>(
  GeminiAuthNotifier.new,
);
