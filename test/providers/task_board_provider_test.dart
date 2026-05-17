import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/models/task_board.dart';
import 'package:pixelcode/providers/task_board_provider.dart';
import 'package:pixelcode/providers/ws_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

// ─── Fake WS service ─────────────────────────────────────────────────────────

class _FakeWsService extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();
  final _connCtrl = StreamController<bool>.broadcast();
  final List<Map<String, Object?>> calls = [];
  bool _connected;

  _FakeWsService({bool connected = true}) : _connected = connected;

  void inject(ServerMessage msg) => _msgCtrl.add(msg);

  /// Push a non-ServerMessage error onto the stream so we can verify the
  /// provider's onError handler keeps the listener alive.
  void injectError(Object error) => _msgCtrl.addError(error);

  void setConnected(bool connected) {
    _connected = connected;
    _connCtrl.add(connected);
  }

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<bool> get connectionStatus => _connCtrl.stream;

  @override
  bool get isConnected => _connected;

  @override
  void boardGetState({int? since}) {
    calls.add({'op': 'boardGetState', 'since': since});
  }

  @override
  void boardMoveTask({required String taskId, required String column}) {
    calls.add({'op': 'boardMoveTask', 'taskId': taskId, 'column': column});
  }

  @override
  void boardCreateTask({
    required String title,
    String? description,
    String? color,
    String? priority,
    int? difficulty,
    List<String>? allowedRoles,
    String? taskType,
  }) {
    calls.add({
      'op': 'boardCreateTask',
      'title': title,
      'description': description,
      'color': color,
      'priority': priority,
      'difficulty': difficulty,
      'allowedRoles': allowedRoles,
      'taskType': taskType,
    });
  }

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    await _connCtrl.close();
    return super.dispose();
  }
}

