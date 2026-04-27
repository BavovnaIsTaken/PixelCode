/// Fake WebSocket service for testing GameEconomyNotifier without real connections.
library;

import 'dart:async';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

/// Minimal fake that satisfies the wsServiceProvider contract.
///
/// Returns empty/offline streams so notifier can initialize without real WS.
class FakeAgentWsService extends AgentWsService {
  @override
  Stream<ServerMessage> get messages => const Stream.empty();

  @override
  Stream<bool> get connectionStatus async* {
    yield false;
  }

  @override
  Stream<String> get connectionLog => const Stream.empty();

  @override
  Stream<String?> get phaseStatus async* {
    yield null;
  }

  @override
  Future<void> dispose() async {}
}
