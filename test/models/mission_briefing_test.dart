import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/mission_briefing.dart';
import 'package:pixelcode/models/quest_line.dart' show DevCategory, ScopeScore;
import 'package:pixelcode/models/task_board.dart';

void main() {
  MissionBriefing build({
    MissionStatus s1 = MissionStatus.standby,
    MissionStatus s2 = MissionStatus.standby,
    MissionStatus s3 = MissionStatus.standby,
  }) {
    final missions = [
      Mission(
        id: 'm1',
        briefing: 'Ship the auth flow.',
        target: 'Users can log in with email + password.',
        category: DevCategory.auth,
        status: s1,
        xp: 100,
        estimatedMinutes: 25,
      ),
      Mission(
        id: 'm2',
        briefing: 'Wire the API.',
        category: DevCategory.apiRoute,
        status: s2,
        xp: 150,
        estimatedMinutes: 50,
      ),
      Mission(
        id: 'm3',
        briefing: 'Deploy. Now.',
        category: DevCategory.deploy,
        status: s3,
        xp: 200,
        estimatedMinutes: 15,
      ),
    ];
    return MissionBriefing(
      id: 'b1',
      projectPath: '/tmp/op',
      objective: 'Ship MVP by EOD.',
      missions: missions,
      scoreBreakdown: const ScopeScore.empty(),
      createdAt: DateTime.parse('2026-04-26T10:00:00Z'),
    );
  }

  group('MissionStatus', () {
    test('round-trip key/fromKey for every variant', () {
      for (final s in MissionStatus.values) {
        expect(MissionStatus.fromKey(s.key), s);
      }
    });

    test('unknown key falls back to standby', () {
      expect(MissionStatus.fromKey('nope'), MissionStatus.standby);
    });
  });

  group('Mission serde', () {
    test('round-trips all fields', () {
      final original = Mission(
        id: 'm',
        briefing: 'Do the thing',
        target: 'thing done',
        category: DevCategory.uiScreen,
        status: MissionStatus.active,
        xp: 100,
        estimatedMinutes: 30,
        completedAt: DateTime.parse('2026-04-26T11:00:00Z'),
      );
      final restored = Mission.fromJson(original.toJson());
      expect(restored.id, 'm');
      expect(restored.briefing, 'Do the thing');
      expect(restored.target, 'thing done');
      expect(restored.category, DevCategory.uiScreen);
      expect(restored.status, MissionStatus.active);
      expect(restored.completedAt,
          DateTime.parse('2026-04-26T11:00:00Z'));
    });

    test('empty target is omitted from JSON', () {
      final m = Mission(
        id: 'm',
        briefing: 'b',
        category: DevCategory.deploy,
        xp: 0,
        estimatedMinutes: 0,
      );
      expect(m.toJson().containsKey('target'), false);
    });

    test('copyWith preserves status when not provided', () {
      final m = Mission(
        id: 'm',
        briefing: 'b',
        category: DevCategory.deploy,
        status: MissionStatus.active,
        xp: 0,
        estimatedMinutes: 0,
      );
      expect(m.copyWith().status, MissionStatus.active);
    });

    test('copyWith preserves completedAt when not provided', () {
      final ts = DateTime.parse('2026-04-26T12:00:00Z');
      final m = Mission(
        id: 'm',
        briefing: 'b',
        category: DevCategory.deploy,
        xp: 0,
        estimatedMinutes: 0,
        completedAt: ts,
      );
      expect(m.copyWith().completedAt, ts);
    });
  });

  group('MissionBriefing derived state', () {
    test('totalXp / earnedXp / progress / isComplete', () {
      final b = build(
        s1: MissionStatus.complete,
        s2: MissionStatus.active,
        s3: MissionStatus.standby,
      );
      expect(b.totalXp, 450);
      expect(b.earnedXp, 100);
      expect(b.progress, closeTo(1 / 3, 1e-9));
      expect(b.isComplete, false);
    });

    test('scrubbed counts as done for progress', () {
      final b = build(
        s1: MissionStatus.complete,
        s2: MissionStatus.scrubbed,
        s3: MissionStatus.complete,
      );
      expect(b.progress, 1.0);
      expect(b.isComplete, true);
    });

    test('missionById finds mission by id', () {
      final b = build();
      expect(b.missionById('m2')?.briefing, 'Wire the API.');
      expect(b.missionById('missing'), isNull);
    });

    test('withMissionUpdated replaces target mission', () {
      final b = build();
      final updated = b.missions[0].copyWith(
        status: MissionStatus.complete,
        completedAt: DateTime.parse('2026-04-26T12:00:00Z'),
      );
      final newB = b.withMissionUpdated(updated);
      expect(newB.missions[0].status, MissionStatus.complete);
      expect(newB.missions[1].status, MissionStatus.standby);
    });
  });

  group('MissionBriefing implements FacilitatorOutput', () {
    test('format is missionBriefing', () {
      expect(build().format, OutputFormat.missionBriefing);
    });

    test('serialized JSON carries the format key', () {
      expect(build().serialize(), contains('"format":"mission_briefing"'));
    });

    test('toKanbanTasks emits one card per mission', () {
      final cards = build().toKanbanTasks();
      expect(cards.map((c) => c.id), ['m1', 'm2', 'm3']);
    });

    test('all cards wear orange (drill is uniform)', () {
      final cards = build().toKanbanTasks();
      expect(cards.every((c) => c.color == StickyColor.orange), true);
    });

    test('status maps to kanban column', () {
      final cards = build(
        s1: MissionStatus.complete,
        s2: MissionStatus.active,
        s3: MissionStatus.standby,
      ).toKanbanTasks();
      expect(cards[0].column, TaskColumn.done);
      expect(cards[1].column, TaskColumn.inProgress);
      expect(cards[2].column, TaskColumn.backlog);

      final scrubbed = build(s1: MissionStatus.scrubbed).toKanbanTasks();
      expect(scrubbed[0].column, TaskColumn.done,
          reason: 'scrubbed counts as done on the board');
    });

    test('estimatedMinutes bucket into 1–5 difficulty', () {
      final cards = build().toKanbanTasks();
      expect(cards[0].difficulty, 2); // 25 min
      expect(cards[1].difficulty, 4); // 50 min
      expect(cards[2].difficulty, 1); // 15 min
    });

    test('DevCategory drives taskType', () {
      final cards = build().toKanbanTasks();
      expect(cards[0].taskType, 'coding'); // auth
      expect(cards[1].taskType, 'coding'); // apiRoute
      expect(cards[2].taskType, 'deploy'); // deploy
    });

    test('briefing → title, target → description', () {
      final cards = build().toKanbanTasks();
      expect(cards[0].title, 'Ship the auth flow.');
      expect(cards[0].description,
          'Users can log in with email + password.');
    });

    test('toCanonicalProgress', () {
      final p = build(
        s1: MissionStatus.complete,
        s2: MissionStatus.active,
      ).toCanonicalProgress();
      expect(p.fraction, closeTo(1 / 3, 1e-9));
      expect(p.earnedXp, 100);
      expect(p.totalXp, 450);
      expect(p.isComplete, false);
      expect(p.label, '1 of 3 missions complete');
    });

    test('toCanonicalProgress label when no missions assigned', () {
      final empty = MissionBriefing(
        id: 'b',
        projectPath: '/p',
        objective: '',
        missions: const [],
        scoreBreakdown: const ScopeScore.empty(),
        createdAt: DateTime.now(),
      );
      expect(empty.toCanonicalProgress().label, 'No missions assigned');
    });
  });

  group('MissionBriefing serde', () {
    test('encode → decode round-trips full state', () {
      final original = build(
        s1: MissionStatus.complete,
        s2: MissionStatus.active,
        s3: MissionStatus.standby,
      ).copyWith();
      final restored = MissionBriefing.decode(original.serialize());

      expect(restored.id, 'b1');
      expect(restored.projectPath, '/tmp/op');
      expect(restored.objective, 'Ship MVP by EOD.');
      expect(restored.missions.length, 3);
      expect(restored.missions[0].status, MissionStatus.complete);
      expect(restored.missions[1].status, MissionStatus.active);
      expect(restored.format, OutputFormat.missionBriefing);
    });

    test('decode tolerates missing optional fields', () {
      final minimal = MissionBriefing.fromJson({
        'id': 'b',
        'projectPath': '/p',
        'objective': '',
        'createdAt': '2026-04-26T00:00:00Z',
      });
      expect(minimal.missions, isEmpty);
      expect(minimal.completedAt, isNull);
    });

    test('fromJson with completedAt parses the timestamp', () {
      final b = MissionBriefing.fromJson({
        'id': 'b1',
        'projectPath': '/proj',
        'objective': 'Ship it',
        'missions': <dynamic>[],
        'scoreBreakdown': <String, dynamic>{},
        'createdAt': '2026-04-26T00:00:00Z',
        'completedAt': '2026-04-27T10:00:00Z',
      });
      expect(b.completedAt, DateTime.parse('2026-04-27T10:00:00Z'));
    });
  });
}
