import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

Future<ProviderContainer> _makeContainer({int grymni = 50000}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  container.read(gameEconomyProvider.notifier).addGrymni(grymni);
  return container;
}

void main() {
  group('purchaseWallSkinPack', () {
    test('adds pack to ownedWallSkinPacks and deducts cost', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);
      final pack = wallSkinPackCatalog.firstWhere((p) => p.cost > 0);

      final before = c.read(gameEconomyProvider).grymni;
      n.purchaseWallSkinPack(pack);

      final state = c.read(gameEconomyProvider);
      expect(state.ownedWallSkinPacks, contains(pack.id));
      expect(state.grymni, before - pack.cost);
      expect(state.totalSpent, pack.cost);
    });

    test('does nothing when already owned', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);
      final pack = wallSkinPackCatalog.firstWhere((p) => p.cost > 0);

      n.purchaseWallSkinPack(pack);
      final grymniAfterFirst = c.read(gameEconomyProvider).grymni;
      n.purchaseWallSkinPack(pack); // second call — no-op
      expect(c.read(gameEconomyProvider).grymni, grymniAfterFirst);
    });

    test('does nothing when balance is insufficient', () async {
      // Default GameState starts with 500 ₲ — pick a pack that costs more.
      final c = await _makeContainer(grymni: 0);
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);
      final pack = wallSkinPackCatalog.firstWhere((p) => p.cost > 500);

      n.purchaseWallSkinPack(pack);
      expect(c.read(gameEconomyProvider).ownedWallSkinPacks,
          isNot(contains(pack.id)));
    });
  });

  group('purchaseFloorSkinPack', () {
    test('adds pack to ownedFloorSkinPacks and deducts cost', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);
      final pack = floorSkinPackCatalog.firstWhere((p) => p.cost > 0);

      final before = c.read(gameEconomyProvider).grymni;
      n.purchaseFloorSkinPack(pack);

      final state = c.read(gameEconomyProvider);
      expect(state.ownedFloorSkinPacks, contains(pack.id));
      expect(state.grymni, before - pack.cost);
    });
  });

  group('applyRoomWallSkin', () {
    test('sets wallSkinId on the target room', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);
      final pack = wallSkinPackCatalog.firstWhere((p) => p.cost > 0);

      // Place a room first and purchase the pack.
      n.placeRoom(RoomType.workstation, 2, 2);
      final roomId = c.read(gameEconomyProvider).placedRooms.first.id;
      n.purchaseWallSkinPack(pack);

      n.applyRoomWallSkin(roomId, pack.id);
      final room = c
          .read(gameEconomyProvider)
          .placedRooms
          .firstWhere((r) => r.id == roomId);
      expect(room.wallSkinId, pack.id);
    });

    test('does not apply unowned paid pack', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);
      final pack = wallSkinPackCatalog.firstWhere((p) => p.cost > 0);

      n.placeRoom(RoomType.workstation, 2, 2);
      final roomId = c.read(gameEconomyProvider).placedRooms.first.id;
      // Do NOT purchase the pack — apply should be rejected.
      n.applyRoomWallSkin(roomId, pack.id);

      final room = c
          .read(gameEconomyProvider)
          .placedRooms
          .firstWhere((r) => r.id == roomId);
      expect(room.wallSkinId, isNull);
    });

    test('applying free skin clears the override', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);
      final paid = wallSkinPackCatalog.firstWhere((p) => p.cost > 0);

      n.placeRoom(RoomType.workstation, 2, 2);
      final roomId = c.read(gameEconomyProvider).placedRooms.first.id;
      n.purchaseWallSkinPack(paid);
      n.applyRoomWallSkin(roomId, paid.id);

      // Revert to free skin — wallSkinId should be null.
      n.applyRoomWallSkin(roomId, kWallSkinFreeId);
      final room = c
          .read(gameEconomyProvider)
          .placedRooms
          .firstWhere((r) => r.id == roomId);
      expect(room.wallSkinId, isNull);
    });
  });

  group('applyRoomFloorSkin', () {
    test('sets floorSkinId on the target room', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);
      final pack = floorSkinPackCatalog.firstWhere((p) => p.cost > 0);

      n.placeRoom(RoomType.workstation, 2, 2);
      final roomId = c.read(gameEconomyProvider).placedRooms.first.id;
      n.purchaseFloorSkinPack(pack);
      n.applyRoomFloorSkin(roomId, pack.id);

      final room = c
          .read(gameEconomyProvider)
          .placedRooms
          .firstWhere((r) => r.id == roomId);
      expect(room.floorSkinId, pack.id);
    });
  });
}
