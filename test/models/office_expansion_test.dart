import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';

void main() {
  group('OfficeLevel expansion mechanics', () {
    group('Garage tier', () {
      test('garage has 5 expansion steps', () {
        expect(OfficeLevel.garage.expansions.length, 5);
      });

      test('garage expansions increase grid incrementally', () {
        final garage = OfficeLevel.garage;
        expect(garage.baseCols, 7);
        expect(garage.baseRows, 5);

        // After each expansion, grid grows
        expect(garage.effectiveCols(0), 7);
        expect(garage.effectiveCols(1), 8); // +1 col
        expect(garage.effectiveCols(2), 9); // +1 col
        expect(garage.effectiveCols(3), 9); // no change
        expect(garage.effectiveCols(4), 10); // +1 col
        expect(garage.effectiveCols(5), 10); // no change

        expect(garage.effectiveRows(0), 5);
        expect(garage.effectiveRows(3), 6); // +1 row at step 3
        expect(garage.effectiveRows(5), 7); // +1 row at step 5
      });

      test('garage expansion costs increase monotonically', () {
        final steps = OfficeLevel.garage.expansions;
        for (var i = 1; i < steps.length; i++) {
          expect(steps[i].cost, greaterThan(steps[i - 1].cost));
        }
      });

      test('garage maxPlayableTiles ~ 40 after full expansion', () {
        final garage = OfficeLevel.garage;
        // 10×7 total grid → (10-2)×(7-2) = 8×5 = 40 playable
        expect(garage.maxPlayableTiles, 40);
      });
    });

    group('Small Office tier', () {
      test('smallOffice has 8 expansion steps', () {
        expect(OfficeLevel.smallOffice.expansions.length, 8);
      });

      test('smallOffice grows from 9×6 to 13×10 base', () {
        final so = OfficeLevel.smallOffice;
        expect(so.baseCols, 9);
        expect(so.baseRows, 6);
        expect(so.maxPlayableTiles, (13 - 2) * (10 - 2)); // 88
      });

      test('expansion costs scale up vs garage', () {
        final soFirst = OfficeLevel.smallOffice.expansions[0].cost;
        final garageFirst = OfficeLevel.garage.expansions[0].cost;
        expect(soFirst, greaterThan(garageFirst));
      });
    });

    group('Expansion cost formula', () {
      test('each tier is progressively more expensive', () {
        final tiers = [
          OfficeLevel.garage,
          OfficeLevel.smallOffice,
          OfficeLevel.modernOffice,
          OfficeLevel.techHub,
          OfficeLevel.campus,
        ];

        for (var i = 1; i < tiers.length; i++) {
          final prevFirst = tiers[i - 1].expansions[0].cost;
          final currFirst = tiers[i].expansions[0].cost;
          expect(currFirst, greaterThan(prevFirst),
              reason: '${tiers[i]} first expansion should be more expensive than ${tiers[i - 1]}');
        }
      });

      test('upgrade to next tier is more expensive than last expansion', () {
        final garage = OfficeLevel.garage;
        final lastExpansion = garage.expansions.last.cost;
        final upgradeToSmallOffice = OfficeLevel.smallOffice.upgradeCost;
        expect(upgradeToSmallOffice, greaterThan(lastExpansion));
      });
    });

    group('Playable tiles calculation', () {
      test('playable tiles = (cols-2) × (rows-2)', () {
        final garage = OfficeLevel.garage;
        expect(garage.playableTiles(0), (7 - 2) * (5 - 2)); // 15
        expect(garage.basePlayableTiles, 15);
      });

      test('full expanded garage has 40 playable tiles', () {
        final garage = OfficeLevel.garage;
        final maxSteps = garage.expansions.length;
        expect(garage.playableTiles(maxSteps), 40);
        expect(garage.maxPlayableTiles, 40);
      });

      test('campus is largest office', () {
        final tiles = {
          'garage': OfficeLevel.garage.maxPlayableTiles,
          'smallOffice': OfficeLevel.smallOffice.maxPlayableTiles,
          'modernOffice': OfficeLevel.modernOffice.maxPlayableTiles,
          'techHub': OfficeLevel.techHub.maxPlayableTiles,
          'campus': OfficeLevel.campus.maxPlayableTiles,
        };

        var prev = 0;
        for (final count in tiles.values) {
          expect(count, greaterThan(prev));
          prev = count;
        }
      });
    });

    group('Grid boundary calculations', () {
      test('grid always has 1-tile wall border on all sides', () {
        // The effective grid includes borders; playable is inner area
        final garage = OfficeLevel.garage;
        final totalCols = garage.effectiveCols(0);
        final totalRows = garage.effectiveRows(0);
        final playableCols = totalCols - 2;
        final playableRows = totalRows - 2;

        expect(playableCols * playableRows, garage.playableTiles(0));
      });

      test('grid dimensions after rotation', () {
        // This tests that the expansion system is consistent
        final garage = OfficeLevel.garage;
        final cols0 = garage.effectiveCols(0);
        final rows0 = garage.effectiveRows(0);

        final expanded = garage.expansions[0]; // First expansion
        if (expanded.deltaCols > 0) {
          expect(garage.effectiveCols(1), cols0 + expanded.deltaCols);
        }
        if (expanded.deltaRows > 0) {
          expect(garage.effectiveRows(1), rows0 + expanded.deltaRows);
        }
      });
    });

    group('Upgrade costs', () {
      test('garage upgrade is free (base cost)', () {
        expect(OfficeLevel.garage.upgradeCost, 0);
      });

      test('upgrade costs scale exponentially', () {
        final upgradeCosts = [
          OfficeLevel.garage.upgradeCost,
          OfficeLevel.smallOffice.upgradeCost,
          OfficeLevel.modernOffice.upgradeCost,
          OfficeLevel.techHub.upgradeCost,
          OfficeLevel.campus.upgradeCost,
        ];

        // Each is much more expensive than the previous
        for (var i = 1; i < upgradeCosts.length; i++) {
          if (upgradeCosts[i - 1] > 0) {
            expect(upgradeCosts[i] / upgradeCosts[i - 1], greaterThan(5));
          }
        }
      });
    });

    group('Edge cases and clamping', () {
      test('effectiveCols clamps negative expansion count', () {
        final garage = OfficeLevel.garage;
        expect(garage.effectiveCols(-999), garage.baseCols);
        expect(garage.effectiveRows(-1), garage.baseRows);
      });

      test('effectiveCols clamps beyond max', () {
        final garage = OfficeLevel.garage;
        final maxSteps = garage.expansions.length;
        final max = garage.effectiveCols(maxSteps);
        expect(garage.effectiveCols(maxSteps + 1), max);
        expect(garage.effectiveCols(999), max);
      });

      test('playableTiles is always positive', () {
        for (final tier in OfficeLevel.values) {
          expect(tier.basePlayableTiles, greaterThan(0));
          expect(tier.maxPlayableTiles, greaterThan(0));
        }
      });
    });

    group('Integration: GameState uses expansion correctly', () {
      test('GameState expansion clamping works via fromJson', () {
        final json = {
          'schemaVersion': 6,
          'grymni': 500,
          'officeLevel': 0, // Garage
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
        expect(state.officeExpansions, lessThanOrEqualTo(5));
      });

      test('GameState tier progression grows capacity', () {
        var state = GameState(officeLevel: OfficeLevel.garage);
        final garageMax = state.officeLevel.maxAgents;
        expect(garageMax, 3);

        state = state.copyWith(officeLevel: OfficeLevel.smallOffice);
        expect(state.officeLevel.maxAgents, 6);
        expect(state.officeLevel.maxAgents, greaterThan(garageMax));
      });

      test('playable tiles grow with expansions', () {
        var state = GameState(
          officeLevel: OfficeLevel.garage,
          officeExpansions: 0,
        );
        final before = state.playableTiles;

        state = state.copyWith(officeExpansions: 5);
        final after = state.playableTiles;

        expect(after, greaterThan(before));
      });
    });
  });
}
