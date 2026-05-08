/// Tech-lead pulse provider — streams the server's task-completion digest
/// into a Riverpod state shape the Hub strip can subscribe to.
///
/// The provider:
///   - Pulls a fresh snapshot on first build (`get_tech_lead_pulse`)
///   - Listens for unsolicited `tech_lead_pulse` broadcasts (server pushes
///     one on every new completion)
///   - Replaces state with each new payload (server is authoritative)
///
/// The strip widget treats an empty list as "nothing finished yet — hide".
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import 'ws_provider.dart';

class TechLeadPulseNotifier
    extends Notifier<List<TechLeadPulseEntry>> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  List<TechLeadPulseEntry> build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen((msg) {
      if (msg is TechLeadPulseMessage) {
        state = List.unmodifiable(msg.entries);
      }
    });
    ref.onDispose(() => _sub?.cancel());
    // Ask the server to push the current snapshot. Server always replies,
    // even with empty entries, so the loading state resolves cleanly.
    ws.getTechLeadPulse(limit: 20);
    return const [];
  }
}

final techLeadPulseProvider =
    NotifierProvider<TechLeadPulseNotifier, List<TechLeadPulseEntry>>(
  TechLeadPulseNotifier.new,
);
