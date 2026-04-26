import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/milestone_tree.dart';
import 'package:pixelcode/models/mission_briefing.dart';
import 'package:pixelcode/models/quest_line.dart';
import 'package:pixelcode/services/facilitator_output_persistence_service.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String supportDir;
  _FakePathProvider(this.supportDir);

  @override
  Future<String?> getApplicationSupportPath() async => supportDir;
}

QuestLine _sampleLine(String projectPath) => QuestLine(
      id: 'line-1',
      projectPath: projectPath,
      appSummary: 'Todo with reminders',
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
              subtitle: 'Define Task model',
              description: 'Lay the bedrock of the app.',
              devTask: const DevTask(
                category: DevCategory.dataModel,
                description: 'Define Task',
                acceptanceCriteria: ['model exists'],
                files: ['lib/models/task.dart'],
              ),
              status: QuestStatus.available,
              type: QuestType.main,
              xp: 100,
              estimatedMinutes: 25,
            ),
          ],
        ),
      ],
      createdAt: DateTime.parse('2026-04-26T10:00:00Z'),
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('facilitator_persist_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('load returns null when no output exists for project', () async {
    final loaded =
        await FacilitatorOutputPersistenceService.load('/Users/x/MyApp');
    expect(loaded, isNull);
  });

  test('save then load round-trips full QuestLine state and routes via '
      'format discriminator', () async {
    final original = _sampleLine('/Users/x/MyApp');
    await FacilitatorOutputPersistenceService.save('/Users/x/MyApp', original);

    final loaded =
        await FacilitatorOutputPersistenceService.load('/Users/x/MyApp');
    expect(loaded, isNotNull);
    expect(loaded!.format, OutputFormat.questLine);

    final restored = loaded as QuestLine;
    expect(restored.id, 'line-1');
    expect(restored.tier, QuestTier.small);
    expect(restored.scoreBreakdown.total, 4);
    expect(restored.acts.first.quests.first.title, 'Forge the Task Vault');
    expect(restored.acts.first.quests.first.devTask.acceptanceCriteria,
        ['model exists']);
  });

  test('save overwrites existing output for same project', () async {
    await FacilitatorOutputPersistenceService.save(
        '/Users/x/App', _sampleLine('/Users/x/App'));

    final updated = _sampleLine('/Users/x/App').copyWith(
      acts: [
        Act(
          id: 'a1',
          name: 'Foundation',
          archetype: ActArchetype.foundation,
          quests: const [],
        ),
        Act(
          id: 'a2',
          name: 'Interface',
          archetype: ActArchetype.interfaceAct,
          quests: const [],
        ),
      ],
    );
    await FacilitatorOutputPersistenceService.save('/Users/x/App', updated);

    final loaded =
        await FacilitatorOutputPersistenceService.load('/Users/x/App');
    final restored = loaded! as QuestLine;
    expect(restored.acts.length, 2);
    expect(restored.acts[1].archetype, ActArchetype.interfaceAct);
  });

  test('different projects keep isolated output files', () async {
    final lineA = _sampleLine('/Users/x/AppA');
    final lineB = _sampleLine('/Users/x/AppB').copyWith(acts: const []);
    await FacilitatorOutputPersistenceService.save('/Users/x/AppA', lineA);
    await FacilitatorOutputPersistenceService.save('/Users/x/AppB', lineB);

    final loadedA =
        await FacilitatorOutputPersistenceService.load('/Users/x/AppA')
            as QuestLine?;
    final loadedB =
        await FacilitatorOutputPersistenceService.load('/Users/x/AppB')
            as QuestLine?;

    expect(loadedA!.acts, hasLength(1));
    expect(loadedB!.acts, isEmpty);
  });

  test('delete removes the output file', () async {
    final line = _sampleLine('/Users/x/Z');
    await FacilitatorOutputPersistenceService.save('/Users/x/Z', line);

    expect(await FacilitatorOutputPersistenceService.load('/Users/x/Z'),
        isNotNull);

    await FacilitatorOutputPersistenceService.delete('/Users/x/Z');
    expect(await FacilitatorOutputPersistenceService.load('/Users/x/Z'),
        isNull);
  });

  test('delete on missing file does not throw', () async {
    await FacilitatorOutputPersistenceService.delete('/Users/never/existed');
  });

  test('resolvePath returns deterministic path under app support', () async {
    final path =
        await FacilitatorOutputPersistenceService.resolvePath('/Users/x/MyApp');
    expect(path, startsWith(tempDir.path));
    expect(path, endsWith('facilitator_output.json'));
    expect(path, contains('Users-x-MyApp'));
  });

  test('save+load round-trips a MissionBriefing (Drill Sergeant output)',
      () async {
    final original = MissionBriefing(
      id: 'mb-1',
      projectPath: '/Users/x/Op',
      objective: 'Ship MVP by EOD',
      missions: [
        Mission(
          id: 'm1',
          briefing: 'Wire auth.',
          category: DevCategory.auth,
          status: MissionStatus.active,
          xp: 100,
          estimatedMinutes: 30,
        ),
      ],
      scoreBreakdown: const ScopeScore.empty(),
      createdAt: DateTime.parse('2026-04-26T10:00:00Z'),
    );
    await FacilitatorOutputPersistenceService.save('/Users/x/Op', original);

    final loaded =
        await FacilitatorOutputPersistenceService.load('/Users/x/Op');
    expect(loaded, isNotNull);
    expect(loaded!.format, OutputFormat.missionBriefing,
        reason: 'discriminator routes to MissionBriefing decoder');
    final restored = loaded as MissionBriefing;
    expect(restored.id, 'mb-1');
    expect(restored.missions.first.briefing, 'Wire auth.');
    expect(restored.missions.first.status, MissionStatus.active);
  });

  test('save+load round-trips a MilestoneTree (Marina output)', () async {
    final original = MilestoneTree(
      id: 'mt-1',
      projectPath: '/Users/x/Plan',
      objective: 'Q3 launch',
      milestones: [
        Milestone(
          id: 'M1',
          name: 'Foundation',
          dueDate: '2026-05-15',
          tasks: [
            MilestoneTask(
              id: 't1',
              milestoneId: 'M1',
              title: 'Schema',
              category: DevCategory.dataModel,
              xp: 100,
              estimatedMinutes: 25,
            ),
          ],
        ),
      ],
      scoreBreakdown: const ScopeScore.empty(),
      createdAt: DateTime.parse('2026-04-26T10:00:00Z'),
    );
    await FacilitatorOutputPersistenceService.save('/Users/x/Plan', original);

    final loaded =
        await FacilitatorOutputPersistenceService.load('/Users/x/Plan');
    expect(loaded, isNotNull);
    expect(loaded!.format, OutputFormat.milestoneTree,
        reason: 'discriminator routes to MilestoneTree decoder');
    final restored = loaded as MilestoneTree;
    expect(restored.milestones.first.name, 'Foundation');
    expect(restored.milestones.first.dueDate, '2026-05-15');
    expect(restored.allTasks.first.title, 'Schema');
  });

  test('discriminator survives format change at the same path', () async {
    // User picks Drill Sergeant first, then switches to Game Master.
    // Same project path, different output shape — load() must route
    // to the new shape after the second save.
    final drill = MissionBriefing(
      id: 'mb',
      projectPath: '/Users/x/Switch',
      objective: 'go',
      missions: const [],
      scoreBreakdown: const ScopeScore.empty(),
      createdAt: DateTime.parse('2026-04-26T10:00:00Z'),
    );
    await FacilitatorOutputPersistenceService.save('/Users/x/Switch', drill);
    expect(
      (await FacilitatorOutputPersistenceService.load('/Users/x/Switch'))!
          .format,
      OutputFormat.missionBriefing,
    );

    await FacilitatorOutputPersistenceService.save(
        '/Users/x/Switch', _sampleLine('/Users/x/Switch'));
    expect(
      (await FacilitatorOutputPersistenceService.load('/Users/x/Switch'))!
          .format,
      OutputFormat.questLine,
    );
  });

  test('load returns null when format key is unknown (no decoder)', () async {
    // Write a hand-crafted JSON with a format string the registry has
    // never heard of. `OutputFormat.fromKey` will fall back to
    // `questLine`, so to trigger the "no decoder" path we deregister
    // the questLine decoder for the duration of this test.
    final saved =
        FacilitatorOutputPersistenceService.removeDecoder(OutputFormat.questLine);

    try {
      final path = await FacilitatorOutputPersistenceService.resolvePath(
          '/Users/x/Future');
      await File(path)
          .writeAsString('{"format":"never_registered","payload":42}');
      final loaded =
          await FacilitatorOutputPersistenceService.load('/Users/x/Future');
      expect(loaded, isNull);
    } finally {
      if (saved != null) {
        FacilitatorOutputPersistenceService.registerDecoder(
            OutputFormat.questLine, saved);
      }
    }
  });

  test('registerDecoder lets future formats plug in without code edits',
      () async {
    // Pretend a marketplace style ships with a brand-new format we
    // haven't built yet. We simulate it by registering for
    // `OutputFormat.koanEntry`, which has no built-in decoder today.
    FacilitatorOutputPersistenceService.registerDecoder(
      OutputFormat.koanEntry,
      (_) => _sampleLine('/Users/x/Plugged'),
    );

    final path = await FacilitatorOutputPersistenceService.resolvePath(
        '/Users/x/Plugged');
    await File(path).writeAsString('{"format":"koan_entry"}');

    final loaded =
        await FacilitatorOutputPersistenceService.load('/Users/x/Plugged');
    expect(loaded, isNotNull,
        reason: 'registered decoder should produce an output');
  });
}
