import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

Future<ProviderContainer> _container({int grymni = 100000}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  container.read(gameEconomyProvider.notifier).addGrymni(grymni);
  return container;
}

void main() {
  group('placeRoom + expansion (Stage 3b)', () {
    test('placeRoom with zero expansionStepsToBuy behaves as before', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      final before = c.read(gameEconomyProvider);

      notifier.placeRoom(RoomType.workstation, 1, 1);

      final after = c.read(gameEconomyProvider);
      expect(after.placedRooms.length, 1);
      expect(after.officeExpansions, before.officeExpansions);
      expect(after.grymni, before.grymni - RoomType.workstation.cost);
    });

    test('placeRoom with expansionStepsToBuy=1 charges combined cost and grows grid',
        () async {
      final c = await _container();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      final before = c.read(gameEconomyProvider);
      final expansionCost = before.officeLevel.expansions[0].cost;

      notifier.placeRoom(
        RoomType.workstation,
        1,
        1,
        expansionStepsToBuy: 1,
      );

      final after = c.read(gameEconomyProvider);
      expect(after.officeExpansions, before.officeExpansions + 1);
      expect(after.placedRooms.length, 1);
      expect(after.grymni,
          before.grymni - RoomType.workstation.cost - expansionCost);
    });

    test('multi-step expansion is purchased in one transaction', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      final before = c.read(gameEconomyProvider);
      final cost = before.officeLevel.expansions[0].cost +
          before.officeLevel.expansions[1].cost;

      notifier.placeRoom(
        RoomType.workstation,
        1,
        1,
        expansionStepsToBuy: 2,
      );

      final after = c.read(gameEconomyProvider);
      expect(after.officeExpansions, before.officeExpansions + 2);
      expect(after.grymni,
          before.grymni - RoomType.workstation.cost - cost);
    });

    test('asking for more steps than tier allows is a no-op', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      final before = c.read(gameEconomyProvider);
      final maxSteps = before.officeLevel.expansions.length;

      notifier.placeRoom(
        RoomType.workstation,
        1,
        1,
        expansionStepsToBuy: maxSteps + 1,
      );

      final after = c.read(gameEconomyProvider);
      // No room placed, no money spent, no expansion bought.
      expect(after.placedRooms, isEmpty);
      expect(after.officeExpansions, before.officeExpansions);
      expect(after.grymni, before.grymni);
    });

    test('combined cost beyond wallet is a no-op', () async {
      // Default state has ₲500 + we top up by 0 here. workstation = ₲400.
      // Multi-step expansion at garage tier sums to far more than ₲100 left
      // after a workstation purchase, so combined cost > wallet.
      final c = await _container(grymni: 0);
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      final before = c.read(gameEconomyProvider);
      // garage expansions: 80 + 140 + 200 + 280 + 380 = 1080
      // Combined with workstation (400) = 1480 > default 500.
      notifier.placeRoom(
        RoomType.workstation,
        1,
        1,
        expansionStepsToBuy: before.officeLevel.expansions.length,
      );

      final after = c.read(gameEconomyProvider);
      expect(after.placedRooms, isEmpty);
      expect(after.officeExpansions, before.officeExpansions);
      expect(after.grymni, before.grymni);
    });

    test('placeRoomTemplate also supports expansionStepsToBuy', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      final tpl = roomTemplateCatalog.first;
      final before = c.read(gameEconomyProvider);
      final bundleCost = notifier.templateCost(tpl);
      final expansionCost = before.officeLevel.expansions[0].cost;

      notifier.placeRoomTemplate(
        tpl,
        1,
        1,
        expansionStepsToBuy: 1,
      );

      final after = c.read(gameEconomyProvider);
      expect(after.officeExpansions, before.officeExpansions + 1);
      expect(after.placedRooms.length, 1);
      expect(after.grymni, before.grymni - bundleCost - expansionCost);
    });
  });

  group('toggleDoor (Stage 3b)', () {
    test('toggling a border tile flips it between open and sealed', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);

      notifier.placeRoom(RoomType.workstation, 5, 5);
      final roomId = c.read(gameEconomyProvider).placedRooms.first.id;

      // Workstation 2×2 at (5,5): border tile at (5,5) is top-left interior.
      notifier.toggleDoor(roomId, 5, 5);
      expect(
          c.read(gameEconomyProvider).placedRooms.first.closedDoors,
          {(col: 5, row: 5)});

      notifier.toggleDoor(roomId, 5, 5);
      expect(
          c.read(gameEconomyProvider).placedRooms.first.closedDoors,
          isEmpty);
    });

    test('tile outside the room footprint is ignored', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);

      notifier.placeRoom(RoomType.workstation, 5, 5);
      final roomId = c.read(gameEconomyProvider).placedRooms.first.id;

      notifier.toggleDoor(roomId, 100, 100);
      expect(
          c.read(gameEconomyProvider).placedRooms.first.closedDoors,
          isEmpty);
    });

    test('interior (non-border) tile is ignored', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);

      // openSpace is 4×3 — has a genuine interior tile at (col+1, row+1).
      notifier.placeRoom(RoomType.openSpace, 5, 5);
      final roomId = c.read(gameEconomyProvider).placedRooms.first.id;
      // (6, 6) is strictly inside (not on the border ring).
      notifier.toggleDoor(roomId, 6, 6);
      expect(
          c.read(gameEconomyProvider).placedRooms.first.closedDoors,
          isEmpty);
    });

    test('unknown roomId is a no-op', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      notifier.placeRoom(RoomType.workstation, 5, 5);

      notifier.toggleDoor('does_not_exist', 5, 5);
      expect(
          c.read(gameEconomyProvider).placedRooms.first.closedDoors,
          isEmpty);
    });
  });
}
