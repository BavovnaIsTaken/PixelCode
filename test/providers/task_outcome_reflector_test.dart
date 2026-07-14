/// Tests for TaskOutcomeReflectorNotifier — pins the C.2 contract:
/// when the server pushes a TaskCard with `outcome` set, the reflector
/// folds the derived XP / specialization counter / crit gold into the
/// local economy exactly once per taskId, and never mutates the board.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/models/task_board.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/task_board_provider.dart';
import 'package:pixelcode/providers/task_outcome_reflector.dart';
import 'package:pixelcode/providers/ws_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';
import 'package:pixelcode/services/task_outcome.dart';

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
  void setGameState({
    required Map<String, Map<String, dynamic>> instances,
    String? fullState,
    int? stateUpdatedAt,
    String? deepseekApiKey,
    String? kimiApiKey,
    String? accountId,
  }) {
    calls.add({'op': 'setGameState'});
  }

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    await _connCtrl.close();
    return super.dispose();
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

ProviderContainer _makeContainer(_FakeWsService fake, {GameState? seed}) {
  final c = ProviderContainer(
    overrides: [wsServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(c.dispose);
  c.read(taskBoardProvider);
  // Seed economy state if provided — used to inject a starter agent so the
  // reflector has someone to credit.
  if (seed != null) {
    c.read(gameEconomyProvider.notifier).state = seed;
  }
  c.read(taskOutcomeReflectorProvider);
  return c;
}

final _t = DateTime(2026, 1, 1);

TaskCard _card({
  required String id,
  required TaskColumn column,
  required TaskOutcome? outcome,
  List<String> agents = const ['coder#1'],
  int difficulty = 3,
  String taskType = 'coding',
}) =>
    TaskCard(
      id: id,
      title: id,
      column: column,
      assignedAgents: agents,
      difficulty: difficulty,
      taskType: taskType,
      createdAt: _t,
      updatedAt: _t,
      outcome: outcome,
    );

GameState _seedWithCoder({int xp = 0, int level = 1, int grymni = 0}) =>
    GameState(
      grymni: grymni,
      agents: {
        'coder#1': AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Майстер',
          level: level,
          xp: xp,
        ),
      },
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('TaskOutcomeReflectorNotifier — XP award', () {
    test('clean outcome awards XP', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake, seed: _seedWithCoder());

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card(id: 't1', column: TaskColumn.done, outcome: TaskOutcome.clean),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      final agent = c.read(gameEconomyProvider).agents['coder#1']!;
      expect(agent.xp, greaterThan(0));
    });

    test('incomplete outcome still awards (lower) XP', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake, seed: _seedWithCoder());

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card(
            id: 't1',
            column: TaskColumn.backlog,
            outcome: TaskOutcome.incomplete,
          ),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      final agent = c.read(gameEconomyProvider).agents['coder#1']!;
      // quality 0.5 vs 1.5 → roughly 1/3 the XP of a clean, but > 0.
      expect(agent.xp, greaterThan(0));
    });
  });

  group('TaskOutcomeReflectorNotifier — crit gold', () {
    test('crit outcome awards +150 grymni', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake, seed: _seedWithCoder(grymni: 100));

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card(id: 't1', column: TaskColumn.done, outcome: TaskOutcome.crit),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(c.read(gameEconomyProvider).grymni, 250);
      expect(c.read(gameEconomyProvider).totalEarned, 150);
    });

    test('non-crit outcomes do NOT award gold', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake, seed: _seedWithCoder(grymni: 100));

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card(id: 't1', column: TaskColumn.done, outcome: TaskOutcome.clean),
          _card(
              id: 't2',
              column: TaskColumn.inProgress,
              outcome: TaskOutcome.bug),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(c.read(gameEconomyProvider).grymni, 100);
    });
  });

  group('TaskOutcomeReflectorNotifier — specialization counter', () {
    test('clean increments taskCompletionsByType', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake, seed: _seedWithCoder());

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card(id: 't1', column: TaskColumn.done, outcome: TaskOutcome.clean),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      final counters =
          c.read(gameEconomyProvider).agents['coder#1']!.taskCompletionsByType;
      expect(counters['coding'], 1);
    });

    test('bug / incomplete do NOT increment the counter', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake, seed: _seedWithCoder());

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card(
              id: 't1',
              column: TaskColumn.inProgress,
              outcome: TaskOutcome.bug),
          _card(
              id: 't2',
              column: TaskColumn.backlog,
              outcome: TaskOutcome.incomplete),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      final counters =
          c.read(gameEconomyProvider).agents['coder#1']!.taskCompletionsByType;
      expect(counters, isEmpty);
    });
  });

  group('TaskOutcomeReflectorNotifier — idempotency', () {
    test('replaying the same board_state does not double-award', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake, seed: _seedWithCoder(grymni: 0));

      final card =
          _card(id: 't1', column: TaskColumn.done, outcome: TaskOutcome.crit);
      // Snapshot 1
      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [card]),
        revision: 1,
      ));
      await Future.microtask(() {});
      final xpAfterFirst =
          c.read(gameEconomyProvider).agents['coder#1']!.xp;
      final grymniAfterFirst = c.read(gameEconomyProvider).grymni;

      // Snapshot 2 — same payload, possibly from a reconnect.
      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [card]),
        revision: 2,
      ));
      await Future.microtask(() {});

      expect(c.read(gameEconomyProvider).agents['coder#1']!.xp, xpAfterFirst);
      expect(c.read(gameEconomyProvider).grymni, grymniAfterFirst);
      expect(c.read(gameEconomyProvider).rewardedTaskIds, {'t1'});
    });

    test('reward set persists across copyWith chains', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake, seed: _seedWithCoder());

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card(id: 't1', column: TaskColumn.done, outcome: TaskOutcome.clean),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(c.read(gameEconomyProvider).rewardedTaskIds, contains('t1'));
    });
  });

  group('TaskOutcomeReflectorNotifier — strict reflector', () {
    test('never sends boardMoveTask', () async {
      final fake = _FakeWsService();
      _makeContainer(fake, seed: _seedWithCoder());

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card(id: 't1', column: TaskColumn.done, outcome: TaskOutcome.clean),
          _card(
              id: 't2',
              column: TaskColumn.inProgress,
              outcome: TaskOutcome.bug),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      expect(
        fake.calls.where((e) => e['op'] == 'boardMoveTask'),
        isEmpty,
      );
    });

    test('cards without outcome are ignored entirely', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake, seed: _seedWithCoder(grymni: 0));

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [
          _card(id: 't1', column: TaskColumn.done, outcome: null),
          _card(id: 't2', column: TaskColumn.testing, outcome: null),
        ]),
        revision: 1,
      ));
      await Future.microtask(() {});

      final agent = c.read(gameEconomyProvider).agents['coder#1']!;
      expect(agent.xp, 0);
      expect(c.read(gameEconomyProvider).grymni, 0);
      expect(c.read(gameEconomyProvider).rewardedTaskIds, isEmpty);
    });
  });
}
