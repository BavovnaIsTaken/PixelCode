import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/models/task_board.dart';
import 'package:pixelcode/providers/task_board_provider.dart';
import 'package:pixelcode/providers/ws_provider.dart';

import '../helpers/recording_ws_service.dart';

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

  // ─── TaskBoardNotifier — board sync flow ─────────────────────────────────

  group('TaskBoardNotifier', () {
    ProviderContainer makeContainer(RecordingWsService ws) {
      final c = ProviderContainer(
        overrides: [wsServiceProvider.overrideWithValue(ws)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('initial state is empty BoardState', () {
      final ws = RecordingWsService(connected: false);
      final c = makeContainer(ws);
      expect(c.read(taskBoardProvider).tasks, isEmpty);
    });

    test('requests board state immediately when already connected', () {
      final ws = RecordingWsService(connected: true);
      final c = makeContainer(ws);

      c.read(taskBoardProvider); // triggers build()

      expect(ws.countCalls('boardGetState'), 1);
    });

    test('defers boardGetState until connection becomes available', () async {
      final ws = RecordingWsService(connected: false);
      final c = makeContainer(ws);
      c.read(taskBoardProvider);

      expect(ws.countCalls('boardGetState'), 0);

      ws.setConnected(true);
      // allow stream subscription microtask to fire
      await Future<void>.delayed(Duration.zero);

      expect(ws.countCalls('boardGetState'), 1);
    });

    test('applies BoardStateMessage from server (multi-client sync)', () async {
      final ws = RecordingWsService(connected: true);
      final c = makeContainer(ws);
      c.read(taskBoardProvider);

      final now = DateTime(2026, 5, 1);
      ws.emit(BoardStateMessage(
        boardState: BoardState(tasks: [
          TaskCard(
            id: 't-1',
            title: 'Розбити фічу логіну',
            createdAt: now,
            updatedAt: now,
          ),
          TaskCard(
            id: 't-2',
            title: 'Підзадача — форма',
            column: TaskColumn.inProgress,
            createdAt: now,
            updatedAt: now,
          ),
        ]),
      ));

      await Future<void>.delayed(Duration.zero);

      final state = c.read(taskBoardProvider);
      expect(state.tasks, hasLength(2));
      expect(state.tasksInColumn(TaskColumn.backlog).single.id, 't-1');
      expect(state.tasksInColumn(TaskColumn.inProgress).single.id, 't-2');
    });

    test('overwrites local state when server pushes a fresh snapshot', () async {
      final ws = RecordingWsService(connected: true);
      final c = makeContainer(ws);
      c.read(taskBoardProvider);

      final now = DateTime(2026, 5, 1);
      ws.emit(BoardStateMessage(
        boardState: BoardState(tasks: [
          TaskCard(id: 'a', title: 'A', createdAt: now, updatedAt: now),
        ]),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(taskBoardProvider).tasks.single.id, 'a');

      // Second client deletes 'a' and adds 'b' — server broadcasts new snapshot.
      ws.emit(BoardStateMessage(
        boardState: BoardState(tasks: [
          TaskCard(id: 'b', title: 'B', createdAt: now, updatedAt: now),
        ]),
      ));
      await Future<void>.delayed(Duration.zero);

      final tasks = c.read(taskBoardProvider).tasks;
      expect(tasks, hasLength(1));
      expect(tasks.single.id, 'b');
    });

    test('ignores non-board ServerMessages', () async {
      final ws = RecordingWsService(connected: true);
      final c = makeContainer(ws);
      c.read(taskBoardProvider);

      ws.emit(ErrorMessage(message: 'unrelated'));
      await Future<void>.delayed(Duration.zero);

      expect(c.read(taskBoardProvider).tasks, isEmpty);
    });

    // ─── createTask: positive + negative ────────────────────────────────

    test('createTask returns true and forwards args when connected', () {
      final ws = RecordingWsService(connected: true);
      final c = makeContainer(ws);

      final ok = c.read(taskBoardProvider.notifier).createTask(
            title: 'Нова задача',
            description: 'опис',
            difficulty: 3,
            allowedRoles: ['coder', 'reviewer'],
            taskType: 'coding',
          );

      expect(ok, isTrue);
      final call = ws.lastCall('boardCreateTask')!;
      expect(call.args['title'], 'Нова задача');
      expect(call.args['difficulty'], 3);
      expect(call.args['allowedRoles'], ['coder', 'reviewer']);
      expect(call.args['taskType'], 'coding');
    });

    test('createTask returns false and drops message when disconnected', () {
      final ws = RecordingWsService(connected: false);
      final c = makeContainer(ws);

      final ok = c.read(taskBoardProvider.notifier).createTask(
            title: 'Не дійде',
          );

      expect(ok, isFalse);
      expect(ws.countCalls('boardCreateTask'), 0);
    });

    // ─── moveTask / updateTask / deleteTask delegation ──────────────────

    test('moveTask sends boardMoveTask with column key', () {
      final ws = RecordingWsService(connected: true);
      final c = makeContainer(ws);

      c
          .read(taskBoardProvider.notifier)
          .moveTask(taskId: 't-1', column: TaskColumn.testing);

      final call = ws.lastCall('boardMoveTask')!;
      expect(call.args['taskId'], 't-1');
      expect(call.args['column'], 'testing');
    });

    test('updateTask forwards updates map verbatim', () {
      final ws = RecordingWsService(connected: true);
      final c = makeContainer(ws);

      c.read(taskBoardProvider.notifier).updateTask(
        taskId: 't-1',
        updates: {'title': 'Renamed', 'priority': 'urgent'},
      );

      final call = ws.lastCall('boardUpdateTask')!;
      expect(call.args['taskId'], 't-1');
      expect(call.args['updates'], {'title': 'Renamed', 'priority': 'urgent'});
    });

    test('deleteTask sends boardDeleteTask with id', () {
      final ws = RecordingWsService(connected: true);
      final c = makeContainer(ws);

      c.read(taskBoardProvider.notifier).deleteTask(taskId: 't-9');

      expect(ws.lastCall('boardDeleteTask')!.args['taskId'], 't-9');
    });

    // ─── Delegation via assignAgent ─────────────────────────────────────

    test('assignAgent: assign=true forwards assign flag', () {
      final ws = RecordingWsService(connected: true);
      final c = makeContainer(ws);

      c.read(taskBoardProvider.notifier).assignAgent(
            taskId: 't-1',
            agentId: 'coder#1',
            assign: true,
          );

      final call = ws.lastCall('boardAssignAgent')!;
      expect(call.args['taskId'], 't-1');
      expect(call.args['agentId'], 'coder#1');
      expect(call.args['assign'], isTrue);
    });

    test('assignAgent: assign=false unassigns', () {
      final ws = RecordingWsService(connected: true);
      final c = makeContainer(ws);

      c.read(taskBoardProvider.notifier).assignAgent(
            taskId: 't-1',
            agentId: 'coder#1',
            assign: false,
          );

      expect(ws.lastCall('boardAssignAgent')!.args['assign'], isFalse);
    });

    test('attachment add/remove forwards size and ids', () {
      final ws = RecordingWsService(connected: true);
      final c = makeContainer(ws);

      c.read(taskBoardProvider.notifier).addAttachment(
            taskId: 't-1',
            name: 'spec.md',
            mimeType: 'text/markdown',
            sizeBytes: 1024,
            dataBase64: 'YWJj',
          );
      c.read(taskBoardProvider.notifier).removeAttachment(
            taskId: 't-1',
            attachmentId: 'att-9',
          );

      expect(ws.lastCall('boardAddAttachment')!.args['sizeBytes'], 1024);
      expect(
        ws.lastCall('boardRemoveAttachment')!.args['attachmentId'],
        'att-9',
      );
    });
  });
}
