import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/milestone_tree.dart';
import 'package:pixelcode/models/quest_line.dart' show DevCategory, ScopeScore;
import 'package:pixelcode/models/task_board.dart';

void main() {
  MilestoneTree build({
    MilestoneStatus m1Status = MilestoneStatus.notStarted,
    MilestoneStatus m2Status = MilestoneStatus.notStarted,
    MilestoneTaskStatus t1Status = MilestoneTaskStatus.pending,
    MilestoneTaskStatus t2Status = MilestoneTaskStatus.pending,
    MilestoneTaskStatus t3Status = MilestoneTaskStatus.pending,
  }) {
    return MilestoneTree(
      id: 'tree-1',
      projectPath: '/tmp/p',
      objective: 'Q3 launch',
      milestones: [
        Milestone(
          id: 'M1',
          name: 'Foundation',
          dueDate: '2026-05-15',
          status: m1Status,
          tasks: [
            MilestoneTask(
              id: 't1',
              milestoneId: 'M1',
              title: 'Define data models',
              description: 'Schema design',
              category: DevCategory.dataModel,
              status: t1Status,
              xp: 100,
              estimatedMinutes: 25,
            ),
          ],
        ),
        Milestone(
          id: 'M2',
          name: 'API + UI',
          dependsOn: const ['M1'],
          status: m2Status,
          tasks: [
            MilestoneTask(
              id: 't2',
              milestoneId: 'M2',
              title: 'Build endpoints',
              category: DevCategory.apiRoute,
              status: t2Status,
              xp: 150,
              estimatedMinutes: 50,
            ),
            MilestoneTask(
              id: 't3',
              milestoneId: 'M2',
              title: 'Wire UI',
              category: DevCategory.uiScreen,
              status: t3Status,
              xp: 100,
              estimatedMinutes: 35,
            ),
          ],
        ),
      ],
      scoreBreakdown: const ScopeScore.empty(),
      createdAt: DateTime.parse('2026-04-26T10:00:00Z'),
    );
  }

  group('MilestoneStatus / MilestoneTaskStatus', () {
    test('round-trip key/fromKey for every status', () {
      for (final s in MilestoneStatus.values) {
        expect(MilestoneStatus.fromKey(s.key), s);
      }
      for (final s in MilestoneTaskStatus.values) {
        expect(MilestoneTaskStatus.fromKey(s.key), s);
      }
    });

    test('snake_case keys for multi-word states', () {
      expect(MilestoneStatus.notStarted.key, 'not_started');
      expect(MilestoneStatus.inFlight.key, 'in_flight');
      expect(MilestoneTaskStatus.inFlight.key, 'in_flight');
    });
  });

  group('MilestoneTask serde', () {
    test('round-trips full state including completedAt', () {
      final original = MilestoneTask(
        id: 't',
        milestoneId: 'M',
        title: 'do thing',
        description: 'context',
        category: DevCategory.testing,
        status: MilestoneTaskStatus.delivered,
        xp: 50,
        estimatedMinutes: 20,
        completedAt: DateTime.parse('2026-04-26T11:00:00Z'),
      );
      final restored = MilestoneTask.fromJson(original.toJson());
      expect(restored.id, 't');
      expect(restored.milestoneId, 'M');
      expect(restored.category, DevCategory.testing);
      expect(restored.status, MilestoneTaskStatus.delivered);
      expect(restored.completedAt,
          DateTime.parse('2026-04-26T11:00:00Z'));
    });

    test('empty description omitted from JSON', () {
      final t = MilestoneTask(
        id: 't',
        milestoneId: 'M',
        title: 'x',
        category: DevCategory.deploy,
        xp: 0,
        estimatedMinutes: 0,
      );
      expect(t.toJson().containsKey('description'), false);
    });
  });

  group('Milestone derived state', () {
    test('isComplete true when every task delivered or cancelled', () {
      final tree = build(
        t1Status: MilestoneTaskStatus.delivered,
        t2Status: MilestoneTaskStatus.cancelled,
        t3Status: MilestoneTaskStatus.delivered,
      );
      expect(tree.milestones[0].isComplete, true);
      expect(tree.milestones[1].isComplete, true);
    });

    test('isComplete false when any task is still pending/inFlight', () {
      final tree = build(
        t2Status: MilestoneTaskStatus.delivered,
        // t3 still pending
      );
      expect(tree.milestones[1].isComplete, false);
    });

    test('Milestone serde preserves dependsOn + dueDate', () {
      final original = Milestone(
        id: 'm',
        name: 'Phase 2',
        dueDate: '2026-06-30',
        dependsOn: const ['m1', 'm0'],
        status: MilestoneStatus.inFlight,
        tasks: const [],
      );
      final restored = Milestone.fromJson(original.toJson());
      expect(restored.dueDate, '2026-06-30');
      expect(restored.dependsOn, ['m1', 'm0']);
      expect(restored.status, MilestoneStatus.inFlight);
    });

    test('empty dependsOn omitted from JSON', () {
      final m = Milestone(id: 'm', name: 'n', tasks: const []);
      expect(m.toJson().containsKey('dependsOn'), false);
    });
  });

  group('MilestoneTree derived state', () {
    test('totalXp / earnedXp track delivered tasks only', () {
      final tree = build(
        t1Status: MilestoneTaskStatus.delivered,
        t2Status: MilestoneTaskStatus.inFlight,
      );
      expect(tree.totalXp, 350);
      expect(tree.earnedXp, 100);
    });

    test('progress counts milestones (not tasks)', () {
      // M1 delivered, M2 not started → 1/2 = 0.5
      final tree = build(m1Status: MilestoneStatus.delivered);
      expect(tree.progress, 0.5);
      expect(tree.isComplete, false);
    });

    test('cancelled milestone counts toward progress', () {
      final tree = build(
        m1Status: MilestoneStatus.delivered,
        m2Status: MilestoneStatus.cancelled,
      );
      expect(tree.progress, 1.0);
      expect(tree.isComplete, true);
    });

    test('milestoneById and taskById lookup', () {
      final tree = build();
      expect(tree.milestoneById('M2')?.name, 'API + UI');
      expect(tree.taskById('t3')?.title, 'Wire UI');
      expect(tree.milestoneById('missing'), isNull);
      expect(tree.taskById('missing'), isNull);
    });

    test('allTasks flattens milestones', () {
      final tree = build();
      expect(tree.allTasks.map((t) => t.id).toList(), ['t1', 't2', 't3']);
    });
  });

  group('MilestoneTree implements FacilitatorOutput', () {
    test('format is milestoneTree', () {
      expect(build().format, OutputFormat.milestoneTree);
    });

    test('serialized JSON carries the format key', () {
      expect(build().serialize(), contains('"format":"milestone_tree"'));
    });

    test('toKanbanTasks emits one card per LEAF task only '
        '(milestones are not cards)', () {
      final cards = build().toKanbanTasks();
      expect(cards.map((c) => c.id), ['t1', 't2', 't3']);
    });

    test('all cards wear blue (Marina is corporate-neutral)', () {
      final cards = build().toKanbanTasks();
      expect(cards.every((c) => c.color == StickyColor.blue), true);
    });

    test('task description falls back to "Milestone: <name>" '
        'when task has no description', () {
      final cards = build().toKanbanTasks();
      // t1 has its own description; t2 has none → falls back
      expect(cards[0].description, 'Schema design');
      expect(cards[1].description, 'Milestone: API + UI');
    });

    test('task status maps to kanban column', () {
      final cards = build(
        t1Status: MilestoneTaskStatus.delivered,
        t2Status: MilestoneTaskStatus.inFlight,
        t3Status: MilestoneTaskStatus.cancelled,
      ).toKanbanTasks();
      expect(cards[0].column, TaskColumn.done); // delivered
      expect(cards[1].column, TaskColumn.inProgress); // inFlight
      expect(cards[2].column, TaskColumn.done); // cancelled = done
    });

    test('toCanonicalProgress label uses "milestones delivered" wording', () {
      final p = build(m1Status: MilestoneStatus.delivered)
          .toCanonicalProgress();
      expect(p.fraction, 0.5);
      expect(p.label, '1 of 2 milestones delivered');
    });

    test('toCanonicalProgress label when no milestones planned', () {
      final empty = MilestoneTree(
        id: 't',
        projectPath: '/p',
        objective: '',
        milestones: const [],
        scoreBreakdown: const ScopeScore.empty(),
        createdAt: DateTime.now(),
      );
      expect(empty.toCanonicalProgress().label, 'No milestones planned');
    });
  });

  group('MilestoneTree serde', () {
    test('encode → decode round-trips full nested state', () {
      final original = build(
        m1Status: MilestoneStatus.delivered,
        m2Status: MilestoneStatus.inFlight,
        t1Status: MilestoneTaskStatus.delivered,
        t2Status: MilestoneTaskStatus.inFlight,
      );
      final restored = MilestoneTree.decode(original.serialize());

      expect(restored.id, 'tree-1');
      expect(restored.milestones.length, 2);
      expect(restored.milestones[0].status, MilestoneStatus.delivered);
      expect(restored.milestones[1].dependsOn, ['M1']);
      expect(restored.allTasks.length, 3);
      expect(restored.format, OutputFormat.milestoneTree);
    });

    test('decode tolerates missing optional collections', () {
      final minimal = MilestoneTree.fromJson({
        'id': 't',
        'projectPath': '/p',
        'objective': '',
        'createdAt': '2026-04-26T00:00:00Z',
      });
      expect(minimal.milestones, isEmpty);
      expect(minimal.completedAt, isNull);
    });
  });
}
