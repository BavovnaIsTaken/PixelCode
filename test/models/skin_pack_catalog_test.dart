import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';

void main() {
  group('wallSkinPackCatalog', () {
    test('ships at least 4 packs', () {
      expect(wallSkinPackCatalog.length, greaterThanOrEqualTo(4));
    });

    test('ids are unique', () {
      final ids = wallSkinPackCatalog.map((p) => p.id).toSet();
      expect(ids.length, wallSkinPackCatalog.length);
    });

    test('exactly one free pack exists', () {
      final free = wallSkinPackCatalog.where((p) => p.cost == 0).toList();
      expect(free.length, 1);
      expect(free.first.id, kWallSkinFreeId);
    });

    test('wallSkinPackById finds known and rejects unknown', () {
      final first = wallSkinPackCatalog.first;
      expect(wallSkinPackById(first.id), same(first));
      expect(wallSkinPackById('does_not_exist'), isNull);
    });
  });

  group('floorSkinPackCatalog', () {
    test('ships at least 4 packs', () {
      expect(floorSkinPackCatalog.length, greaterThanOrEqualTo(4));
    });

    test('ids are unique', () {
      final ids = floorSkinPackCatalog.map((p) => p.id).toSet();
      expect(ids.length, floorSkinPackCatalog.length);
    });

    test('exactly one free pack exists', () {
      final free = floorSkinPackCatalog.where((p) => p.cost == 0).toList();
      expect(free.length, 1);
      expect(free.first.id, kFloorSkinFreeId);
    });

    test('floorSkinPackById finds known and rejects unknown', () {
      final first = floorSkinPackCatalog.first;
      expect(floorSkinPackById(first.id), same(first));
      expect(floorSkinPackById('does_not_exist'), isNull);
    });
  });
}
