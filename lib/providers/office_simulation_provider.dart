/// Long-lived provider that owns the [OfficeSimulationService].
///
/// Wires the simulation engine into the rest of the app:
///   • connection-status → autonomous-wander / wake-up transitions
///   • gameEconomy → layout rebuild + hired-roster sync
///   • agentsProvider → per-tick agent-state sync
///   • WebSocket → periodic position broadcast + remote-position apply
///
/// The provider is created on first read and lives for the duration of the
/// [ProviderContainer] (i.e. the app process). The simulation never restarts
/// across view rebuilds — that's the whole point of lifting it up here.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import '../models/game_economy.dart';
import '../services/office_simulation_service.dart';
import 'agent_provider.dart';
import 'game_economy_provider.dart';

final officeSimulationProvider = Provider<OfficeSimulationService>((ref) {
  final service = OfficeSimulationService();

  // ── Connection-status → simulation mode ─────────────────────────────────
  ref.listen<AsyncValue<bool>>(connectionStatusProvider, (prev, next) {
    final wasConnected = prev?.valueOrNull ?? false;
    final isConnected = next.valueOrNull ?? false;
    if (!wasConnected && isConnected) {
      service.wakeUp();
    } else if (wasConnected && !isConnected) {
      service.enterAutonomousWander();
    }
  });
  // Initial mode: if the socket isn't up yet, start in autonomous wander so
  // the office is alive from the very first frame.
  final initiallyConnected =
      ref.read(connectionStatusProvider).valueOrNull ?? false;
  if (!initiallyConnected) service.enterAutonomousWander();

  // ── gameEconomy → layout rebuild + hired-roster sync ────────────────────
  // Cache the last layout inputs so we only rebuild the tile map when one
  // actually changes — rebuilding is O(rows * cols) and clears wandering
  // state.
  OfficeLevel? lastLevel;
  List<PlacedRoom>? lastRooms;
  List<FurniturePlacement>? lastFurniture;
  List<PlacedCorridor>? lastCorridors;

  void onEconomy(GameState econ) {
    if (lastLevel != econ.officeLevel ||
        !identical(lastRooms, econ.placedRooms) ||
        !identical(lastFurniture, econ.placedFurniture) ||
        !identical(lastCorridors, econ.placedCorridors)) {
      lastLevel = econ.officeLevel;
      lastRooms = econ.placedRooms;
      lastFurniture = econ.placedFurniture;
      lastCorridors = econ.placedCorridors;
      service.rebuildLayout(
        econ.officeLevel,
        econ.placedRooms,
        econ.placedFurniture,
        econ.placedCorridors,
      );
    }

    final hardwareMap = {
      for (final e in econ.agents.entries) e.key: e.value.hardware,
    };
    final workplaceStatusMap = {
      for (final e in econ.agents.entries) e.key: e.value.workplaceStatus,
    };
    final newlyAssigned = service.syncHired(
      econ.hiredAgentIds,
      hardwareMap,
      workplaceStatusMap,
    );
    if (newlyAssigned.isNotEmpty) {
      // Defer the mutation: ref.listen(..., fireImmediately: true) calls
      // this synchronously during provider creation, and Riverpod forbids
      // mutating another provider mid-init.
      Future.microtask(() {
        final notifier = ref.read(gameEconomyProvider.notifier);
        for (final id in newlyAssigned) {
          notifier.assignWorkplace(id);
        }
      });
    }
  }

  ref.listen<GameState>(
    gameEconomyProvider,
    (_, next) => onEconomy(next),
    fireImmediately: true,
  );

  // ── agentsProvider → per-frame agent-state sync ─────────────────────────
  ref.listen<Map<String, AgentState>>(
    agentsProvider,
    (_, next) => service.syncAgents(next),
    fireImmediately: true,
  );

  // ── WebSocket position broadcast + remote-positions apply ───────────────
  final ws = ref.read(wsServiceProvider);
  final posSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
    if (ws.isConnected) {
      ws.syncPositions(service.serializePositions());
    }
  });
  final msgSub = ws.messages.listen((msg) {
    if (msg is PositionsSyncMessage) {
      service.applyRemotePositions({
        for (final e in msg.positions.entries)
          e.key: (
            col: e.value.col,
            row: e.value.row,
            state: e.value.state,
            dir: e.value.dir,
            onSkateboard: e.value.onSkateboard,
          ),
      });
    }
  });

  ref.onDispose(() {
    posSyncTimer.cancel();
    msgSub.cancel();
    service.dispose();
  });

  return service;
});
