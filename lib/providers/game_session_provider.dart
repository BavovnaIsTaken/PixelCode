/// Multi-device session presence provider.
///
/// Tracks whether this client is the primary (write-capable) device or a
/// viewer, and surfaces takeover requests so the UI can react.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import 'ws_provider.dart';

// ─── State ────────────────────────────────────────────────────────────────────

enum GameSessionMode {
  /// Only device connected — full write access.
  sole,

  /// Multiple devices; this one is the active primary.
  primary,

  /// Another device holds the primary session. Read-only view.
  viewer,

  /// This device sent a takeover request and is waiting for the primary.
  takeoverPending,

  /// WebSocket is disconnected — playing locally.
  offline,
}

class GameSessionState {
  final GameSessionMode mode;

  /// Device name of the current primary (populated in viewer/takeoverPending).
  final String? primaryDevice;

  /// Device that requested to take over (populated in primary mode when request arrives).
  final String? takeoverRequestFrom;

  const GameSessionState({
    this.mode = GameSessionMode.offline,
    this.primaryDevice,
    this.takeoverRequestFrom,
  });

  bool get canWrite =>
      mode == GameSessionMode.sole || mode == GameSessionMode.primary;

  GameSessionState copyWith({
    GameSessionMode? mode,
    String? primaryDevice,
    String? takeoverRequestFrom,
    bool clearTakeoverRequest = false,
    bool clearPrimaryDevice = false,
  }) =>
      GameSessionState(
        mode: mode ?? this.mode,
        primaryDevice: clearPrimaryDevice ? null : (primaryDevice ?? this.primaryDevice),
        takeoverRequestFrom: clearTakeoverRequest
            ? null
            : (takeoverRequestFrom ?? this.takeoverRequestFrom),
      );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class GameSessionNotifier extends Notifier<GameSessionState> {
  StreamSubscription<ServerMessage>? _msgSub;
  StreamSubscription<bool>? _connSub;

  @override
  GameSessionState build() {
    final ws = ref.watch(wsServiceProvider);

    _msgSub?.cancel();
    _msgSub = ws.messages.listen(_onMessage);

    _connSub?.cancel();
    _connSub = ws.connectionStatus.listen((connected) {
      if (!connected) {
        state = GameSessionState(mode: GameSessionMode.offline);
      }
      // When reconnecting, the server will push session_status — no action needed here.
    });

    ref.onDispose(() {
      _msgSub?.cancel();
      _connSub?.cancel();
    });

    return const GameSessionState(mode: GameSessionMode.offline);
  }

  void _onMessage(ServerMessage msg) {
    switch (msg) {
      case SessionStatusMessage(:final mode, :final primaryDevice):
        final isAlone = mode == SessionMode.primary && primaryDevice == null;
        state = GameSessionState(
          mode: isAlone
              ? GameSessionMode.sole
              : mode == SessionMode.primary
                  ? GameSessionMode.primary
                  : GameSessionMode.viewer,
          primaryDevice: primaryDevice,
        );

      case SessionTakeoverRequestMessage(:final fromDevice):
        // We are primary; a viewer is asking to take over.
        state = state.copyWith(takeoverRequestFrom: fromDevice);

      case SessionTakenMessage():
        // We were primary but session was transferred away.
        state = state.copyWith(
          mode: GameSessionMode.viewer,
          clearTakeoverRequest: true,
        );

      default:
        break;
    }
  }

  /// Request to become primary (only valid from viewer mode).
  void claimSession() {
    if (state.mode != GameSessionMode.viewer) return;
    state = state.copyWith(mode: GameSessionMode.takeoverPending);
    ref.read(wsServiceProvider).claimSession();
  }

  /// Voluntarily release the primary session (e.g. user tapped "Let other device in").
  void releaseSession() {
    if (!state.canWrite) return;
    ref.read(wsServiceProvider).releaseSession();
    // State will update when server sends session_status to the new primary.
  }

  /// Dismiss the incoming takeover request without yielding (user chose to keep playing).
  void dismissTakeoverRequest() {
    state = state.copyWith(clearTakeoverRequest: true);
  }

}

// ─── Provider ─────────────────────────────────────────────────────────────────

final gameSessionProvider =
    NotifierProvider<GameSessionNotifier, GameSessionState>(
  GameSessionNotifier.new,
);
