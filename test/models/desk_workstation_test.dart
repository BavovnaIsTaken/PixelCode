import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/widgets/canvas/furniture_sprites.dart';

Future<ProviderContainer> _makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

void main() {
  group('desk_workstation (the default agent desk, now buyable)', () {
    test('exists in the catalog under the new desk type, with a real cost', () {
      final item = furnitureById('desk_workstation');
      expect(item, isNotNull);
      expect(item!.type, FurnitureType.desk);
      expect(item.cost, greaterThan(0),
          reason: 'it is a purchasable item, not a free starter');
    });

    test('the shabby starter desk is also categorised as a desk', () {
      // old_desk was historically filed under coffeeTable; it is a desk and
      // now lives in the dedicated "Робочі столи" category alongside the
      // buyable workstation desk.
      expect(furnitureById('old_desk')!.type, FurnitureType.desk);
    });

    test('has an 8×10 shop/inventory sprite', () {
      final sprite = furnitureSpriteMap['desk_workstation'];
      expect(sprite, isNotNull,
          reason: 'without a sprite the shop falls back to the category emoji');
      expect(sprite!.length, 10);
      expect(sprite.every((row) => row.length == 8), isTrue,
          reason: 'all furniture sprites are 8 columns wide');
    });

    test('can be purchased into inventory', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gameEconomyProvider.notifier);

      final before = container
              .read(gameEconomyProvider)
              .furnitureInventory['desk_workstation'] ??
          0;
      expect(notifier.canPurchaseFurniture('desk_workstation'), isTrue,
          reason: 'a fresh save has enough grymni for a 250₲ desk');

      notifier.purchaseFurniture('desk_workstation');

      final after = container
              .read(gameEconomyProvider)
              .furnitureInventory['desk_workstation'] ??
          0;
      expect(after, before + 1);
    });
  });
}
