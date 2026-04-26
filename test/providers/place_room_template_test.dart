import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

Future<ProviderContainer> _makeContainer({int grymni = 100000}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  // Top up the wallet so we can afford every template in the catalog.
  container.read(gameEconomyProvider.notifier).addGrymni(grymni);
  return container;
}

void main() {
  group('placeRoomTemplate', () {
    test('places room + every furniture slot atomically', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      final tpl = roomTemplateCatalog.first;

      final balanceBefore = c.read(gameEconomyProvider).grymni;
      final cost = notifier.templateCost(tpl);
      notifier.placeRoomTemplate(tpl, 0, 0);

      final state = c.read(gameEconomyProvider);
      expect(state.placedRooms.length, 1);
      expect(state.placedRooms.first.type, tpl.baseRoom);
      expect(state.placedRooms.first.col, 0);
      expect(state.placedRooms.first.row, 0);

      // Furniture: every slot from the template should now be placed at the
      // expected absolute (col, row).
      for (final slot in tpl.furniture) {
        final hit = state.placedFurniture.any((p) =>
            p.itemId == slot.furnitureId &&
            p.col == slot.colOffset &&
            p.row == slot.rowOffset);
        expect(hit, isTrue, reason: 'missing furniture ${slot.furnitureId}');
        expect(state.ownedFurniture.contains(slot.furnitureId), isTrue);
      }

      expect(state.grymni, balanceBefore - cost);
      expect(state.totalSpent, cost);
    });

    test('does nothing when player can\'t afford the bundle', () async {
      // Only seed a tiny balance — every template costs more than this.
      final c = await _makeContainer(grymni: 0);
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      final tpl = roomTemplateCatalog.first;

      final balanceBefore = c.read(gameEconomyProvider).grymni;
      notifier.placeRoomTemplate(tpl, 0, 0);

      final state = c.read(gameEconomyProvider);
      expect(state.placedRooms, isEmpty);
      expect(state.placedFurniture.where(
              (p) => tpl.furniture.any((s) => s.furnitureId == p.itemId)),
          isEmpty);
      expect(state.grymni, balanceBefore);
    });

    test('respects baseRoom maxPerOffice cap', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      // Pick a template whose base room has a low cap, then fill it up first.
      final tpl = roomTemplateCatalog.firstWhere(
          (t) => t.baseRoom.maxPerOffice == 1,
          orElse: () => roomTemplateCatalog
              .reduce((a, b) =>
                  a.baseRoom.maxPerOffice < b.baseRoom.maxPerOffice ? a : b));
      // Saturate the cap with plain rooms.
      for (var i = 0; i < tpl.baseRoom.maxPerOffice; i++) {
        notifier.placeRoom(tpl.baseRoom, i * 4, 0);
      }
      expect(notifier.canPlaceRoomTemplate(tpl), isFalse);
      final balanceBefore = c.read(gameEconomyProvider).grymni;
      notifier.placeRoomTemplate(tpl, 10, 10);
      expect(c.read(gameEconomyProvider).grymni, balanceBefore);
    });

    test('templateCost matches RoomTemplate.bundleCost', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      for (final tpl in roomTemplateCatalog) {
        expect(notifier.templateCost(tpl), tpl.bundleCost(furnitureCatalog));
      }
    });
  });
}
