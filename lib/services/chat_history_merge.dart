/// Pure merge logic for reconciling server-authoritative chat snapshots
/// with the local per-agent message map.
///
/// Lifted out of `ChatNotifier` so it can be unit-tested without spinning up
/// a `ProviderContainer` or mocking WebSocket plumbing — and so the platform
/// drift between macOS/iOS clients can be characterised in a focused test
/// suite (`test/services/chat_history_merge_test.dart`).
library;

import '../models/agent_message.dart';

/// Merges a `chat_history` snapshot from the server into the existing local
/// per-agent message map.
///
/// Contract (id-based reconciliation, snapshot is always full):
///  * Server is authoritative: the snapshot is the complete state, NOT an
///    additive feed. The server-side `ChatHistory.snapshot()` always returns
///    the entire log; there is no per-agent or partial snapshot mode.
///  * Messages present on the server (with an id) are the canonical versions.
///    Local messages with matching ids are dropped.
///  * Local-only streaming messages (still being streamed from assistant) are
///    preserved in a "tail" because the server hasn't persisted them yet.
///  * Local-only non-streaming messages with an id not in the server snapshot
///    are dropped — treated as orphaned optimistic writes pending server echo.
///  * Local messages without an id and not streaming are dropped — no identity
///    to match, and if they were server-canonical they'd have an id.
///
/// **Why no "agents-only-locally" fast path exists**: an earlier version
/// kept the local list untouched when the server snapshot had no entries
/// for an agent, on the assumption that the server might send per-agent
/// partial snapshots. That assumption is false — server.ts only sends full
/// snapshots — and the fast path caused a real iPhone↔Mac desync when the
/// chat was cleared on one device: the empty snapshot landed on the other
/// device but the stale local list survived. The fix is to apply the
/// per-message rules uniformly: streaming items are kept regardless of
/// snapshot coverage; everything else dies on an empty snapshot, which
/// matches the server's authoritative state.
Map<String, List<ChatMessage>> mergeChatHistory(
  Map<String, List<ChatMessage>> local,
  List<ChatMessage> serverMessages,
) {
  final serverGrouped = <String, List<ChatMessage>>{};
  for (final m in serverMessages) {
    (serverGrouped[m.agentId] ??= []).add(m);
  }
  final merged = <String, List<ChatMessage>>{};
  final agentIds = {...local.keys, ...serverGrouped.keys};
  for (final agentId in agentIds) {
    final serverList = serverGrouped[agentId] ?? const <ChatMessage>[];
    final localList = local[agentId] ?? const <ChatMessage>[];
    final serverIds = {
      for (final m in serverList)
        if (m.id != null) m.id!,
    };
    // Keep local messages only if:
    //   * still streaming (server hasn't persisted yet), OR
    //   * have an id not yet in the server (optimistic, pending echo)
    final tail = localList.where((m) =>
        m.isStreaming || (m.id != null && !serverIds.contains(m.id)));
    final entry = [...serverList, ...tail];
    if (entry.isNotEmpty) {
      merged[agentId] = entry;
    }
  }
  return merged;
}
