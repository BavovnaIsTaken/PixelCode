/// Unit tests for TaskProgressNotifier — focusing on the orphan-recovery
/// invariant: a task in inProgress or testing with no assigned agents must
/// be reset to backlog so it never gets permanently stuck.
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

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('TaskProgressNotifier — orphan recovery', () {
    test('inProgress task with no agents is moved to backlog', () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('t1', TaskColumn.inProgress)]),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(
        fake.calls,
        contains(allOf(
          containsPair('op', 'boardMoveTask'),
          containsPair('taskId', 't1'),
          containsPair('column', 'backlog'),
        )),
      );
    });

    test('testing task with no agents is moved to backlog', () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('t2', TaskColumn.testing)]),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(
        fake.calls,
        contains(allOf(
          containsPair('op', 'boardMoveTask'),
          containsPair('taskId', 't2'),
          containsPair('column', 'backlog'),
        )),
      );
    });

    test('inProgress task WITH assigned agent is NOT reset', () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(
          tasks: [_card('t3', TaskColumn.inProgress, agents: ['coder#1'])],
        ),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(
        fake.calls.where((e) =>
            e['op'] == 'boardMoveTask' && e['taskId'] == 't3'),
        isEmpty,
      );
    });

    test('backlog task with no agents stays in backlog — no move sent', () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('t4', TaskColumn.backlog)]),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(
        fake.calls.where((e) =>
            e['op'] == 'boardMoveTask' && e['taskId'] == 't4'),
        isEmpty,
      );
    });

    test('done task with no agents is NOT moved', () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('t5', TaskColumn.done)]),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(
        fake.calls.where((e) =>
            e['op'] == 'boardMoveTask' && e['taskId'] == 't5'),
        isEmpty,
      );
    });

    test('multiple orphaned tasks are all reset; assigned tasks untouched',
        () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card('a', TaskColumn.inProgress),               // orphan
          _card('b', TaskColumn.testing),                  // orphan
          _card('c', TaskColumn.inProgress, agents: ['coder#1']), // has agent
          _card('d', TaskColumn.backlog),                  // fine
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      final moveCalls = fake.calls
          .where((e) => e['op'] == 'boardMoveTask')
          .toList();

      // Only 'a' and 'b' should be reset.
      expect(
        moveCalls.map((e) => e['taskId']).toSet(),
        equals({'a', 'b'}),
      );
      for (final call in moveCalls) {
        expect(call['column'], 'backlog');
      }
    });
  });
}
