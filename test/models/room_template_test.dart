import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';

void main() {
  group('roomTemplateCatalog sanity', () {
    test('every template references an existing furniture id', () {
      for (final tpl in roomTemplateCatalog) {
        for (final slot in tpl.furniture) {
          expect(furnitureById(slot.furnitureId), isNotNull,
              reason: 'template ${tpl.id} references unknown furniture '
                  '"${slot.furnitureId}"');
        }
      }
    });

    test('every furniture slot fits within the base room footprint', () {
      for (final tpl in roomTemplateCatalog) {
        final w = tpl.baseRoom.widthTiles;
        final h = tpl.baseRoom.heightTiles;
        for (final slot in tpl.furniture) {
          expect(slot.colOffset, inInclusiveRange(0, w - 1),
              reason: '${tpl.id}: slot ${slot.furnitureId} colOffset out of '
                  'range');
          expect(slot.rowOffset, inInclusiveRange(0, h - 1),
              reason: '${tpl.id}: slot ${slot.furnitureId} rowOffset out of '
                  'range');
        }
      }
    });

    test('template ids are unique', () {
      final ids = roomTemplateCatalog.map((t) => t.id).toSet();
      expect(ids.length, roomTemplateCatalog.length);
    });

    test('catalog ships at least 6 templates', () {
      expect(roomTemplateCatalog.length, greaterThanOrEqualTo(6));
    });

    test('new Stage 3a work-themed templates exist with a workstation/meetingRoom base', () {
      const expectedIds = ['tpl_starter_cube', 'tpl_deep_focus', 'tpl_team_hub'];
      for (final id in expectedIds) {
        final tpl = roomTemplateById(id);
        expect(tpl, isNotNull, reason: 'expected template $id to exist');
        expect(
            [RoomType.workstation, RoomType.meetingRoom].contains(tpl!.baseRoom),
            isTrue,
            reason: '$id should be a work-focused base (workstation or meetingRoom)');
        expect(tpl.furniture, isNotEmpty,
            reason: '$id should ship at least one piece of furniture');
      }
    });

    test('roomTemplateById finds known and rejects unknown', () {
      final first = roomTemplateCatalog.first;
      expect(roomTemplateById(first.id), same(first));
      expect(roomTemplateById('does_not_exist'), isNull);
    });
  });

  group('RoomTemplate pricing math', () {
    test('rawCost equals base + sum of furniture', () {
      final tpl = roomTemplateCatalog.first;
      var expected = tpl.baseRoom.cost;
      for (final slot in tpl.furniture) {
        expected += furnitureById(slot.furnitureId)!.cost;
      }
      expect(tpl.rawCost(furnitureCatalog), expected);
    });

    test('bundleCost applies the discount and is strictly less than raw '
        'when discount > 0', () {
      for (final tpl in roomTemplateCatalog) {
        final raw = tpl.rawCost(furnitureCatalog);
        final bundle = tpl.bundleCost(furnitureCatalog);
        if (tpl.discountPercent > 0 && raw > 0) {
          expect(bundle, lessThan(raw),
              reason: '${tpl.id}: bundle should be cheaper than raw');
        }
      }
    });
  });
}
