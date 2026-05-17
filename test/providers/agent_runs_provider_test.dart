/// Tests for [agentRunsProvider] — ingests `runs_since` snapshots and
/// surfaces interrupted runs to the UI banner layer.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/agent_runs_provider.dart';
import 'package:pixelcode/providers/ws_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

class _FakeWs extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();
  final _connCtrl = StreamController<bool>.broadcast();
  final List<Map<String, Object?>> sent = [];

  void inject(ServerMessage msg) => _msgCtrl.add(msg);
  void emitConn(bool up) => _connCtrl.add(up);

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<bool> get connectionStatus => _connCtrl.stream;

  @override
  void listRunsSince(String? sinceRunId) =>
      sent.add({'op': 'listRunsSince', 'since': sinceRunId});

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    await _connCtrl.close();
    return super.dispose();
  }
}

ProviderContainer _makeContainer(_FakeWs ws) {
  final c = ProviderContainer(overrides: [
    wsServiceProvider.overrideWithValue(ws),
  ]);
  addTearDown(c.dispose);
  return c;
}

AgentRunSnapshot _run(
  String id, {
  AgentRunStatus status = AgentRunStatus.completed,
  AgentRunTaskType taskType = AgentRunTaskType.chat,
  String agentId = 'manager#1',
  String? snippet,
}) =>
    AgentRunSnapshot(
      runId: id,
      agentId: agentId,
      taskType: taskType,
      status: status,
      userMessageSnippet: snippet,
      toolCalls: const [],
      startedAt: '2026-05-17T10:00:00Z',
    );

