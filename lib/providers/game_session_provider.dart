/// Multi-device session presence provider.
///
/// Tracks whether this client is the primary (write-capable) device or a
/// viewer. Takeover is fully automatic — no user interaction required.
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

  /// WebSocket is disconnected — playing locally.
  offline,
}

class GameSessionState {
  final GameSessionMode mode;

  /// Device name of the current primary (populated in viewer mode).
  final String? primaryDevice;

  const GameSessionState({
    this.mode = GameSessionMode.offline,
    this.primaryDevice,
  });

  bool get canWrite =>
      mode == GameSessionMode.sole || mode == GameSessionMode.primary;

  GameSessionState copyWith({
    GameSessionMode? mode,
    String? primaryDevice,
    bool clearPrimaryDevice = false,
  }) =>
      GameSessionState(
        mode: mode ?? this.mode,
        primaryDevice:
            clearPrimaryDevice ? null : (primaryDevice ?? this.primaryDevice),
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
        state = const GameSessionState(mode: GameSessionMode.offline);
      }
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
        final newMode = isAlone
            ? GameSessionMode.sole
            : mode == SessionMode.primary
                ? GameSessionMode.primary
                : GameSessionMode.viewer;
        state = GameSessionState(mode: newMode, primaryDevice: primaryDevice);
        // Auto-claim: silently become primary without user interaction.
        if (newMode == GameSessionMode.viewer) _claimSession();

      case SessionTakenMessage():
        // Flip to viewer immediately so canWrite goes false.
        // Server will follow up with session_status → viewer, which also calls _claimSession().
        state = state.copyWith(mode: GameSessionMode.viewer);

      default:
        break;
    }
  }

  void _claimSession() {
    if (state.canWrite) return;
    ref.read(wsServiceProvider).claimSession();
  }

  /// Voluntarily release the primary session.
  void releaseSession() {
    if (!state.canWrite) return;
    ref.read(wsServiceProvider).releaseSession();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final gameSessionProvider =
    NotifierProvider<GameSessionNotifier, GameSessionState>(
  GameSessionNotifier.new,
);
