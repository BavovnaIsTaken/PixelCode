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

/// Number of completed tasks recorded against a specific agent. Derived
/// directly from the live pulse stream — no extra round-trip. Returns
/// 0 when the digest holds nothing for the agent (fresh hire) or when
/// the pulse provider is still loading.
///
/// Note: the tech-lead digest is bounded to the most recent ~50 entries
/// server-side, so this is a "recent completions" count, not lifetime.
/// That is the right signal for short-term growth feel; lifetime stats
/// can land later when the agent-signature endpoint is built.
final agentCompletionCountProvider =
    Provider.family<int, String>((ref, agentId) {
  final entries = ref.watch(techLeadPulseProvider);
  return entries.where((e) => e.agentId == agentId).length;
});
