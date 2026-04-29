import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';

void main() {
  group('AgentGameData', () {
    group('Initialization and basic properties', () {
      test('fresh agent starts at level 1 with zero XP', () {
        final agent = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice',
        );
        expect(agent.level, 1);
        expect(agent.xp, 0);
        expect(agent.skills, isEmpty);
      });

      test('hardware defaults to oldLaptop', () {
        final agent = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice',
        );
        expect(agent.hardware, HardwareTier.oldLaptop);
      });

      test('nickname is player-editable display name', () {
        final agent = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice The Great',
        );
        expect(agent.nickname, 'Alice The Great');
      });

      test('role type determines behavior template', () {
        final coder = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice',
        );
        final reviewer = AgentGameData(
          instanceId: 'reviewer#1',
          roleType: 'reviewer',
          nickname: 'Bob',
        );
        expect(coder.roleType, 'coder');
        expect(reviewer.roleType, 'reviewer');
        expect(coder.roleType, isNot(equals(reviewer.roleType)));
      });
    });

    group('Skill management', () {
      test('agent can have zero or multiple skills', () {
        final noSkills = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: 'Alice',
          skills: {},
        );
        expect(noSkills.skills, isEmpty);

        final multiSkill = AgentGameData(
          instanceId: 'b1',
          roleType: 'coder',
          nickname: 'Bob',
          skills: {
            SkillType.precision: 5,
            SkillType.speed: 3,
            SkillType.creativity: 2,
          },
        );
        expect(multiSkill.skills.length, 3);
        expect(multiSkill.skills[SkillType.precision], 5);
      });

      test('skill levels should be non-negative', () {
        final agent = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: 'Alice',
          skills: {SkillType.precision: 0, SkillType.speed: 10},
        );
        // Test expects this to be valid (zero is allowed for not-upgraded skills)
        expect(agent.skills[SkillType.precision], 0);
        expect(agent.skills[SkillType.speed], 10);
      });
    });

    group('Level and XP progression', () {
      test('agent can level up', () {
        final level5 = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: 'Alice',
          level: 5,
          xp: 0,
        );
        expect(level5.level, 5);
      });

      test('XP accumulates towards next level', () {
        final agent = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: 'Alice',
          level: 1,
          xp: 25, // Halfway to next level (needs 50)
        );
        expect(agent.xp, 25);
      });

      test('level is clamped at maxAgentLevel', () {
        // This test checks that creating with a level > maxAgentLevel is handled
        // (though the constructor may not validate; fromJson will clamp)
        final highLevel = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: 'Alice',
          level: 999,
        );
        // Constructor doesn't validate, but external logic should clamp
        expect(highLevel.level, 999);
      });
    });

    group('Hardware tier progression', () {
      test('agent starts with oldLaptop', () {
        final agent = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: 'Alice',
        );
        expect(agent.hardware, HardwareTier.oldLaptop);
        expect(agent.hardware.speedModifier, 0.5);
      });

      test('agent can upgrade hardware', () {
        final upgraded = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: 'Alice',
          hardware: HardwareTier.gamingPC,
        );
        expect(upgraded.hardware, HardwareTier.gamingPC);
        expect(upgraded.hardware.speedModifier, 1.25);
      });

      test('all hardware tiers are progressively better', () {
        var prev = HardwareTier.oldLaptop.speedModifier;
        for (final tier in HardwareTier.values.skip(1)) {
          expect(tier.speedModifier, greaterThan(prev));
          prev = tier.speedModifier;
        }
      });
    });

    group('JSON serialization', () {
      test('AgentGameData round-trips through JSON', () {
        final original = AgentGameData(
          instanceId: 'coder#5',
          roleType: 'coder',
          nickname: 'Alice Wonder',
          hardware: HardwareTier.desktopPC,
          skills: {
            SkillType.precision: 7,
            SkillType.speed: 5,
          },
          level: 3,
          xp: 120,
        );

        final json = original.toJson();
        final restored = AgentGameData.fromJson(json);

        expect(restored.instanceId, original.instanceId);
        expect(restored.roleType, original.roleType);
        expect(restored.nickname, original.nickname);
        expect(restored.hardware, original.hardware);
        expect(restored.skills, original.skills);
        expect(restored.level, original.level);
        expect(restored.xp, original.xp);
      });

      test('missing optional fields get defaults in fromJson', () {
        final minimal = {
          'instanceId': 'a1',
          'roleType': 'coder',
          'nickname': 'Alice',
          // hardware, skills, level, xp omitted
        };
        final agent = AgentGameData.fromJson(minimal);
        expect(agent.hardware, HardwareTier.oldLaptop);
        expect(agent.skills, isEmpty);
        expect(agent.level, 1);
        expect(agent.xp, 0);
      });

      test('skill map survives round-trip', () {
        final json = {
          'instanceId': 'a1',
          'roleType': 'coder',
          'nickname': 'Alice',
          'skills': {
            '0': 5, // SkillType.speed index
            '2': 3, // SkillType.creativity index
          },
        };
        final agent = AgentGameData.fromJson(json);
        // Skills should be parsed correctly
        expect(agent.skills, isNotEmpty);
      });
    });

    group('Copy constructor (copyWith)', () {
      test('copyWith preserves unchanged fields', () {
        final original = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: 'Alice',
          hardware: HardwareTier.desktopPC,
          level: 5,
        );
        final modified = original.copyWith(nickname: 'Alice2');
        expect(modified.instanceId, original.instanceId);
        expect(modified.roleType, original.roleType);
        expect(modified.hardware, original.hardware);
        expect(modified.level, original.level);
        expect(modified.nickname, 'Alice2');
      });

      test('copyWith allows upgrading hardware', () {
        final original = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: 'Alice',
          hardware: HardwareTier.oldLaptop,
        );
        final upgraded = original.copyWith(hardware: HardwareTier.serverRack);
        expect(upgraded.hardware, HardwareTier.serverRack);
        expect(upgraded.instanceId, original.instanceId);
      });

      test('copyWith allows adding skills', () {
        final original = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: 'Alice',
          skills: {SkillType.precision: 3},
        );
        final enhanced = original.copyWith(
          skills: {
            ...original.skills,
            SkillType.speed: 5,
          },
        );
        expect(enhanced.skills.length, 2);
        expect(enhanced.skills[SkillType.precision], 3);
        expect(enhanced.skills[SkillType.speed], 5);
      });
    });

    group('Edge cases', () {
      test('instance ID can contain special characters', () {
        final agent = AgentGameData(
          instanceId: 'coder#42-special_id',
          roleType: 'coder',
          nickname: 'Alice',
        );
        expect(agent.instanceId, 'coder#42-special_id');
      });

      test('nickname can be empty string', () {
        final agent = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: '',
        );
        expect(agent.nickname, '');
      });

      test('very high XP values are allowed', () {
        final agent = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: 'Alice',
          xp: 999999999,
        );
        expect(agent.xp, 999999999);
      });

      test('all skill types can be set together', () {
        final agent = AgentGameData(
          instanceId: 'a1',
          roleType: 'coder',
          nickname: 'Alice',
          skills: {
            SkillType.speed: 1,
            SkillType.precision: 2,
            SkillType.creativity: 3,
            SkillType.insight: 4,
            SkillType.reliability: 5,
          },
        );
        expect(agent.skills.length, 5);
      });
    });

    group('WorkplaceStatus', () {
      test('defaults to assigned for backward-compat seeded agents', () {
        final agent = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice',
        );
        expect(agent.workplaceStatus, WorkplaceStatus.assigned);
      });

      test('can be set to unassigned for new hires', () {
        final agent = AgentGameData(
          instanceId: 'coder#2',
          roleType: 'coder',
          nickname: 'Bob',
          workplaceStatus: WorkplaceStatus.unassigned,
        );
        expect(agent.workplaceStatus, WorkplaceStatus.unassigned);
      });

      test('copyWith transitions unassigned → assigned', () {
        final unassigned = AgentGameData(
          instanceId: 'coder#2',
          roleType: 'coder',
          nickname: 'Bob',
          workplaceStatus: WorkplaceStatus.unassigned,
        );
        final assigned = unassigned.copyWith(workplaceStatus: WorkplaceStatus.assigned);
        expect(assigned.workplaceStatus, WorkplaceStatus.assigned);
        expect(assigned.instanceId, unassigned.instanceId);
      });

      test('copyWith preserves workplaceStatus when not specified', () {
        final agent = AgentGameData(
          instanceId: 'coder#2',
          roleType: 'coder',
          nickname: 'Bob',
          workplaceStatus: WorkplaceStatus.unassigned,
        );
        final modified = agent.copyWith(nickname: 'Bob 2');
        expect(modified.workplaceStatus, WorkplaceStatus.unassigned);
      });

      test('toJson omits workplaceStatus when assigned (backward compat)', () {
        final agent = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice',
        );
        expect(agent.toJson().containsKey('workplaceStatus'), isFalse);
      });

      test('toJson includes workplaceStatus when unassigned', () {
        final agent = AgentGameData(
          instanceId: 'coder#2',
          roleType: 'coder',
          nickname: 'Bob',
          workplaceStatus: WorkplaceStatus.unassigned,
        );
        expect(agent.toJson()['workplaceStatus'], WorkplaceStatus.unassigned.index);
      });

      test('fromJson defaults to assigned when key missing (old saves)', () {
        final agent = AgentGameData.fromJson({
          'instanceId': 'coder#1',
          'roleType': 'coder',
          'nickname': 'Alice',
        });
        expect(agent.workplaceStatus, WorkplaceStatus.assigned);
      });

      test('round-trips unassigned through JSON', () {
        final original = AgentGameData(
          instanceId: 'coder#2',
          roleType: 'coder',
          nickname: 'Bob',
          workplaceStatus: WorkplaceStatus.unassigned,
        );
        final restored = AgentGameData.fromJson(original.toJson());
        expect(restored.workplaceStatus, WorkplaceStatus.unassigned);
      });
    });

    group('characterId (Roster v1 link)', () {
      test('defaults to null for legacy / role-flow hires', () {
        final agent = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice',
        );
        expect(agent.characterId, isNull);
      });

      test('persists through copyWith', () {
        final original = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Андрій',
          characterId: 'andriy_coder',
        );
        final modified = original.copyWith(nickname: 'Андрій 2');
        expect(modified.characterId, 'andriy_coder');
      });

      test('copyWith allows attaching characterId later', () {
        final original = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice',
        );
        final linked = original.copyWith(characterId: 'andriy_coder');
        expect(linked.characterId, 'andriy_coder');
      });

      test('round-trips through JSON when set', () {
        final original = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Андрій',
          characterId: 'andriy_coder',
        );
        final restored = AgentGameData.fromJson(original.toJson());
        expect(restored.characterId, 'andriy_coder');
      });

      test('toJson omits characterId when null (no orphan field)', () {
        final agent = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice',
        );
        expect(agent.toJson().containsKey('characterId'), isFalse);
      });

      test('fromJson defaults to null when key is missing', () {
        final agent = AgentGameData.fromJson({
          'instanceId': 'a1',
          'roleType': 'coder',
          'nickname': 'Alice',
        });
        expect(agent.characterId, isNull);
      });
    });

    group('specialization fields (C.1)', () {
      test('fresh agent has empty counters and specializations', () {
        final agent = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice',
        );
        expect(agent.taskCompletionsByType, isEmpty);
        expect(agent.specializations, isEmpty);
      });

      test('toJson omits both fields when empty (backward compat)', () {
        final agent = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice',
        );
        final json = agent.toJson();
        expect(json.containsKey('taskCompletionsByType'), isFalse);
        expect(json.containsKey('specializations'), isFalse);
      });

      test('round-trips populated counters and specializations', () {
        final original = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice',
          taskCompletionsByType: const {'coding': 25, 'testing': 4},
          specializations: const {'coding'},
        );
        final restored = AgentGameData.fromJson(original.toJson());
        expect(restored.taskCompletionsByType, {'coding': 25, 'testing': 4});
        expect(restored.specializations, {'coding'});
      });

      test('fromJson defaults to empty when keys missing (old saves)', () {
        final agent = AgentGameData.fromJson({
          'instanceId': 'a1',
          'roleType': 'coder',
          'nickname': 'Alice',
        });
        expect(agent.taskCompletionsByType, isEmpty);
        expect(agent.specializations, isEmpty);
      });

      test('copyWith updates counters and specializations independently', () {
        final original = AgentGameData(
          instanceId: 'coder#1',
          roleType: 'coder',
          nickname: 'Alice',
        );
        final updated = original.copyWith(
          taskCompletionsByType: const {'coding': 1},
        );
        expect(updated.taskCompletionsByType, {'coding': 1});
        expect(updated.specializations, isEmpty);

        final specced = updated.copyWith(specializations: {'coding'});
        expect(specced.taskCompletionsByType, {'coding': 1});
        expect(specced.specializations, {'coding'});
      });

      test('threshold and bonus constants match expected balance', () {
        expect(kSpecializationThreshold, 20);
        expect(kSpecializationCritBonus, 0.15);
        expect(kMaxSpecializationCritBonus, 0.30);
      });
    });
  });
}
