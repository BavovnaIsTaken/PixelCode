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
/// Contract (id-based reconciliation):
///  * Server is authoritative: messages present on the server (with an id) are
///    the canonical versions. Local messages with matching ids are dropped.
///  * Local-only streaming messages (still being streamed from assistant) are
///    preserved in a "tail" because the server hasn't yet persisted them.
///  * Local-only non-streaming messages with an id not in server snapshot are
///    dropped — treated as orphaned optimistic writes pending server echo.
///  * Local messages without an id and not streaming are dropped — no identity
///    to match, and if they were server-canonical they'd have an id.
///  * Agents present only locally (server returned nothing for them) are kept
///    untouched — supports per-agent snapshots that cover a subset of agents.
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
    if (serverList.isEmpty) {
      merged[agentId] = List.of(localList);
      continue;
    }
    // Build set of ids present on the server
    final serverIds = {
      for (final m in serverList)
        if (m.id != null) m.id!,
    };
    // Keep local messages only if:
    //   * still streaming (server hasn't persisted yet), OR
    //   * have an id not yet in the server (optimistic, pending echo)
    final tail = localList.where((m) =>
        m.isStreaming || (m.id != null && !serverIds.contains(m.id)));
    merged[agentId] = [...serverList, ...tail];
  }
  return merged;
}
