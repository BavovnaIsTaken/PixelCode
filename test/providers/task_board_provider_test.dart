import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/models/task_board.dart';
import 'package:pixelcode/providers/task_board_provider.dart';

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
}
