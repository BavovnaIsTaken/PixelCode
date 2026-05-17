/// Tracks the server's [AgentRun] history — per-run lifecycle snapshots.
///
/// On every (re)connect the provider asks the server for runs that landed
/// after the last one it has seen (`list_runs_since`). The server responds
/// with a [RunsSinceMessage] and we fold it into the in-memory store,
/// preserving the chronological order from the server (which is the
/// authoritative source — clients never invent run ordering).
///
/// Why this exists: when a server restart promotes any in-flight run to
/// `status=interrupted`, the UI needs to surface those rows so the user
/// can retry. Without this provider the client would silently lose
/// awareness of runs that finished while it was offline.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import 'ws_provider.dart';

class AgentRunsNotifier extends Notifier<List<AgentRunSnapshot>> {
  StreamSubscription<ServerMessage>? _msgSub;
  StreamSubscription<bool>? _connSub;

  /// Run IDs the user has explicitly acknowledged — typically by tapping
  /// the "retry / dismiss" affordance on an interrupted-run banner. Kept
  /// in-memory: re-running the app re-surfaces the same banners, which is
  /// the conservative default (better to re-show than to hide a run the
  /// user actually missed).
  final Set<String> _acknowledged = <String>{};

  /// Highest runId we have ingested. Sent back as the `sinceRunId` cursor
  /// on the next reconnect so we don't re-fetch state we already have.
  String? _lastSeenRunId;

  @override
  List<AgentRunSnapshot> build() {
    final ws = ref.watch(wsServiceProvider);
    _msgSub?.cancel();
    _connSub?.cancel();
    _msgSub = ws.messages.listen((msg) {
      if (msg is RunsSinceMessage) {
        _ingest(msg.runs);
      }
    });
    // Re-request on every connect transition (initial connect + reconnect).
    // `connectionStatus` yields the current value first, so the initial
    // fetch happens without a separate kick.
    _connSub = ws.connectionStatus.listen((connected) {
      if (connected) ws.listRunsSince(_lastSeenRunId);
    });
    ref.onDispose(() {
      _msgSub?.cancel();
      _connSub?.cancel();
    });
    return const [];
  }

  void _ingest(List<AgentRunSnapshot> incoming) {
    if (incoming.isEmpty) return;
    // Fold into a {runId → snapshot} map so re-pushing an updated row
    // overwrites the previous version (e.g. running → interrupted on a
    // mid-session refresh). Preserve server's chronological order via
    // insertion-ordered Map iteration.
    final byId = <String, AgentRunSnapshot>{};
    for (final r in state) {
      byId[r.runId] = r;
    }
    for (final r in incoming) {
      byId[r.runId] = r;
      _lastSeenRunId = r.runId;
    }
    state = List.unmodifiable(byId.values);
  }

  /// Runs that finished while the client wasn't watching and the user has
  /// not yet acknowledged. The Hub / banner UI watches this to know what
  /// to surface; `[ack]` clears the entry without dropping it from the
  /// underlying list (so debug views still see it).
  List<AgentRunSnapshot> get interruptedUnacknowledged => state
      .where((r) =>
          r.status == AgentRunStatus.interrupted &&
          !_acknowledged.contains(r.runId))
      .toList(growable: false);

  /// Mark an interrupted run as seen by the user. Idempotent.
  void ack(String runId) {
    if (_acknowledged.add(runId)) {
      // Notify listeners — state list itself is unchanged, but derived
      // `interruptedUnacknowledged` value flips. Re-emit the same list
      // to trigger the watch.
      state = List.unmodifiable(state);
    }
  }

  /// Acknowledge every currently-surfaced interrupted run in one shot —
  /// "got it, hide the banner" affordance.
  void ackAll() {
    final ids = interruptedUnacknowledged.map((r) => r.runId).toList();
    if (ids.isEmpty) return;
    _acknowledged.addAll(ids);
    state = List.unmodifiable(state);
  }

  /// Force-refresh the full history (drops in-memory cursor + ack set).
  /// Reserved for debug surfaces — normal reconnect uses the cursored fetch.
  void hardReload() {
    _lastSeenRunId = null;
    _acknowledged.clear();
    state = const [];
    ref.read(wsServiceProvider).listRunsSince(null);
  }

  // ─── Test hooks ─────────────────────────────────────────────────────────

  /// Exposed for tests: feed a server snapshot directly without ws plumbing.
  void debugIngest(List<AgentRunSnapshot> runs) => _ingest(runs);

  /// Exposed for tests: read the cursor without bouncing through `state`.
  String? get debugLastSeenRunId => _lastSeenRunId;
}

final agentRunsProvider =
    NotifierProvider<AgentRunsNotifier, List<AgentRunSnapshot>>(
  AgentRunsNotifier.new,
);
