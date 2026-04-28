import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/services/agent_export_service.dart';
import 'package:pixelcode/widgets/personalization/custom_agent_spawn_form.dart';

// ─── Fixtures ──────────────────────────────────────────────────────────────

AgentGameData _makeAgent({
  String instanceId = 'coder#1',
  String roleType = 'coder',
  String nickname = 'Андрій',
  String? customSystemPrompt,
  String? personalityPreset = 'speedster',
  String? characterId,
  Map<SkillType, int>? skills,
}) =>
    AgentGameData(
      instanceId: instanceId,
      roleType: roleType,
      nickname: nickname,
      customSystemPrompt: customSystemPrompt,
      personalityPreset: personalityPreset,
      characterId: characterId,
      skills: skills ??
          {
            SkillType.speed: 5,
            SkillType.precision: 3,
            SkillType.creativity: 2,
            SkillType.insight: 3,
            SkillType.reliability: 2,
          },
    );

// ─── AgentBlueprint ────────────────────────────────────────────────────────

void main() {
  const service = AgentExportService();

  group('AgentBlueprint.fromAgent', () {
    test('copies identity fields', () {
      final agent = _makeAgent();
      final bp = AgentBlueprint.fromAgent(agent);

      expect(bp.roleType, 'coder');
      expect(bp.nickname, 'Андрій');
      expect(bp.personalityPreset, 'speedster');
    });

    test('strips runtime-only fields (instanceId not in blueprint)', () {
      final agent = _makeAgent(instanceId: 'coder#99');
      final bp = AgentBlueprint.fromAgent(agent);
      final json = bp.toJson();

      expect(json.containsKey('instanceId'), isFalse);
      expect(json.containsKey('level'), isFalse);
      expect(json.containsKey('xp'), isFalse);
      expect(json.containsKey('hardware'), isFalse);
      expect(json.containsKey('provider'), isFalse);
    });

    test('version is set to "1"', () {
      final bp = AgentBlueprint.fromAgent(_makeAgent());
      expect(bp.version, '1');
    });

    test('copies skills map', () {
      final agent = _makeAgent(skills: {
        SkillType.speed: 7,
        SkillType.precision: 4,
      });
      final bp = AgentBlueprint.fromAgent(agent);
      expect(bp.skills[SkillType.speed], 7);
      expect(bp.skills[SkillType.precision], 4);
    });

    test('null optional fields remain null', () {
      final agent = _makeAgent(customSystemPrompt: null, characterId: null);
      final bp = AgentBlueprint.fromAgent(agent);
      expect(bp.customSystemPrompt, isNull);
      expect(bp.characterId, isNull);
    });

    test('non-null optional fields are copied', () {
      final agent = _makeAgent(
        customSystemPrompt: 'Be concise.',
        characterId: 'andriy_coder',
      );
      final bp = AgentBlueprint.fromAgent(agent);
      expect(bp.customSystemPrompt, 'Be concise.');
      expect(bp.characterId, 'andriy_coder');
    });
  });

  // ─── Serialization roundtrip ──────────────────────────────────────────────

  group('AgentBlueprint JSON roundtrip', () {
    test('toJson → fromJson preserves all fields', () {
      final original = AgentBlueprint.fromAgent(_makeAgent(
        customSystemPrompt: 'Test prompt',
        characterId: 'andriy_coder',
      ));
      final restored = AgentBlueprint.fromJson(original.toJson());

      expect(restored.version, original.version);
      expect(restored.roleType, original.roleType);
      expect(restored.nickname, original.nickname);
      expect(restored.customSystemPrompt, original.customSystemPrompt);
      expect(restored.personalityPreset, original.personalityPreset);
      expect(restored.characterId, original.characterId);
      expect(restored.skills, original.skills);
    });

    test('toJson omits null optional keys', () {
      final bp = AgentBlueprint.fromAgent(
          _makeAgent(customSystemPrompt: null, characterId: null));
      final json = bp.toJson();

      expect(json.containsKey('customSystemPrompt'), isFalse);
      expect(json.containsKey('characterId'), isFalse);
    });

    test('fromJson throws FormatException on missing version', () {
      expect(
        () => AgentBlueprint.fromJson({'roleType': 'coder', 'nickname': 'X',
            'skills': {}, 'exportedAt': '2026-01-01T00:00:00.000Z'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson throws FormatException on unknown version', () {
      expect(
        () => AgentBlueprint.fromJson({'pixelcodeAgent': '99', 'roleType': 'coder',
            'nickname': 'X', 'skills': {}, 'exportedAt': '2026-01-01T00:00:00.000Z'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson ignores out-of-range skill indices gracefully', () {
      final json = {
        'pixelcodeAgent': '1',
        'roleType': 'coder',
        'nickname': 'X',
        'skills': {'0': 5, '999': 3},
        'exportedAt': '2026-01-01T00:00:00.000Z',
      };
      final bp = AgentBlueprint.fromJson(json);
      expect(bp.skills[SkillType.values[0]], 5);
      expect(bp.skills.length, 1);
    });
  });

  // ─── AgentExportService.exportToString / importFromString ─────────────────

  group('AgentExportService string export/import', () {
    test('exportToString produces valid JSON', () {
      final bp = AgentBlueprint.fromAgent(_makeAgent());
      final jsonStr = service.exportToString(bp);
      expect(() => service.importFromString(jsonStr), returnsNormally);
    });

    test('importFromString roundtrips nickname', () {
      final bp = AgentBlueprint.fromAgent(_makeAgent(nickname: 'Тетяна'));
      final restored = service.importFromString(service.exportToString(bp));
      expect(restored.nickname, 'Тетяна');
    });

    test('importFromString roundtrips skills', () {
      final skills = {
        SkillType.speed: 8,
        SkillType.precision: 2,
        SkillType.creativity: 5,
        SkillType.insight: 1,
        SkillType.reliability: 4,
      };
      final bp = AgentBlueprint.fromAgent(_makeAgent(skills: skills));
      final restored = service.importFromString(service.exportToString(bp));
      expect(restored.skills, skills);
    });

    test('importFromString throws on invalid JSON', () {
      expect(
        () => service.importFromString('not json at all'),
        throwsA(isA<FormatException>()),
      );
    });

    test('importFromString throws when root is not an object', () {
      expect(
        () => service.importFromString('[1, 2, 3]'),
        throwsA(isA<FormatException>()),
      );
    });

    test('importFromString throws on missing version', () {
      expect(
        () => service.importFromString('{"roleType":"coder","nickname":"X",'
            '"skills":{},"exportedAt":"2026-01-01T00:00:00.000Z"}'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ─── AgentExportService.toSpawnData ───────────────────────────────────────

  group('AgentExportService.toSpawnData', () {
    test('maps roleType to selectedRole', () {
      final bp = AgentBlueprint.fromAgent(_makeAgent(roleType: 'reviewer'));
      final spawn = service.toSpawnData(bp);
      expect(spawn.selectedRole, 'reviewer');
    });

    test('maps nickname', () {
      final bp = AgentBlueprint.fromAgent(_makeAgent(nickname: 'Богдан'));
      final spawn = service.toSpawnData(bp);
      expect(spawn.nickname, 'Богдан');
    });

    test('maps customSystemPrompt to systemPrompt', () {
      final bp = AgentBlueprint.fromAgent(
          _makeAgent(customSystemPrompt: 'Be concise.'));
      final spawn = service.toSpawnData(bp);
      expect(spawn.systemPrompt, 'Be concise.');
    });

    test('null systemPrompt maps to empty string', () {
      final bp = AgentBlueprint.fromAgent(_makeAgent(customSystemPrompt: null));
      final spawn = service.toSpawnData(bp);
      expect(spawn.systemPrompt, '');
    });

    test('maps skills to skillWeights', () {
      final skills = {SkillType.speed: 7, SkillType.precision: 4,
          SkillType.creativity: 3, SkillType.insight: 2, SkillType.reliability: 5};
      final bp = AgentBlueprint.fromAgent(_makeAgent(skills: skills));
      final spawn = service.toSpawnData(bp);
      expect(spawn.skillWeights[SkillType.speed], 7);
      expect(spawn.skillWeights[SkillType.precision], 4);
    });

    test('empty skills defaults to all-3 balanced weights', () {
      final bp = AgentBlueprint(
        version: '1',
        roleType: 'coder',
        nickname: 'X',
        skills: const {},
        exportedAt: DateTime(2026),
      );
      final spawn = service.toSpawnData(bp);
      for (final s in SkillType.values) {
        expect(spawn.skillWeights[s], 3, reason: '${s.name} should be 3');
      }
    });

    test('null personalityPreset defaults to balanced', () {
      final bp = AgentBlueprint(
        version: '1',
        roleType: 'coder',
        nickname: 'X',
        skills: const {},
        exportedAt: DateTime(2026),
        personalityPreset: null,
      );
      final spawn = service.toSpawnData(bp);
      expect(spawn.personalityPreset, 'balanced');
    });

    test('maps personalityPreset when set', () {
      final bp = AgentBlueprint.fromAgent(
          _makeAgent(personalityPreset: 'creative'));
      final spawn = service.toSpawnData(bp);
      expect(spawn.personalityPreset, 'creative');
    });

    test('toSpawnData result is a valid CustomAgentSpawnData', () {
      final bp = AgentBlueprint.fromAgent(_makeAgent());
      final spawn = service.toSpawnData(bp);
      expect(spawn, isA<CustomAgentSpawnData>());
    });
  });
}
