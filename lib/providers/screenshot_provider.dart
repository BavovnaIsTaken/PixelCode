/// Device screenshot state — one-click capture from the deploy popover toolbar.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import 'agent_provider.dart';
import 'android_deploy_provider.dart';

enum ScreenshotPhase { idle, capturing, ready, error }

class ScreenshotState {
  final ScreenshotPhase phase;
  final String? url;
  final String? platform;
  final String? error;

  const ScreenshotState({
    this.phase = ScreenshotPhase.idle,
    this.url,
    this.platform,
    this.error,
  });

  ScreenshotState copyWith({
    ScreenshotPhase? phase,
    String? url,
    String? platform,
    String? error,
    bool clearUrl = false,
    bool clearError = false,
  }) =>
      ScreenshotState(
        phase: phase ?? this.phase,
        url: clearUrl ? null : (url ?? this.url),
        platform: platform ?? this.platform,
        error: clearError ? null : (error ?? this.error),
      );
}

class ScreenshotNotifier extends Notifier<ScreenshotState> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  ScreenshotState build() {
    ref.onDispose(() => _sub?.cancel());
    return const ScreenshotState();
  }

  void capture({required String platform}) {
    if (state.phase == ScreenshotPhase.capturing) return;

    final ws = ref.read(wsServiceProvider);
    if (!ws.isConnected) {
      state = state.copyWith(
        phase: ScreenshotPhase.error,
        error: 'Немає з\'єднання з сервером',
        platform: platform,
      );
      return;
    }

    String? serial;
    if (platform == 'android') {
      serial = ref.read(androidDeployProvider).selectedSerial;
    }

    _sub?.cancel();
    _sub = ws.messages.listen((msg) {
      if (msg is ScreenshotStatusMessage && msg.platform == platform) {
        if (msg.subtype == 'ready' && msg.url != null) {
          state = state.copyWith(
            phase: ScreenshotPhase.ready,
            url: msg.url,
            platform: platform,
            clearError: true,
          );
          _sub?.cancel();
          _sub = null;
        } else if (msg.subtype == 'error') {
          state = state.copyWith(
            phase: ScreenshotPhase.error,
            error: msg.message ?? 'Помилка',
            platform: platform,
            clearUrl: true,
          );
          _sub?.cancel();
          _sub = null;
        }
      }
    });

    state = ScreenshotState(
      phase: ScreenshotPhase.capturing,
      platform: platform,
    );
    ws.captureScreenshot(platform: platform, deviceSerial: serial);

    // Safety timeout
    Future.delayed(const Duration(seconds: 15), () {
      if (state.phase == ScreenshotPhase.capturing) {
        _sub?.cancel();
        _sub = null;
        state = state.copyWith(
          phase: ScreenshotPhase.error,
          error: 'Таймаут скріншоту',
        );
      }
    });
  }

  void dismiss() {
    _sub?.cancel();
    _sub = null;
    state = const ScreenshotState();
  }
}

final screenshotProvider =
    NotifierProvider<ScreenshotNotifier, ScreenshotState>(
        ScreenshotNotifier.new);
