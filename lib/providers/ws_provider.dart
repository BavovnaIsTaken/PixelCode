/// WebSocket service and derived stream providers.
///
/// Extracted into its own file to break the circular import between
/// agent_provider.dart (which watches gameEconomyProvider) and
/// game_economy_provider.dart (which needs wsServiceProvider).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import '../services/agent_ws_service.dart';

// ─── WebSocket Service ────────────────────────────────────────────────────────

final wsServiceProvider = Provider<AgentWsService>((ref) {
  final service = AgentWsService();
  ref.onDispose(() => service.dispose());
  return service;
});

// ─── Connection Status ────────────────────────────────────────────────────────

final connectionStatusProvider = StreamProvider<bool>((ref) {
  return ref.watch(wsServiceProvider).connectionStatus;
});

/// Short status token (≤5 chars) for the in-flight connection terminal widget.
/// `null` = connected/idle (terminal hides itself).
final connectionPhaseProvider = StreamProvider<String?>((ref) {
  return ref.watch(wsServiceProvider).phaseStatus;
});

// ─── All server messages ──────────────────────────────────────────────────────

final serverMessagesProvider = StreamProvider<ServerMessage>((ref) {
  return ref.watch(wsServiceProvider).messages;
});
