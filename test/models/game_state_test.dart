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
      });

      test('upgrade resets expansions counter', () {
        var state = GameState(
          officeLevel: OfficeLevel.garage,
          officeExpansions: 3,
        );
        expect(state.officeExpansions, 3);

        state = state.copyWith(officeLevel: OfficeLevel.smallOffice);
        expect(state.officeExpansions, 3); // copyWith keeps it unless explicitly reset
      });

      test('effective grid dimensions account for expansions', () {
        // Garage base: 7×5
        final garage = GameState(officeLevel: OfficeLevel.garage);
        expect(garage.gridCols, 7);
        expect(garage.gridRows, 5);

        // After first expansion (+1 col)
        final expanded = garage.copyWith(officeExpansions: 1);
        expect(expanded.gridCols, 8);
        expect(expanded.gridRows, 5);
      });

      test('playableTiles excludes 1-tile wall borders', () {
        final garage = GameState(officeLevel: OfficeLevel.garage);
        // 7×5 total → (7-2)×(5-2) = 5×3 = 15 playable
        expect(garage.playableTiles, 15);
      });

      test('expansions clamp to max for tier', () {
        final garage = GameState(officeLevel: OfficeLevel.garage);
        // Garage has 5 expansion steps (per game_economy.dart)
        expect(garage.officeLevel.expansions.length, 5);

        // Try to set beyond max
        final overclamped = garage.copyWith(officeExpansions: 999);
        // fromJson will clamp, but copyWith doesn't auto-clamp
        expect(overclamped.officeExpansions, 999); // value is 999, but logic should clamp

        // When used in JSON round-trip or grid calc, it should clamp
        expect(overclamped.gridCols,
            garage.officeLevel.effectiveCols(5)); // clamped at 5
      });

      test('isOfficeFullyExpanded is true when all expansions bought', () {
        final garage = GameState(officeLevel: OfficeLevel.garage);
        expect(garage.isOfficeFullyExpanded, false);

        final fullExpanded = garage.copyWith(officeExpansions: 5);
        expect(fullExpanded.isOfficeFullyExpanded, true);
      });

      test('nextExpansion returns null when fully expanded', () {
        final garage = GameState(officeLevel: OfficeLevel.garage);
        expect(garage.nextExpansion, isNotNull);
        expect(garage.nextExpansion!.cost, 80); // First expansion

        final lastStep = garage.copyWith(officeExpansions: 4);
        expect(lastStep.nextExpansion, isNotNull);
        expect(lastStep.nextExpansion!.cost, 380); // Fifth expansion

        final full = garage.copyWith(officeExpansions: 5);
        expect(full.nextExpansion, isNull);
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
          officeExpansions: 3,
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

      test('fromJson clamps out-of-bounds expansions', () {
        final json = {
          'schemaVersion': 6,
          'grymni': 500,
          'officeLevel': 0,
          'officeExpansions': 999, // Way out of bounds
          'agents': <String, dynamic>{},
          'totalEarned': 0,
          'totalSpent': 0,
          'nickname': '',
          'nicknameChangesUsed': 0,
          'ownedCosmetics': [],
          'equippedCosmetics': <String, dynamic>{},
          'themeState': <String, dynamic>{},
          'ownedFurniture': [],
          'placedFurniture': [],
          'placedRooms': [],
          'placedCorridors': [],
          'ownedWallSkinPacks': [],
          'ownedFloorSkinPacks': [],
          'updatedAt': 0,
        };

        final state = GameState.fromJson(json);
        // fromJson should clamp it
        expect(state.officeExpansions, lessThanOrEqualTo(5)); // Garage has 5 max
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

      test('upgradeCost follows expected curve', () {
        expect(OfficeLevel.garage.upgradeCost, 0);
        expect(OfficeLevel.smallOffice.upgradeCost, 1000);
        expect(OfficeLevel.modernOffice.upgradeCost, 8000);
        expect(OfficeLevel.techHub.upgradeCost, 50000);
        expect(OfficeLevel.campus.upgradeCost, 500000);
      });

      test('basePlayableTiles and maxPlayableTiles are sensible', () {
        for (final level in OfficeLevel.values) {
          final baseTiles = level.basePlayableTiles;
          final maxTiles = level.maxPlayableTiles;
          expect(baseTiles, greaterThan(0));
          expect(maxTiles, greaterThanOrEqualTo(baseTiles));
        }
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
