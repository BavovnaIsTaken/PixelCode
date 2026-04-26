import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pixelcode/models/facilitator_output.dart';
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

  test('load returns null when format key is unknown (no decoder)', () async {
    // Write a hand-crafted JSON with an unregistered format directly to disk.
    final path =
        await FacilitatorOutputPersistenceService.resolvePath('/Users/x/Future');
    await File(path)
        .writeAsString('{"format":"never_registered","payload":42}');

    final loaded =
        await FacilitatorOutputPersistenceService.load('/Users/x/Future');
    expect(loaded, isNull);
  });

  test('registerDecoder allows new formats to plug in', () async {
    // Register a fake decoder for a format we know nothing about.
    FacilitatorOutputPersistenceService.registerDecoder(
      OutputFormat.missionBriefing,
      (_) => _sampleLine('/Users/x/Plugged'),
    );

    final path = await FacilitatorOutputPersistenceService.resolvePath(
        '/Users/x/Plugged');
    await File(path).writeAsString('{"format":"mission_briefing"}');

    final loaded =
        await FacilitatorOutputPersistenceService.load('/Users/x/Plugged');
    expect(loaded, isNotNull);
    expect(loaded!.format, OutputFormat.questLine,
        reason: 'fake decoder returns a QuestLine for the test');
  });
}
