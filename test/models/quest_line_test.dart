import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/quest_line.dart';
import 'package:pixelcode/models/task_board.dart';

void main() {
  group('QuestTier.fromScore', () {
    test('0–4 → micro', () {
      expect(QuestTier.fromScore(0), QuestTier.micro);
      expect(QuestTier.fromScore(4), QuestTier.micro);
    });

    test('5–8 → small', () {
      expect(QuestTier.fromScore(5), QuestTier.small);
      expect(QuestTier.fromScore(8), QuestTier.small);
    });

    test('9–12 → medium', () {
      expect(QuestTier.fromScore(9), QuestTier.medium);
      expect(QuestTier.fromScore(12), QuestTier.medium);
    });

    test('13–18 → large', () {
      expect(QuestTier.fromScore(13), QuestTier.large);
      expect(QuestTier.fromScore(18), QuestTier.large);
    });

    test('quest count range matches tier', () {
      expect(QuestTier.micro.questCountRange, (min: 3, max: 4));
      expect(QuestTier.small.questCountRange, (min: 5, max: 7));
      expect(QuestTier.medium.questCountRange, (min: 8, max: 13));
      expect(QuestTier.large.questCountRange, (min: 14, max: 20));
    });
  });

  group('ScopeScore', () {
    test('total sums all dimensions', () {
      const s = ScopeScore(
        entityCount: 1,
        interactionSurface: 2,
        auth: 2,
        integrations: 1,
        realtime: 0,
      );
      expect(s.total, 6);
      expect(s.tier, QuestTier.small);
    });

    test('empty has total 0 → micro tier', () {
      const s = ScopeScore.empty();
      expect(s.total, 0);
      expect(s.tier, QuestTier.micro);
    });

    test('serde round-trip preserves all fields', () {
      const original = ScopeScore(
        entityCount: 3,
        interactionSurface: 3,
        auth: 2,
        integrations: 3,
        realtime: 0,
      );
      final restored = ScopeScore.fromJson(original.toJson());
      expect(restored.entityCount, 3);
      expect(restored.interactionSurface, 3);
      expect(restored.auth, 2);
      expect(restored.integrations, 3);
      expect(restored.realtime, 0);
      expect(restored.total, original.total);
    });
  });

  group('Quest enums fromKey', () {
    test('QuestStatus round-trip', () {
      for (final s in QuestStatus.values) {
        expect(QuestStatus.fromKey(s.key), s);
      }
    });

    test('QuestType round-trip', () {
      for (final t in QuestType.values) {
        expect(QuestType.fromKey(t.key), t);
      }
    });

    test('DevCategory round-trip', () {
      for (final c in DevCategory.values) {
        expect(DevCategory.fromKey(c.key), c);
      }
    });

    test('ActArchetype round-trip', () {
      for (final a in ActArchetype.values) {
        expect(ActArchetype.fromKey(a.key), a);
      }
    });

    test('ActArchetype interface uses "interface" key (not "interfaceAct")',
        () {
      // The enum is named `interfaceAct` to dodge Dart's keyword,
      // but external key must be the natural "interface".
      expect(ActArchetype.interfaceAct.key, 'interface');
      expect(ActArchetype.fromKey('interface'), ActArchetype.interfaceAct);
    });
  });

  group('QuestLine derived state', () {
    QuestLine buildLine({
      QuestStatus q1Status = QuestStatus.locked,
      QuestStatus q2Status = QuestStatus.locked,
      QuestStatus sideStatus = QuestStatus.locked,
    }) {
      final q1 = Quest(
        id: 'q1',
        actId: 'a1',
        title: 'Q1',
        subtitle: 's',
        description: 'd',
        devTask: const DevTask(category: DevCategory.dataModel, description: ''),
        status: q1Status,
        type: QuestType.main,
        unlocks: const ['q2'],
        xp: 100,
        estimatedMinutes: 25,
      );
      final q2 = Quest(
        id: 'q2',
        actId: 'a1',
        title: 'Q2',
        subtitle: 's',
        description: 'd',
        devTask: const DevTask(category: DevCategory.uiScreen, description: ''),
        status: q2Status,
        type: QuestType.main,
        dependsOn: const ['q1'],
        xp: 150,
        estimatedMinutes: 35,
      );
      final qSide = Quest(
        id: 'qSide',
        actId: 'a1',
        title: 'Side',
        subtitle: 's',
        description: 'd',
        devTask:
            const DevTask(category: DevCategory.uiComponent, description: ''),
        status: sideStatus,
        type: QuestType.side,
        dependsOn: const ['q1'],
        xp: 60,
        estimatedMinutes: 20,
      );
      return QuestLine(
        id: 'line-1',
        projectPath: '/tmp/app',
        appSummary: 'Todo app',
        tier: QuestTier.small,
        scoreBreakdown: const ScopeScore.empty(),
        acts: [
          Act(
            id: 'a1',
            name: 'Foundation',
            archetype: ActArchetype.foundation,
            quests: [q1, q2, qSide],
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );
    }

    test('totalXp counts every quest, earnedXp only completed', () {
      final line = buildLine(q1Status: QuestStatus.completed);
      expect(line.totalXp, 100 + 150 + 60);
      expect(line.earnedXp, 100);
    });

    test('progress uses main quests only (side quests excluded)', () {
      final line = buildLine(
        q1Status: QuestStatus.completed,
        sideStatus: QuestStatus.completed,
      );
      // 1 of 2 main quests done, side excluded.
      expect(line.progress, 0.5);
    });

    test('skipped main quest counts toward progress denominator-numerator',
        () {
      final line = buildLine(
        q1Status: QuestStatus.completed,
        q2Status: QuestStatus.skipped,
      );
      expect(line.progress, 1.0);
      expect(line.isCompleted, true);
    });

    test('isCompleted false until every main quest is done or skipped', () {
      final line = buildLine(q1Status: QuestStatus.completed);
      expect(line.isCompleted, false);
    });

    test('questById finds quest across acts', () {
      final line = buildLine();
      expect(line.questById('q1')?.title, 'Q1');
      expect(line.questById('missing'), isNull);
    });
  });

  group('QuestLine.recomputeAvailability', () {
    test('promotes locked → available when deps complete', () {
      final q1 = Quest(
        id: 'q1',
        actId: 'a1',
        title: 'Q1',
        subtitle: '',
        description: '',
        devTask: const DevTask(category: DevCategory.dataModel, description: ''),
        status: QuestStatus.completed,
        unlocks: const ['q2'],
        xp: 100,
        estimatedMinutes: 25,
      );
      final q2 = Quest(
        id: 'q2',
        actId: 'a1',
        title: 'Q2',
        subtitle: '',
        description: '',
        devTask: const DevTask(category: DevCategory.uiScreen, description: ''),
        status: QuestStatus.locked,
        dependsOn: const ['q1'],
        xp: 150,
        estimatedMinutes: 35,
      );
      final line = QuestLine(
        id: 'l1',
        projectPath: '/tmp/x',
        appSummary: '',
        tier: QuestTier.small,
        scoreBreakdown: const ScopeScore.empty(),
        acts: [
          Act(
              id: 'a1',
              name: 'F',
              archetype: ActArchetype.foundation,
              quests: [q1, q2]),
        ],
        createdAt: DateTime.now(),
      );

      final recomputed = line.recomputeAvailability();
      expect(recomputed.questById('q2')?.status, QuestStatus.available);
    });

    test('skipped dep also unlocks downstream', () {
      final q1 = Quest(
        id: 'q1',
        actId: 'a1',
        title: 'Q1',
        subtitle: '',
        description: '',
        devTask: const DevTask(category: DevCategory.dataModel, description: ''),
        status: QuestStatus.skipped,
        xp: 100,
        estimatedMinutes: 25,
      );
      final q2 = Quest(
        id: 'q2',
        actId: 'a1',
        title: 'Q2',
        subtitle: '',
        description: '',
        devTask: const DevTask(category: DevCategory.uiScreen, description: ''),
        status: QuestStatus.locked,
        dependsOn: const ['q1'],
        xp: 100,
        estimatedMinutes: 25,
      );
      final line = QuestLine(
        id: 'l1',
        projectPath: '/tmp/x',
        appSummary: '',
        tier: QuestTier.micro,
        scoreBreakdown: const ScopeScore.empty(),
        acts: [
          Act(
              id: 'a1',
              name: 'F',
              archetype: ActArchetype.foundation,
              quests: [q1, q2]),
        ],
        createdAt: DateTime.now(),
      );

      expect(line.recomputeAvailability().questById('q2')?.status,
          QuestStatus.available);
    });

    test('keeps quest locked when any dep unsatisfied', () {
      final q1 = Quest(
        id: 'q1',
        actId: 'a1',
        title: 'Q1',
        subtitle: '',
        description: '',
        devTask: const DevTask(category: DevCategory.dataModel, description: ''),
        status: QuestStatus.completed,
        xp: 100,
        estimatedMinutes: 25,
      );
      final q2 = Quest(
        id: 'q2',
        actId: 'a1',
        title: 'Q2',
        subtitle: '',
        description: '',
        devTask: const DevTask(category: DevCategory.uiScreen, description: ''),
        status: QuestStatus.active,
        xp: 150,
        estimatedMinutes: 35,
      );
      final q3 = Quest(
        id: 'q3',
        actId: 'a1',
        title: 'Q3',
        subtitle: '',
        description: '',
        devTask:
            const DevTask(category: DevCategory.uiComponent, description: ''),
        status: QuestStatus.locked,
        dependsOn: const ['q1', 'q2'],
        xp: 100,
        estimatedMinutes: 25,
      );
      final line = QuestLine(
        id: 'l1',
        projectPath: '/tmp/x',
        appSummary: '',
        tier: QuestTier.small,
        scoreBreakdown: const ScopeScore.empty(),
        acts: [
          Act(
              id: 'a1',
              name: 'F',
              archetype: ActArchetype.foundation,
              quests: [q1, q2, q3]),
        ],
        createdAt: DateTime.now(),
      );

      expect(line.recomputeAvailability().questById('q3')?.status,
          QuestStatus.locked);
    });
  });

  group('QuestLine serde', () {
    test('encode → decode round-trip preserves nested structure', () {
      final original = QuestLine(
        id: 'line-1',
        projectPath: '/Users/x/MyApp',
        appSummary: 'Todo app with reminders',
        tier: QuestTier.small,
        scoreBreakdown: const ScopeScore(
          entityCount: 1,
          interactionSurface: 2,
          auth: 0,
          integrations: 1,
          realtime: 0,
        ),
        acts: [
          Act(
            id: 'a1',
            name: 'Foundation',
            archetype: ActArchetype.foundation,
            quests: [
              Quest(
                id: 'q1',
                actId: 'a1',
                title: 'Forge the Task Vault',
                subtitle: 'Define Task data model',
                description: 'Lay the bedrock.',
                payoffLine: 'The vault stands firm.',
                devTask: const DevTask(
                  category: DevCategory.dataModel,
                  description: 'Define Task',
                  acceptanceCriteria: ['Task model exists'],
                  files: ['lib/models/task.dart'],
                ),
                status: QuestStatus.completed,
                type: QuestType.main,
                unlocks: const ['q2'],
                xp: 100,
                estimatedMinutes: 25,
                completedAt: DateTime.parse('2026-04-26T12:00:00Z'),
              ),
            ],
          ),
        ],
        transformativeChanges: 1,
        finalScreenshotPath: '/tmp/screenshot.png',
        createdAt: DateTime.parse('2026-04-26T10:00:00Z'),
      );

      final restored = QuestLine.decode(original.encode());

      expect(restored.id, original.id);
      expect(restored.projectPath, original.projectPath);
      expect(restored.tier, QuestTier.small);
      expect(restored.scoreBreakdown.total, 4);
      expect(restored.acts.length, 1);
      expect(restored.acts.first.archetype, ActArchetype.foundation);
      expect(restored.acts.first.quests.length, 1);

      final q = restored.acts.first.quests.first;
      expect(q.title, 'Forge the Task Vault');
      expect(q.payoffLine, 'The vault stands firm.');
      expect(q.devTask.category, DevCategory.dataModel);
      expect(q.devTask.acceptanceCriteria, ['Task model exists']);
      expect(q.status, QuestStatus.completed);
      expect(q.completedAt,
          DateTime.parse('2026-04-26T12:00:00Z'));

      expect(restored.transformativeChanges, 1);
      expect(restored.finalScreenshotPath, '/tmp/screenshot.png');
    });

    test('decode tolerates missing optional fields', () {
      final minimal = {
        'id': 'l',
        'projectPath': '/p',
        'appSummary': '',
        'tier': 'micro',
        'scoreBreakdown': const <String, dynamic>{},
        'acts': const <dynamic>[],
        'createdAt': '2026-04-26T00:00:00Z',
      };
      final line = QuestLine.fromJson(minimal);
      expect(line.transformativeChanges, 0);
      expect(line.finalScreenshotPath, isNull);
      expect(line.completedAt, isNull);
      expect(line.acts, isEmpty);
    });
  });

  group('QuestLine implements FacilitatorOutput', () {
    QuestLine buildLine({
      QuestStatus q1Status = QuestStatus.completed,
      QuestStatus q2Status = QuestStatus.active,
      QuestStatus q3Status = QuestStatus.locked,
    }) {
      final q1 = Quest(
        id: 'q1',
        actId: 'a1',
        title: 'Forge the Task Vault',
        subtitle: 'Define Task data model',
        description: 'Lay the bedrock.',
        devTask: const DevTask(
            category: DevCategory.dataModel, description: 'Define Task'),
        status: q1Status,
        type: QuestType.main,
        xp: 100,
        estimatedMinutes: 25,
      );
      final q2 = Quest(
        id: 'q2',
        actId: 'a2',
        title: 'Raise the Hall',
        subtitle: 'Build main screen',
        description: '',
        devTask:
            const DevTask(category: DevCategory.uiScreen, description: 'UI'),
        status: q2Status,
        type: QuestType.main,
        xp: 150,
        estimatedMinutes: 35,
      );
      final q3 = Quest(
        id: 'q3',
        actId: 'a3',
        title: 'Open the Gates',
        subtitle: 'Deploy',
        description: '',
        devTask: const DevTask(
            category: DevCategory.deploy, description: 'Final deploy'),
        status: q3Status,
        type: QuestType.main,
        xp: 200,
        estimatedMinutes: 45,
      );
      return QuestLine(
        id: 'l',
        projectPath: '/p',
        appSummary: '',
        tier: QuestTier.small,
        scoreBreakdown: const ScopeScore.empty(),
        acts: [
          Act(
              id: 'a1',
              name: 'Foundation',
              archetype: ActArchetype.foundation,
              quests: [q1]),
          Act(
              id: 'a2',
              name: 'Interface',
              archetype: ActArchetype.interfaceAct,
              quests: [q2]),
          Act(
              id: 'a3',
              name: 'Launch',
              archetype: ActArchetype.launch,
              quests: [q3]),
        ],
        createdAt: DateTime.parse('2026-04-26T10:00:00Z'),
      );
    }

    test('format discriminator is questLine', () {
      expect(buildLine().format, OutputFormat.questLine);
    });

    test('serialized JSON carries the format key for routing', () {
      final raw = buildLine().serialize();
      expect(raw, contains('"format":"quest_line"'));
    });

    test('toKanbanTasks emits one card per quest across acts', () {
      final cards = buildLine().toKanbanTasks();
      expect(cards.map((c) => c.id), ['q1', 'q2', 'q3']);
    });

    test('status maps to kanban column (locked/available → backlog, '
        'active → inProgress, completed/skipped → done)', () {
      final cards = buildLine(
        q1Status: QuestStatus.completed,
        q2Status: QuestStatus.active,
        q3Status: QuestStatus.locked,
      ).toKanbanTasks();

      expect(cards[0].column, TaskColumn.done);
      expect(cards[1].column, TaskColumn.inProgress);
      expect(cards[2].column, TaskColumn.backlog);

      final skipped = buildLine(q1Status: QuestStatus.skipped).toKanbanTasks();
      expect(skipped[0].column, TaskColumn.done,
          reason: 'skipped counts as done on the board');
    });

    test('act archetype drives sticky color', () {
      final cards = buildLine().toKanbanTasks();
      expect(cards[0].color, StickyColor.green); // foundation
      expect(cards[1].color, StickyColor.blue); // interface
      expect(cards[2].color, StickyColor.orange); // launch
    });

    test('estimatedMinutes bucket into 1–5 difficulty', () {
      final cards = buildLine().toKanbanTasks();
      expect(cards[0].difficulty, 2); // 25 min  → ≤30
      expect(cards[1].difficulty, 3); // 35 min  → ≤45
      expect(cards[2].difficulty, 3); // 45 min  → ≤45 boundary
    });

    test('DevCategory maps to taskType (testing/deploy explicit, rest coding)',
        () {
      final cards = buildLine().toKanbanTasks();
      expect(cards[0].taskType, 'coding'); // dataModel
      expect(cards[1].taskType, 'coding'); // uiScreen
      expect(cards[2].taskType, 'deploy'); // deploy
    });

    test('subtitle prefers over description for kanban description', () {
      final cards = buildLine().toKanbanTasks();
      expect(cards[0].description, 'Define Task data model');
    });

    test('toCanonicalProgress reflects mainQuests progress', () {
      final p = buildLine(
        q1Status: QuestStatus.completed,
        q2Status: QuestStatus.completed,
        q3Status: QuestStatus.locked,
      ).toCanonicalProgress();

      expect(p.fraction, closeTo(2 / 3, 1e-9));
      expect(p.earnedXp, 250);
      expect(p.totalXp, 450);
      expect(p.isComplete, false);
      expect(p.label, '2 of 3 quests forged');
    });

    test('toCanonicalProgress.isComplete true when every main is done/skipped',
        () {
      final p = buildLine(
        q1Status: QuestStatus.completed,
        q2Status: QuestStatus.completed,
        q3Status: QuestStatus.skipped,
      ).toCanonicalProgress();

      expect(p.fraction, 1.0);
      expect(p.isComplete, true);
    });

    test('serialize() round-trips through QuestLine.decode', () {
      final original = buildLine();
      final decoded = QuestLine.decode(original.serialize());
      expect(decoded.id, original.id);
      expect(decoded.allQuests.length, 3);
      expect(decoded.format, OutputFormat.questLine);
    });
  });

  group('OutputFormat', () {
    test('round-trip key/fromKey for every variant', () {
      for (final f in OutputFormat.values) {
        expect(OutputFormat.fromKey(f.key), f);
      }
    });

    test('unknown key falls back to questLine', () {
      expect(OutputFormat.fromKey('nonsense'), OutputFormat.questLine);
    });
  });
}