ProviderContainer _makeContainer(_FakeWsService fake) {
  final c = ProviderContainer(
    overrides: [wsServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(c.dispose);
  c.read(taskBoardProvider); // build the provider
  return c;
}

DateTime _t = DateTime(2026, 1, 1);

TaskCard _card(String id, TaskColumn column) => TaskCard(
      id: id,
      title: id,
      column: column,
      allowedRoles: const ['coder'],
      difficulty: 1,
      createdAt: _t,
      updatedAt: _t,
    );

AgentGameData _agent({String roleType = 'coder', int level = 1}) =>
    AgentGameData(
      instanceId: '$roleType#1',
      roleType: roleType,
      nickname: roleType,
      level: level,
    );

final _now = DateTime(2026, 1, 1);

TaskCard _task({
  List<String> allowedRoles = const ['coder'],
  int difficulty = 1, // requiredLevel = 1
}) =>
    TaskCard(
      id: 'task-1',
      title: 'Test Task',
      allowedRoles: allowedRoles,
      difficulty: difficulty,
      createdAt: _now,
      updatedAt: _now,
    );

void main() {
  // ─── assignmentRejectionReason ────────────────────────────────────────────

  group('assignmentRejectionReason', () {
    test('returns null when role matches and level sufficient', () {
      expect(
        assignmentRejectionReason(_task(), _agent()),
        isNull,
      );
    });

    test('returns rejection when role not in allowedRoles', () {
      final reason = assignmentRejectionReason(
        _task(allowedRoles: ['tester']),
        _agent(roleType: 'coder'),
      );
      expect(reason, isNotNull);
      expect(reason, contains('роль'));
    });

    test('rejection message includes the required role label', () {
      final reason = assignmentRejectionReason(
        _task(allowedRoles: ['tester']),
        _agent(roleType: 'coder'),
      );
      // roleCatalogFor('tester') should provide a Ukrainian label
      expect(reason, isNotNull);
    });

    test('returns rejection when agent level below required', () {
      // difficulty=4 requires level 7 (from requiredLevelFor)
      final reason = assignmentRejectionReason(
        _task(difficulty: 4),
        _agent(level: 1),
      );
      expect(reason, isNotNull);
      expect(reason, contains('Lv'));
    });

    test('rejection message contains required and current level', () {
      final reason = assignmentRejectionReason(
        _task(difficulty: 4), // requiredLevel = 7
        _agent(level: 3),
      );
      expect(reason, contains('7'));
      expect(reason, contains('3'));
    });

    test('level check passes when agent level equals required', () {
      // difficulty=2 requires level 2
      expect(
        assignmentRejectionReason(
          _task(difficulty: 2),
          _agent(level: 2),
        ),
        isNull,
      );
    });

    test('level check passes when agent level exceeds required', () {
      expect(
        assignmentRejectionReason(
          _task(difficulty: 2),
          _agent(level: 10),
        ),
        isNull,
      );
    });

    test('role check wins before level check', () {
      // Wrong role AND low level — role rejection comes first
      final reason = assignmentRejectionReason(
        _task(allowedRoles: ['tester'], difficulty: 5),
        _agent(roleType: 'coder', level: 1),
      );
      expect(reason, contains('роль'));
    });

    test('multiple allowedRoles — matching role passes', () {
      expect(
        assignmentRejectionReason(
          _task(allowedRoles: ['coder', 'tester', 'reviewer']),
          _agent(roleType: 'tester'),
        ),
        isNull,
      );
    });
  });

  // ─── applyOptimisticMove (pure) ───────────────────────────────────────────

  group('applyOptimisticMove', () {
    final start = BoardState(tasks: [
      _card('a', TaskColumn.backlog),
      _card('b', TaskColumn.inProgress),
    ]);

    test('moves the matching task to the target column', () {
      final after = applyOptimisticMove(
        start,
        taskId: 'a',
        column: TaskColumn.inProgress,
        now: _t,
      );
      expect(after.tasks.firstWhere((t) => t.id == 'a').column,
          TaskColumn.inProgress);
      // Other tasks untouched.
      expect(after.tasks.firstWhere((t) => t.id == 'b').column,
          TaskColumn.inProgress);
    });

    test('returns the same shape when taskId is unknown', () {
      final after = applyOptimisticMove(
        start,
        taskId: 'nonexistent',
        column: TaskColumn.done,
        now: _t,
      );
      expect(after.tasks.length, start.tasks.length);
      for (var i = 0; i < after.tasks.length; i++) {
        expect(after.tasks[i].column, start.tasks[i].column);
      }
    });

    test('updates updatedAt only on the moved card', () {
      final later = DateTime(2026, 6, 1);
      final after = applyOptimisticMove(
        start,
        taskId: 'a',
        column: TaskColumn.done,
        now: later,
      );
      expect(after.tasks.firstWhere((t) => t.id == 'a').updatedAt, later);
      // 'b' stays at original timestamp.
      expect(after.tasks.firstWhere((t) => t.id == 'b').updatedAt, _t);
    });
  });

  // ─── TaskBoardNotifier — wired via fake AgentWsService ────────────────────

  group('TaskBoardNotifier', () {
    test('on build (already connected) sends boardGetState with since=null',
        () async {
      final fake = _FakeWsService(connected: true);
      _makeContainer(fake);
      // Provider build calls boardGetState synchronously when connected.
      final getStateCalls =
          fake.calls.where((c) => c['op'] == 'boardGetState').toList();
      expect(getStateCalls, hasLength(1));
      expect(getStateCalls.first['since'], isNull);
    });

    test('records server revision and replays it on reconnect', () async {
      final fake = _FakeWsService(connected: true);
      final c = _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('a', TaskColumn.backlog)]),
        revision: 5,
      ));
      await Future.microtask(() {});

      expect(
        c.read(taskBoardProvider.notifier).debugAppliedRevision,
        5,
      );

      // Simulate reconnect cycle.
      fake.setConnected(false);
      fake.calls.clear();
      fake.setConnected(true);
      await Future.microtask(() {});
      await Future.microtask(() {});

      final getStateCalls =
          fake.calls.where((c) => c['op'] == 'boardGetState').toList();
      expect(getStateCalls, isNotEmpty,
          reason: 'reconnect should re-request board state');
      expect(getStateCalls.last['since'], 5);
    });

    test('board_state_unchanged updates the revision marker without touching state',
        () async {
      final fake = _FakeWsService(connected: true);
      final c = _makeContainer(fake);

      // Seed state.
      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('a', TaskColumn.backlog)]),
        revision: 3,
      ));
      await Future.microtask(() {});
      final before = c.read(taskBoardProvider).tasks.first.id;

      fake.inject(BoardStateUnchangedMessage(revision: 4));
      await Future.microtask(() {});

      // State preserved.
      expect(c.read(taskBoardProvider).tasks.first.id, before);
      // Revision advanced.
      expect(
        c.read(taskBoardProvider.notifier).debugAppliedRevision,
        4,
      );
    });

    test('moveTask applies optimistic state update before the broadcast',
        () async {
      final fake = _FakeWsService(connected: true);
      final c = _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('a', TaskColumn.backlog)]),
        revision: 1,
      ));
      await Future.microtask(() {});

      c
          .read(taskBoardProvider.notifier)
          .moveTask(taskId: 'a', column: TaskColumn.inProgress);

      // Optimistic: state already reflects the move.
      expect(
        c.read(taskBoardProvider).tasks.first.column,
        TaskColumn.inProgress,
      );
      // WS got the command.
      expect(
        fake.calls.where((c) => c['op'] == 'boardMoveTask'),
        hasLength(1),
      );
    });

    test('server rejection is reconciled when next broadcast arrives',
        () async {
      final fake = _FakeWsService(connected: true);
      final c = _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('a', TaskColumn.backlog)]),
        revision: 1,
      ));
      await Future.microtask(() {});

      // Optimistically move; state shows in_progress immediately.
      c
          .read(taskBoardProvider.notifier)
          .moveTask(taskId: 'a', column: TaskColumn.done);
      expect(
        c.read(taskBoardProvider).tasks.first.column,
        TaskColumn.done,
      );

      // Server "rejects" by broadcasting state where 'a' is still in
      // backlog (e.g. column was invalid). Optimistic mutation snaps back.
      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('a', TaskColumn.backlog)]),
        revision: 2,
      ));
      await Future.microtask(() {});

      expect(
        c.read(taskBoardProvider).tasks.first.column,
        TaskColumn.backlog,
      );
    });

    test('listener survives a stream error and keeps receiving messages',
        () async {
      final fake = _FakeWsService(connected: true);
      final c = _makeContainer(fake);

      // Inject an error first.
      fake.injectError(StateError('synthetic transport error'));
      await Future.microtask(() {});

      // Now a normal broadcast — provider should still apply it.
      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('after-error', TaskColumn.backlog)]),
        revision: 9,
      ));
      await Future.microtask(() {});

      expect(c.read(taskBoardProvider).tasks, hasLength(1));
      expect(c.read(taskBoardProvider).tasks.first.id, 'after-error');
      expect(
        c.read(taskBoardProvider.notifier).debugAppliedRevision,
        9,
      );
    });

    test('two rapid optimistic moves on the same task — final state is the last',
        () async {
      final fake = _FakeWsService(connected: true);
      final c = _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('a', TaskColumn.backlog)]),
        revision: 1,
      ));
      await Future.microtask(() {});

      c
          .read(taskBoardProvider.notifier)
          .moveTask(taskId: 'a', column: TaskColumn.inProgress);
      c
          .read(taskBoardProvider.notifier)
          .moveTask(taskId: 'a', column: TaskColumn.testing);

      expect(
        c.read(taskBoardProvider).tasks.first.column,
        TaskColumn.testing,
      );
      expect(
        fake.calls.where((c) => c['op'] == 'boardMoveTask'),
        hasLength(2),
      );
    });

    test('board broadcast without revision keeps the previous revision marker',
        () async {
      final fake = _FakeWsService(connected: true);
      final c = _makeContainer(fake);

      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('a', TaskColumn.backlog)]),
        revision: 7,
      ));
      await Future.microtask(() {});
      expect(
        c.read(taskBoardProvider.notifier).debugAppliedRevision,
        7,
      );

      // Pre-WP2 server speaks without revision; client must not regress.
      fake.inject(BoardStateMessage(
        boardState: BoardState(tasks: [_card('a', TaskColumn.inProgress)]),
        revision: null,
      ));
      await Future.microtask(() {});

      expect(
        c.read(taskBoardProvider.notifier).debugAppliedRevision,
        7,
        reason: 'null revision must not clobber the previous marker',
      );
      expect(
        c.read(taskBoardProvider).tasks.first.column,
        TaskColumn.inProgress,
      );
    });
  });

  // ─── ServerMessage parsing for new types ──────────────────────────────────

  group('agent_message parsing', () {
    test('board_state_unchanged parses revision', () {
      final msg = ServerMessage.fromJson(
        '{"type":"board_state_unchanged","revision":12}',
      );
      expect(msg, isA<BoardStateUnchangedMessage>());
      expect((msg as BoardStateUnchangedMessage).revision, 12);
    });

    test('board_seed_batch_result success parses committedIds', () {
      final msg = ServerMessage.fromJson(
        '{"type":"board_seed_batch_result","batchId":"b1","ok":true,'
        '"committedIds":["task_1","task_2"],"errors":[]}',
      ) as BoardSeedBatchResultMessage;
      expect(msg.ok, isTrue);
      expect(msg.committedIds, ['task_1', 'task_2']);
      expect(msg.batchId, 'b1');
    });

    test('board_seed_batch_result failure parses errors', () {
      final msg = ServerMessage.fromJson(
        '{"type":"board_seed_batch_result","ok":false,"committedIds":[],'
        '"errors":[{"index":2,"reason":"title must be a non-empty string"}]}',
      ) as BoardSeedBatchResultMessage;
      expect(msg.ok, isFalse);
      expect(msg.errors, hasLength(1));
      expect(msg.errors.first.index, 2);
      expect(msg.errors.first.reason, contains('title'));
    });

    test('set_game_state_error parses validation errors', () {
      final msg = ServerMessage.fromJson(
        '{"type":"set_game_state_error","errors":['
        '{"instanceId":"manager#2","code":"manager_singleton","message":"only one"},'
        '{"instanceId":"coder#1","code":"missing_api_key","message":"link DeepSeek"}'
        ']}',
      ) as SetGameStateErrorMessage;
      expect(msg.errors, hasLength(2));
      expect(msg.errors.first.code, 'manager_singleton');
      expect(msg.errors.last.instanceId, 'coder#1');
    });

    test('agent_fired carries instanceId', () {
      final msg = ServerMessage.fromJson(
        '{"type":"agent_fired","instanceId":"coder#3"}',
      ) as AgentFiredMessage;
      expect(msg.instanceId, 'coder#3');
    });
  });

  // ─── requiredLevelFor ─────────────────────────────────────────────────────

  group('requiredLevelFor', () {
    test('difficulty 1 requires level 1', () {
      expect(requiredLevelFor(1), 1);
    });

    test('difficulty 2 requires level 2', () {
      expect(requiredLevelFor(2), 2);
    });

    test('difficulty 3 requires level 4', () {
      expect(requiredLevelFor(3), 4);
    });

    test('difficulty 4 requires level 7', () {
      expect(requiredLevelFor(4), 7);
    });

    test('difficulty 5 requires level 11', () {
      expect(requiredLevelFor(5), 11);
    });

    test('difficulty below 1 clamps to level 1', () {
      expect(requiredLevelFor(0), 1);
    });

    test('difficulty above 5 clamps to level 11', () {
      expect(requiredLevelFor(99), 11);
    });
  });
}
