import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/models/task_board.dart';
import 'package:pixelcode/providers/task_board_provider.dart';

TaskCard _task({
  int difficulty = 2,
  List<String> allowedRoles = const ['coder'],
  String taskType = 'coding',
}) {
  final now = DateTime.now();
  return TaskCard(
    id: 't',
    title: 't',
    createdAt: now,
    updatedAt: now,
    difficulty: difficulty,
    allowedRoles: allowedRoles,
    taskType: taskType,
  );
}

AgentGameData _agent({required String roleType, required int level}) =>
    AgentGameData(
      instanceId: '$roleType#1',
      roleType: roleType,
      nickname: 'T',
      skills: initialSkillsForRole(roleType),
      level: level,
    );

void main() {
  test('accepts matching role and level', () {
    final t = _task(difficulty: 3, allowedRoles: ['coder']);
    final a = _agent(roleType: 'coder', level: 5);
    expect(assignmentRejectionReason(t, a), isNull);
  });

  test('rejects when role is not allowed', () {
    final t = _task(difficulty: 2, allowedRoles: ['tester']);
    final a = _agent(roleType: 'coder', level: 5);
    final r = assignmentRejectionReason(t, a);
    expect(r, isNotNull);
    expect(r, contains('роль'));
  });

  test('rejects when level below requiredLevel', () {
    final t = _task(difficulty: 4, allowedRoles: ['coder']);
    final a = _agent(roleType: 'coder', level: 3);
    final r = assignmentRejectionReason(t, a);
    expect(r, isNotNull);
    expect(r, contains('Lv 7'));
  });

  test('requiredLevel derives from difficulty', () {
    expect(_task(difficulty: 1).requiredLevel, 1);
    expect(_task(difficulty: 5).requiredLevel, 11);
  });
}
