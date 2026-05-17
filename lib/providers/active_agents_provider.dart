/// Tracks the server's "active agents" snapshot (sub-agent dispatches + main
/// chat queries) and exposes cancel intents for the Settings → "Активні
/// агенти" tab.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import 'ws_provider.dart';

class ActiveAgentsNotifier extends Notifier<List<ActiveAgentEntry>> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  List<ActiveAgentEntry> build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen((msg) {
      if (msg is ActiveAgentsMessage) {
        state = List.unmodifiable(msg.entries);
      }
    });
    ref.onDispose(() => _sub?.cancel());
    // Request initial snapshot — server only broadcasts on change events.
    ws.listActiveAgents();
    return const [];
  }

  /// Re-request a fresh snapshot (e.g. when the Settings tab opens).
  void refresh() => ref.read(wsServiceProvider).listActiveAgents();

  void cancelDispatch(String dispatchId) =>
      ref.read(wsServiceProvider).cancelDispatchAgent(dispatchId);

  void cancelChat(String queryId) =>
      ref.read(wsServiceProvider).cancelChatQuery(queryId);

  void cancelAll() => ref.read(wsServiceProvider).cancelAllActive();
}

final activeAgentsProvider =
    NotifierProvider<ActiveAgentsNotifier, List<ActiveAgentEntry>>(
  ActiveAgentsNotifier.new,
);
