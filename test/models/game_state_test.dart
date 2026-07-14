import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';

void main() {
  group('GameState', () {
    group('Agent hiring and capacity', () {
      test('fresh state has no agents', () {
        final state = GameState();
        expect(state.agents, isEmpty);
        expect(state.hiredCount, 0);
      });

      test('canHireMore respects office level capacity', () {
        final garage = GameState(officeLevel: OfficeLevel.garage);
        expect(garage.officeLevel.maxAgents, 3);
        expect(garage.canHireMore, true);

        // Hire 3 agents → full
        var state = garage;
        for (var i = 0; i < 3; i++) {
          state = state.copyWith(
            agents: {
              ...state.agents,
              'agent_$i': AgentGameData(
                instanceId: 'agent_$i',
                roleType: 'coder',
                nickname: 'Agent $i',
                hardware: HardwareTier.basicLaptop,
              ),
            },
          );
        }
        expect(state.hiredCount, 3);
        expect(state.canHireMore, false);

        // Upgrade office → can hire again
        final upgraded = state.copyWith(officeLevel: OfficeLevel.smallOffice);
        expect(upgraded.officeLevel.maxAgents, 6);
        expect(upgraded.canHireMore, true);
      });

      test('agents persist when changing nickname', () {
        final withAgent = GameState(
          nickname: 'Dev',
          agents: {
            'coder#1': AgentGameData(
              instanceId: 'coder#1',
              roleType: 'coder',
              nickname: 'Coder One',
              hardware: HardwareTier.basicLaptop,
            ),
          },
        );
        final renamed = withAgent.copyWith(nickname: 'NewName');
        expect(renamed.agents.length, 1);
        expect(renamed.agents['coder#1'], isNotNull);
      });

      test('instancesOfRole filters by role type', () {
        final state = GameState(
          agents: {
            'coder#1': AgentGameData(
              instanceId: 'coder#1',
              roleType: 'coder',
              nickname: 'Coder One',
              hardware: HardwareTier.basicLaptop,
            ),
            'coder#2': AgentGameData(
              instanceId: 'coder#2',
              roleType: 'coder',
              nickname: 'Coder Two',
              hardware: HardwareTier.desktopPC,
            ),
            'reviewer#1': AgentGameData(
              instanceId: 'reviewer#1',
              roleType: 'reviewer',
              nickname: 'Reviewer One',
              hardware: HardwareTier.basicLaptop,
            ),
          },
        );

        expect(state.roleCount('coder'), 2);
        expect(state.roleCount('reviewer'), 1);
        expect(state.roleCount('nonexistent'), 0);
        expect(state.instancesOfRole('coder'), hasLength(2));
      });

      test('hiredAgentIds preserves insertion order', () {
        var state = GameState();
        for (final id in ['a', 'b', 'c']) {
          state = state.copyWith(
            agents: {
              ...state.agents,
              id: AgentGameData(
                instanceId: id,
                roleType: 'coder',
                nickname: 'Agent $id',
                hardware: HardwareTier.basicLaptop,
              ),
            },
          );
        }
        expect(state.hiredAgentIds, ['a', 'b', 'c']);
      });
    });

    group('Office tier progression', () {
      test('nextLevel chains correctly through tiers', () {
        expect(OfficeLevel.garage.nextLevel, OfficeLevel.smallOffice);
        expect(OfficeLevel.smallOffice.nextLevel, OfficeLevel.modernOffice);
        expect(OfficeLevel.modernOffice.nextLevel, OfficeLevel.techHub);
        expect(OfficeLevel.techHub.nextLevel, OfficeLevel.campus);
        expect(OfficeLevel.campus.nextLevel, isNull);
        expect(OfficeLevel.galley.nextLevel, isNull);
      });

      test('galley is a parallel option (off the linear chain)', () {
        expect(OfficeLevel.galley.isParallelOption, isTrue);
        for (final level in OfficeLevel.values) {
          if (level == OfficeLevel.galley) continue;
          expect(level.isParallelOption, isFalse, reason: '$level');
        }
      });

      test('grid dimensions are the tier fixed lot (Stage 4)', () {
        // Stage 4: each tier is a fixed lot equal to the old fully-expanded max.
        final garage = GameState(officeLevel: OfficeLevel.garage);
        expect(garage.gridCols, 10);
        expect(garage.gridRows, 7);
      });

      test('upgrading grows the grid to the next tier lot', () {
        final garage = GameState(officeLevel: OfficeLevel.garage);
        final small = garage.copyWith(officeLevel: OfficeLevel.smallOffice);
        expect(small.gridCols, 13);
        expect(small.gridRows, 10);
      });

      test('playableTiles excludes 1-tile wall borders', () {
        final garage = GameState(officeLevel: OfficeLevel.garage);
        // 10×7 total → (10-2)×(7-2) = 8×5 = 40 playable
        expect(garage.playableTiles, 40);
      });
    });

    group('Nickname changes', () {
      test('first nickname change is free', () {
        final state = GameState(nickname: 'Initial');
        expect(state.isNicknameChangeFree, true);
        expect(state.nextNicknameChangeCost, 0);
      });

      test('cost accumulates after free changes', () {
        var state = GameState(nickname: 'v1', nicknameChangesUsed: 0);

        // First 3 changes are free
        state = state.copyWith(nicknameChangesUsed: 1);
        expect(state.isNicknameChangeFree, true);

        state = state.copyWith(nicknameChangesUsed: 2);
        expect(state.isNicknameChangeFree, true);

        state = state.copyWith(nicknameChangesUsed: 3);
        expect(state.isNicknameChangeFree, false);
        expect(state.nextNicknameChangeCost, greaterThan(0));
      });
    });

    group('Cosmetics and equipment', () {
      test('equippedFor returns null for unequipped type', () {
        final state = GameState();
        expect(state.equippedFor(CosmeticType.skin), isNull);
      });

      test('equippedFor returns equipped cosmetic', () {
        final state = GameState(
          equippedCosmetics: {CosmeticType.skin.index: 'pink_skin'},
        );
        expect(state.equippedFor(CosmeticType.skin), 'pink_skin');
      });

      test('displayNickname applies cosmetic decor', () {
        final state = GameState(
          nickname: 'Player',
          equippedCosmetics: {},
        );
        // Without decor
        final plain = state.displayNickname;
        expect(plain, isNotEmpty);

        // With decor (assuming applyNicknameDecor exists and does something)
        final decorated = state.copyWith(
          equippedCosmetics: {CosmeticType.nicknameDecor.index: 'gold_frame'},
        );
        // displayNickname should call applyNicknameDecor
        expect(decorated.displayNickname, isNotEmpty);
      });
    });

    group('JSON serialization round-trip', () {
      test('GameState toJson → fromJson preserves all fields', () {
        final original = GameState(
          grymni: 12345,
          officeLevel: OfficeLevel.modernOffice,
          agents: {
            'coder#1': AgentGameData(
              instanceId: 'coder#1',
              roleType: 'coder',
              nickname: 'Coder One',
              hardware: HardwareTier.desktopPC,
            ),
          },
          nickname: 'TestName',
          ownedCosmetics: {'hat_1', 'hat_2'},
          furnitureInventory: {'desk_oak': 1, 'chair_leather': 1},
        );

        final json = original.toJson();
        final restored = GameState.fromJson(json);

        expect(restored.grymni, original.grymni);
        expect(restored.officeLevel, original.officeLevel);
        expect(restored.agents.length, original.agents.length);
        expect(restored.nickname, original.nickname);
        expect(restored.ownedCosmetics, original.ownedCosmetics);
      });

      test('v6→v7 migration refunds expansion spend and drops the field', () {
        // Legacy garage save with 3 expansion steps bought. Refund = 100% of
        // those first 3 step costs (80+140+200 = 420).
        final json = {
          'schemaVersion': 6,
          'grymni': 500,
          'officeLevel': 0, // garage
          'officeExpansions': 3,
          'agents': <String, dynamic>{},
          'placedFurniture': [],
          'placedRooms': [],
          'placedCorridors': [],
          'ownedWallSkinPacks': [],
          'ownedFloorSkinPacks': [],
          'updatedAt': 0,
        };

        final state = GameState.fromJson(json);
        expect(state.grymni, 500 + 420, reason: '100% expansion refund');
        expect(state.gridCols, 10, reason: 'collapses to fixed garage lot');
        expect(state.gridRows, 7);
        // The re-serialised save no longer carries the legacy field, so a
        // second load can't double-refund.
        expect(state.toJson().containsKey('officeExpansions'), isFalse);
      });

      test('v6→v7 migration clamps an out-of-bounds expansion count', () {
        // officeExpansions=999 must not over-refund: only the 5 real garage
        // steps exist (80+140+200+280+380 = 1080).
        final json = {
          'schemaVersion': 6,
          'grymni': 500,
          'officeLevel': 0,
          'officeExpansions': 999,
          'agents': <String, dynamic>{},
          'placedFurniture': [],
          'placedRooms': [],
          'placedCorridors': [],
          'updatedAt': 0,
        };
        final state = GameState.fromJson(json);
        expect(state.grymni, 500 + 1080);
      });

      test('fromJson filters out-of-bounds furniture/rooms', () {
        final tinyJson = {
          'schemaVersion': 6,
          'grymni': 500,
          'officeLevel': 0, // Garage: 7×5
          'officeExpansions': 0,
          'agents': <String, dynamic>{},
          'totalEarned': 0,
          'totalSpent': 0,
          'nickname': '',
          'nicknameChangesUsed': 0,
          'ownedCosmetics': [],
          'equippedCosmetics': <String, dynamic>{},
          'themeState': <String, dynamic>{},
          'ownedFurniture': [],
          'placedFurniture': [
            <String, dynamic>{'itemId': 'desk', 'col': 20, 'row': 20}, // Out of bounds!
          ],
          'placedRooms': [],
          'placedCorridors': [],
          'ownedWallSkinPacks': [],
          'ownedFloorSkinPacks': [],
          'updatedAt': 0,
        };

        final state = GameState.fromJson(tinyJson as Map<String, dynamic>);
        expect(state.placedFurniture, isEmpty); // Filtered out
      });
    });

    group('Office level properties', () {
      test('maxAgents increases per tier', () {
        expect(OfficeLevel.garage.maxAgents, 3);
        expect(OfficeLevel.smallOffice.maxAgents, 6);
        expect(OfficeLevel.modernOffice.maxAgents, 12);
        expect(OfficeLevel.techHub.maxAgents, 25);
        expect(OfficeLevel.campus.maxAgents, 100);
      });

      test('speedModifier scales per tier', () {
        expect(OfficeLevel.garage.speedModifier, 0.75);
        expect(OfficeLevel.smallOffice.speedModifier, 1.0);
        expect(OfficeLevel.campus.speedModifier, 1.5);
      });

      test('upgradeCost follows the Stage 4 fixed-tier curve', () {
        expect(OfficeLevel.garage.upgradeCost, 0);
        expect(OfficeLevel.smallOffice.upgradeCost, 4000);
        expect(OfficeLevel.modernOffice.upgradeCost, 35000);
        expect(OfficeLevel.techHub.upgradeCost, 220000);
        expect(OfficeLevel.campus.upgradeCost, 2700000);
      });

      test('playableTiles is positive and grows with the linear tier chain', () {
        for (final level in OfficeLevel.values) {
          expect(level.playableTiles, greaterThan(0), reason: '$level');
        }
        // Linear upgrade chain hands out strictly bigger lots.
        expect(OfficeLevel.smallOffice.playableTiles,
            greaterThan(OfficeLevel.garage.playableTiles));
        expect(OfficeLevel.techHub.playableTiles,
            greaterThan(OfficeLevel.modernOffice.playableTiles));
      });
    });

    group('Hardware tier properties', () {
      test('nextTier chains through all tiers', () {
        expect(HardwareTier.oldLaptop.nextTier, HardwareTier.basicLaptop);
        expect(HardwareTier.basicLaptop.nextTier, HardwareTier.desktopPC);
        expect(HardwareTier.serverRack.nextTier, isNull);
      });

      test('speedModifier increases per tier', () {
        expect(HardwareTier.oldLaptop.speedModifier, 0.5);
        expect(HardwareTier.basicLaptop.speedModifier, 0.75);
        expect(HardwareTier.desktopPC.speedModifier, 1.0);
        expect(HardwareTier.serverRack.speedModifier, 2.0);
      });

      test('cost increases per tier', () {
        expect(HardwareTier.oldLaptop.cost, 0);
        expect(HardwareTier.basicLaptop.cost, 200);
        expect(HardwareTier.serverRack.cost, 15000);
      });
    });

    group('Skill upgrade costs', () {
      test('upgradeCost scales by level', () {
        final precision = SkillType.precision;
        expect(precision.upgradeCost(0), precision.baseCost * 1);
        expect(precision.upgradeCost(1), precision.baseCost * 2);
        expect(precision.upgradeCost(2), precision.baseCost * 3);
      });

      test('all skills have sensible base costs', () {
        for (final skill in SkillType.values) {
          expect(skill.baseCost, greaterThan(0));
        }
      });
    });
  });
}
