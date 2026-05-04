import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/providers/shop_navigation_provider.dart';

void main() {
  group('shop tab index constants', () {
    test('shopTabOffice is index 2 (Office tab)', () {
      expect(shopTabOffice, 2);
    });

    test('shopTabDonation is index 4 (after Furniture migration)', () {
      // Furniture tab moved to BuildMenu's Decor section in Stage 2; donation
      // shifted from 5 to 4. Pin the post-migration value.
      expect(shopTabDonation, 4);
    });
  });

  group('shopDeepLinkProvider', () {
    test('starts as null (no pending deep link)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(shopDeepLinkProvider), isNull);
    });

    test('can be set to a tab index and read back', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(shopDeepLinkProvider.notifier).state = shopTabOffice;
      expect(container.read(shopDeepLinkProvider), shopTabOffice);

      container.read(shopDeepLinkProvider.notifier).state = null;
      expect(container.read(shopDeepLinkProvider), isNull);
    });
  });

  group('selectedFurnitureIdProvider', () {
    test('starts as null (no furniture selected)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(selectedFurnitureIdProvider), isNull);
    });

    test('can be set to a furniture id and read back', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedFurnitureIdProvider.notifier).state = 'desk_basic';
      expect(container.read(selectedFurnitureIdProvider), 'desk_basic');
    });
  });

  group('furnitureEditModeProvider', () {
    test('false when no furniture is selected', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(furnitureEditModeProvider), isFalse);
    });

    test('true when a furniture id is selected', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedFurnitureIdProvider.notifier).state = 'plant_1';
      expect(container.read(furnitureEditModeProvider), isTrue);
    });

    test('toggles back to false when selection is cleared', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedFurnitureIdProvider.notifier).state = 'plant_1';
      expect(container.read(furnitureEditModeProvider), isTrue);

      container.read(selectedFurnitureIdProvider.notifier).state = null;
      expect(container.read(furnitureEditModeProvider), isFalse);
    });

    test('treats empty string as a valid selection (truthy id)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Implementation only checks `!= null`, so '' counts as selected.
      container.read(selectedFurnitureIdProvider.notifier).state = '';
      expect(container.read(furnitureEditModeProvider), isTrue);
    });
  });
}
