/// Long-lived simulation engine for the pixel-art office canvas.
///
/// Owns the [OfficeGameState] and the per-frame [Ticker]. Decoupling these
/// from the [AgentCanvas] widget means the office keeps simulating even while
/// the canvas widget is destroyed/recreated by the Flutter tree (e.g. during
/// shutdown animations, layout swaps, or AnimatedSwitcher transitions).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../models/game_economy.dart';
import '../providers/agent_provider.dart';
import '../widgets/canvas/office_game_state.dart';

class OfficeSimulationService {
  /// Mutable game state — updated in place every frame by [_onTick].
  /// Exposed directly so view code (painters, hit-testing) can read positions
  /// without going through ChangeNotifier ceremony for every property access.
  final OfficeGameState gameState;

  /// Increments once per simulation frame. Use as the `repaint:` listenable
  /// of [CustomPaint] to trigger paints without rebuilding parent widgets.
  final ValueNotifier<int> frame = ValueNotifier(0);

  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  bool _disposed = false;

  /// Guard for synchronizing WebSocket callbacks (async) with game loop ticks.
  /// Prevents ConcurrentModificationException when applyRemotePositions runs
  /// concurrently with gameState.update() reading characters.
  bool _isUpdating = false;

  OfficeSimulationService({
    OfficeGameState? gameState,
    bool autoStart = true,
  }) : gameState = gameState ?? OfficeGameState() {
    if (autoStart) {
      _ticker = Ticker(_onTick)..start();
    }
  }

  /// Drives a single simulation step manually. Used in tests in place of
  /// the real [Ticker]; production code relies on [_onTick] via the ticker.
  @visibleForTesting
  void debugStep(Duration elapsed) => _onTick(elapsed);

  void _onTick(Duration elapsed) {
    _isUpdating = true;
    try {
      final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
      _lastElapsed = elapsed;
      gameState.update(dt.clamp(0.0, 0.1));
      frame.value++;
    } finally {
      _isUpdating = false;
    }
  }

  // ── Mode transitions ──────────────────────────────────────────────────

  /// Switch to local autonomous wander — used while the WebSocket is offline
  /// or while the app is shutting down. Active tasks cancel; agents wander
  /// at a calmer pace until the connection is re-established.
  void enterAutonomousWander() => gameState.enterAutonomousWander();

  /// Restore network-driven mode after [enterAutonomousWander]. Characters
  /// near the entrance wake first (staggered), so the office naturally fills
  /// from the door inward when reconnecting.
  void wakeUp() => gameState.wakeUpStaggered();

  // ── Provider-driven sync passthroughs ─────────────────────────────────

  /// Sync agent states from provider into game characters.
  /// THREAD-SAFE: Defers the sync until the game loop tick is complete,
  /// preventing race conditions between syncAgents and gameState.update().
  void syncAgents(Map<String, AgentState> agents) {
    // If game loop is currently running, wait for it to finish before syncing.
    // This prevents ConcurrentModificationException when provider update (async)
    // tries to modify characters map during a game loop iteration.
    if (_isUpdating) {
      Future.delayed(const Duration(milliseconds: 1), () {
        if (!_disposed) gameState.syncAgents(agents);
      });
    } else {
      gameState.syncAgents(agents);
    }
  }

  List<String> syncHired(
    List<String> hiredIds, [
    Map<String, HardwareTier>? hardwareMap,
    Map<String, WorkplaceStatus>? workplaceStatusMap,
  ]) =>
      gameState.syncHiredAgents(hiredIds, hardwareMap, workplaceStatusMap);

  void rebuildLayout(
    OfficeLevel newLevel,
    int newExpansions,
    List<PlacedRoom> newRooms, [
    List<FurniturePlacement> newFurniture = const [],
    List<PlacedCorridor> newCorridors = const [],
  ]) =>
      gameState.rebuildLayout(
          newLevel, newExpansions, newRooms, newFurniture, newCorridors);

  // ── Network-sync passthroughs (broadcast/receive lives in provider) ──

  Map<String, Map<String, dynamic>> serializePositions() =>
      gameState.serializePositions();

  /// Apply remote positions from WebSocket callback (async context).
  /// THREAD-SAFE: Defers the update until the game loop tick is complete,
  /// preventing race conditions between applyRemotePositions and gameState.update().
  void applyRemotePositions(
    Map<String,
            ({int col, int row, String state, String dir, bool onSkateboard})>
        remote,
  ) {
    // If game loop is currently running, wait for it to finish before applying.
    // This prevents ConcurrentModificationException when WebSocket callback
    // (async) tries to modify characters map during a game loop iteration.
    if (_isUpdating) {
      Future.delayed(const Duration(milliseconds: 1), () {
        if (!_disposed) gameState.applyRemotePositions(remote);
      });
    } else {
      gameState.applyRemotePositions(remote);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker?.dispose();
    _ticker = null;
    frame.dispose();
  }
}