void main() {
  group('agentRunsProvider — build + connect handshake', () {
    test('does NOT fire list_runs_since while connection is still down',
        () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      c.read(agentRunsProvider);
      ws.emitConn(false);
      await Future<void>.delayed(Duration.zero);
      expect(
        ws.sent.where((m) => m['op'] == 'listRunsSince'),
        isEmpty,
        reason: 'no point asking for runs while we know we are offline',
      );
    });

    test('first true connection emit triggers list_runs_since(null)',
        () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      c.read(agentRunsProvider);
      ws.emitConn(true);
      await Future<void>.delayed(Duration.zero);
      final calls = ws.sent.where((m) => m['op'] == 'listRunsSince').toList();
      expect(calls, hasLength(1));
      expect(calls.single['since'], isNull,
          reason: 'first fetch has no cursor — pull everything');
    });

    test('reconnect after ingest sends the highest seen runId as cursor',
        () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      c.read(agentRunsProvider);
      ws.emitConn(true);
      await pumpEventQueue();

      ws.inject(RunsSinceMessage(runs: [
        _run('a'),
        _run('b'),
      ]));
      await pumpEventQueue();

      // Disconnect → reconnect: cursor must be the last seen.
      ws.emitConn(false);
      await pumpEventQueue();
      ws.emitConn(true);
      await pumpEventQueue();
      final calls = ws.sent.where((m) => m['op'] == 'listRunsSince').toList();
      expect(calls, hasLength(2));
      expect(calls.last['since'], 'b');
    });
  });

  group('agentRunsProvider — ingest', () {
    test('first snapshot populates state in server order', () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      c.read(agentRunsProvider);
      ws.emitConn(true);
      await Future<void>.delayed(Duration.zero);

      ws.inject(RunsSinceMessage(runs: [
        _run('a', status: AgentRunStatus.completed),
        _run('b', status: AgentRunStatus.interrupted),
      ]));
      await Future<void>.delayed(Duration.zero);

      final st = c.read(agentRunsProvider);
      expect(st.map((r) => r.runId).toList(), ['a', 'b']);
    });

    test('re-pushed run with updated status replaces the older snapshot',
        () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      c.read(agentRunsProvider);
      ws.emitConn(true);
      await Future<void>.delayed(Duration.zero);

      ws.inject(RunsSinceMessage(runs: [_run('a', status: AgentRunStatus.running)]));
      await Future<void>.delayed(Duration.zero);
      expect(
        c.read(agentRunsProvider).single.status,
        AgentRunStatus.running,
      );

      // Server pushes an updated row for the same runId.
      ws.inject(RunsSinceMessage(runs: [_run('a', status: AgentRunStatus.interrupted)]));
      await Future<void>.delayed(Duration.zero);
      final st = c.read(agentRunsProvider);
      expect(st, hasLength(1), reason: 'no duplicate row');
      expect(st.single.status, AgentRunStatus.interrupted);
    });

    test('empty RunsSinceMessage does not clear existing state', () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      c.read(agentRunsProvider);
      ws.emitConn(true);
      await Future<void>.delayed(Duration.zero);

      ws.inject(RunsSinceMessage(runs: [_run('a')]));
      ws.inject(const RunsSinceMessage(runs: []));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(agentRunsProvider), hasLength(1));
    });
  });

  group('agentRunsProvider — interrupted banner surface', () {
    test('interruptedUnacknowledged filters to status=interrupted only',
        () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      final notifier = c.read(agentRunsProvider.notifier);
      notifier.debugIngest([
        _run('a', status: AgentRunStatus.completed),
        _run('b', status: AgentRunStatus.interrupted),
        _run('c', status: AgentRunStatus.failed),
        _run('d', status: AgentRunStatus.interrupted),
      ]);
      final got = notifier.interruptedUnacknowledged.map((r) => r.runId).toList();
      expect(got, ['b', 'd']);
    });

    test('ack(id) hides one interrupted run, others remain', () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      final notifier = c.read(agentRunsProvider.notifier);
      notifier.debugIngest([
        _run('b', status: AgentRunStatus.interrupted),
        _run('d', status: AgentRunStatus.interrupted),
      ]);
      notifier.ack('b');
      expect(
        notifier.interruptedUnacknowledged.map((r) => r.runId),
        ['d'],
      );
    });

    test('ack is idempotent — second call does not flip state again',
        () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      final notifier = c.read(agentRunsProvider.notifier);
      notifier.debugIngest([_run('b', status: AgentRunStatus.interrupted)]);

      // Capture the list reference each call. State should reference-change
      // exactly once (first ack); the second ack must be a no-op.
      final before = c.read(agentRunsProvider);
      notifier.ack('b');
      final after = c.read(agentRunsProvider);
      expect(identical(before, after), isFalse, reason: 'first ack must re-emit');

      final afterAgain = c.read(agentRunsProvider);
      notifier.ack('b');
      final stable = c.read(agentRunsProvider);
      expect(identical(afterAgain, stable), isTrue,
          reason: 'second ack on same id should be a no-op');
    });

    test('ackAll clears every currently surfaced interrupted run', () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      final notifier = c.read(agentRunsProvider.notifier);
      notifier.debugIngest([
        _run('b', status: AgentRunStatus.interrupted),
        _run('d', status: AgentRunStatus.interrupted),
      ]);
      notifier.ackAll();
      expect(notifier.interruptedUnacknowledged, isEmpty);

      // A new interrupted run after ackAll is still surfaced — the ack set
      // is per-runId, not a global mute.
      notifier.debugIngest([_run('e', status: AgentRunStatus.interrupted)]);
      expect(
        notifier.interruptedUnacknowledged.map((r) => r.runId),
        ['e'],
      );
    });
  });

  group('agentRunsProvider — cursor mechanics', () {
    test('debugLastSeenRunId advances with each ingest in server order',
        () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      final notifier = c.read(agentRunsProvider.notifier);
      notifier.debugIngest([_run('a'), _run('b')]);
      expect(notifier.debugLastSeenRunId, 'b');
      notifier.debugIngest([_run('c')]);
      expect(notifier.debugLastSeenRunId, 'c');
    });

    test('hardReload drops cursor and clears state', () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      final notifier = c.read(agentRunsProvider.notifier);
      notifier.debugIngest([_run('a'), _run('b', status: AgentRunStatus.interrupted)]);
      notifier.ack('b');

      notifier.hardReload();
      expect(notifier.debugLastSeenRunId, isNull);
      expect(c.read(agentRunsProvider), isEmpty);
      // Acked set is also reset — a previously acked run, if re-ingested,
      // surfaces again. Defensive default for debug surface use.
      notifier.debugIngest([_run('b', status: AgentRunStatus.interrupted)]);
      expect(notifier.interruptedUnacknowledged, hasLength(1));
    });
  });
}
