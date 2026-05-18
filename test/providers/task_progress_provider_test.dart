/// Unit tests for TaskProgressNotifier — pins the C.2 reflector contract:
/// the provider observes server-pushed column changes and records per-agent
/// work-log entries, but never drives column moves itself. Previously this
/// provider was the client-side simulator; the simulator and its orphan
/// reset moved to the server in "Board transitions — server as single writer".
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/models/task_board.dart';
import 'package:pixelcode/providers/task_board_provider.dart';
import 'package:pixelcode/providers/task_progress_provider.dart';
import 'package:pixelcode/providers/ws_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

// ─── Fake WS service ─────────────────────────────────────────────────────────

class _FakeWsService extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();
  final _connCtrl = StreamController<bool>.broadcast();
  final List<Map<String, Object?>> calls = [];

  void inject(ServerMessage msg) => _msgCtrl.add(msg);

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<bool> get connectionStatus => _connCtrl.stream;

  @override
  bool get isConnected => true;

  @override
  void boardGetState({int? since}) {
    calls.add({'op': 'boardGetState', 'since': since});
  }

  @override
  void boardMoveTask({required String taskId, required String column}) {
    calls.add({'op': 'boardMoveTask', 'taskId': taskId, 'column': column});
  }

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    await _connCtrl.close();
    return super.dispose();
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

ProviderContainer _makeContainer(_FakeWsService fake) {
  final c = ProviderContainer(
    overrides: [wsServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(c.dispose);
  c.read(taskBoardProvider);    // build board (sets up WS listener)
  c.read(taskProgressProvider); // build progress (attaches ref.listen)
  return c;
}

final _t = DateTime(2026, 1, 1);

TaskCard _card(
  String id,
  TaskColumn column, {
  List<String> agents = const [],
  int difficulty = 2,
}) =>
    TaskCard(
      id: id,
      title: id,
      column: column,
      assignedAgents: agents,
      difficulty: difficulty,
      createdAt: _t,
      updatedAt: _t,
    );

Iterable<Map<String, Object?>> _moveCalls(_FakeWsService fake) =>
    fake.calls.where((e) => e['op'] == 'boardMoveTask');

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('TaskProgressNotifier — server as single writer (C.2)', () {
    test('orphan in_progress card is NOT reset by the client', () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('t1', TaskColumn.inProgress)]),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(_moveCalls(fake), isEmpty,
          reason: 'orphan reset now lives on the server (Q1 variant A)');
    });

    test('orphan testing card is NOT reset by the client', () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('t2', TaskColumn.testing)]),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(_moveCalls(fake), isEmpty);
    });

    test('active card with agent triggers NO moveTask either', () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(
          tasks: [_card('t3', TaskColumn.inProgress, agents: ['coder#1'])],
        ),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(_moveCalls(fake), isEmpty,
          reason: 'simulator no longer auto-advances columns');
    });

    test('testing card with agent finishing locally is NOT advanced', () async {
      // The old simulator would have rolled outcome and pushed a moveTask
      // when the testing timer expired. Reflector simply waits for the
      // server to push the new column.
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(
          tasks: [_card('t4', TaskColumn.testing, agents: ['coder#1'])],
        ),
        revision: 1,
      ));
      // Let several seconds pass; nothing should fire.
      await Future.delayed(const Duration(milliseconds: 50));

      expect(_moveCalls(fake), isEmpty);
    });

    test('mixed board with orphans + assigned cards produces zero moves',
        () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card('a', TaskColumn.inProgress),
          _card('b', TaskColumn.testing),
          _card('c', TaskColumn.inProgress, agents: ['coder#1']),
          _card('d', TaskColumn.backlog),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(_moveCalls(fake), isEmpty);
    });
  });

  group('TaskProgressNotifier — work-log capture', () {
    test('records duration when card leaves an active column', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      // First snapshot — card enters in_progress with two agents.
      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card('t1', TaskColumn.inProgress, agents: ['coder#1', 'coder#2']),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      // Let some wall-clock time elapse so durationSeconds > 0.
      await Future.delayed(const Duration(seconds: 1));

      // Server pushes the same card now in testing (transition out of
      // in_progress). Reflector should fire a log row per agent.
      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card('t1', TaskColumn.testing, agents: ['coder#1', 'coder#2']),
        ]),
        revision: 2,
      ));
      await Future.microtask(() {});

      final log = c.read(workLogProvider)['t1'] ?? const [];
      expect(log, hasLength(2));
      expect(log.map((e) => e.agentId).toSet(), {'coder#1', 'coder#2'});
      for (final entry in log) {
        expect(entry.durationSeconds, greaterThan(0));
      }
    });

    test('emits one row per active-column stay (in_progress AND testing)',
        () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card('t2', TaskColumn.inProgress, agents: ['coder#1']),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});
      await Future.delayed(const Duration(seconds: 1));

      // inProgress → testing — first row recorded.
      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card('t2', TaskColumn.testing, agents: ['coder#1']),
        ]),
        revision: 2,
      ));
      await Future.microtask(() {});
      await Future.delayed(const Duration(seconds: 1));

      // testing → done — second row recorded.
      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card('t2', TaskColumn.done, agents: ['coder#1']),
        ]),
        revision: 3,
      ));
      await Future.microtask(() {});

      final log = c.read(workLogProvider)['t2'] ?? const [];
      expect(log, hasLength(2));
      expect(log.every((e) => e.agentId == 'coder#1'), isTrue);
    });

    test('no work-log entry when card never leaves an active column',
        () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card('t3', TaskColumn.inProgress, agents: ['coder#1']),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      // Snapshot updates with the SAME column — should not flush.
      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card('t3', TaskColumn.inProgress, agents: ['coder#1']),
        ]),
        revision: 2,
      ));
      await Future.microtask(() {});

      expect(c.read(workLogProvider)['t3'] ?? const [], isEmpty);
    });
  });
}
