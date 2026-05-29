import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/providers/shop_navigation_provider.dart';

void main() {
  group('shop tab index constants', () {
    test('shopTabOffice is index 2 (Office tab)', () {
      expect(shopTabOffice, 2);
    });

    test('shopTabStamp is index 4 (send-button stamps tab)', () {
      expect(shopTabStamp, 4);
    });

    test('shopTabDonation is index 5 (after Stamp tab insertion)', () {
      // Furniture tab moved to BuildMenu's Decor section in Stage 2; donation
      // shifted from 5 to 4 then back to 5 after Stamp tab was inserted at 4.
      // Pin the current value so a regression on the tab order is caught.
      expect(shopTabDonation, 5);
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

  group('heldPlacedFurnitureIndexProvider', () {
    test('starts as null (no item picked up)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(heldPlacedFurnitureIndexProvider), isNull);
    });

    test('can be set to an index and read back', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(heldPlacedFurnitureIndexProvider.notifier).state = 3;
      expect(container.read(heldPlacedFurnitureIndexProvider), 3);
    });
  });

  group('furnitureEditModeProvider — independent toggle', () {
    // Pre-Stage-2c: this provider was derived from `selectedFurnitureIdProvider
    // != null`, so it flipped only as a side effect of inventory pick. That
    // model collapsed when the pencil button needed to enter "manipulate
    // placed items" mode without forcing an inventory pick first. The
    // independent `StateProvider<bool>` below is the new contract; these
    // tests pin it so a future refactor can't silently re-introduce the
    // derived form (which broke the pencil toggle UX).
    test('starts as false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(furnitureEditModeProvider), isFalse);
    });

    test('can be toggled on independently of selected/held state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(furnitureEditModeProvider.notifier).state = true;
      expect(container.read(furnitureEditModeProvider), isTrue);
      expect(container.read(selectedFurnitureIdProvider), isNull,
          reason: 'toggling edit mode does NOT auto-select an inventory item');
      expect(container.read(heldPlacedFurnitureIndexProvider), isNull);
    });

    test('does NOT auto-derive from selectedFurnitureIdProvider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Setting selection alone leaves edit mode off — coord helpers are the
      // only path that turns edit mode on. This pins the regression that
      // previously made selection imply edit mode.
      container.read(selectedFurnitureIdProvider.notifier).state = 'plant_1';
      expect(container.read(furnitureEditModeProvider), isFalse,
          reason: 'edit mode must remain a separate, explicit signal — '
              'derived form caused the pencil-toggle bug');
    });

    test('does NOT auto-derive from heldPlacedFurnitureIndexProvider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(heldPlacedFurnitureIndexProvider.notifier).state = 0;
      expect(container.read(furnitureEditModeProvider), isFalse);
    });

    test('can be toggled off while a selection is set (edit-off wins)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedFurnitureIdProvider.notifier).state = 'plant_1';
      container.read(furnitureEditModeProvider.notifier).state = true;
      container.read(furnitureEditModeProvider.notifier).state = false;
      expect(container.read(furnitureEditModeProvider), isFalse);
      // The provider is independent — turning it off does not auto-clear
      // selection; that is the coord helper's job (exit() does both).
      expect(container.read(selectedFurnitureIdProvider), 'plant_1');
    });
  });

  group('FurnitureEditModeCoordContainer — coord helper invariants', () {
    test('enterPlacement → edit on, selected set, held cleared', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      FurnitureEditModeCoordContainer.enterPlacement(container, 'desk_basic');
      expect(container.read(furnitureEditModeProvider), isTrue);
      expect(container.read(selectedFurnitureIdProvider), 'desk_basic');
      expect(container.read(heldPlacedFurnitureIndexProvider), isNull);
    });

    test('enterPlacement after enterMove clears the held index', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      FurnitureEditModeCoordContainer.enterMove(container, 5);
      FurnitureEditModeCoordContainer.enterPlacement(container, 'plant_1');
      expect(container.read(heldPlacedFurnitureIndexProvider), isNull,
          reason: 'switching to placement must drop any prior move-pickup '
              'so we never have two items "in hand" at once');
      expect(container.read(selectedFurnitureIdProvider), 'plant_1');
    });

    test('enterMove → edit on, held set, selected cleared', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      FurnitureEditModeCoordContainer.enterPlacement(container, 'desk_basic');
      FurnitureEditModeCoordContainer.enterMove(container, 3);
      expect(container.read(furnitureEditModeProvider), isTrue);
      expect(container.read(heldPlacedFurnitureIndexProvider), 3);
      expect(container.read(selectedFurnitureIdProvider), isNull);
    });

    test('enterEmpty → edit on, both hand-states cleared', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      FurnitureEditModeCoordContainer.enterPlacement(container, 'plant_1');
      FurnitureEditModeCoordContainer.enterEmpty(container);
      expect(container.read(furnitureEditModeProvider), isTrue);
      expect(container.read(selectedFurnitureIdProvider), isNull);
      expect(container.read(heldPlacedFurnitureIndexProvider), isNull);
    });

    test('exit → everything off', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      FurnitureEditModeCoordContainer.enterMove(container, 2);
      FurnitureEditModeCoordContainer.exit(container);
      expect(container.read(furnitureEditModeProvider), isFalse);
      expect(container.read(selectedFurnitureIdProvider), isNull);
      expect(container.read(heldPlacedFurnitureIndexProvider), isNull);
    });

    test('releaseHold → hands cleared but edit mode stays on', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      FurnitureEditModeCoordContainer.enterMove(container, 1);
      FurnitureEditModeCoordContainer.releaseHold(container);
      expect(container.read(furnitureEditModeProvider), isTrue,
          reason: 'releaseHold cancels the move but keeps the player in '
              'edit mode — that is the explicit pencil-toggle contract');
      expect(container.read(selectedFurnitureIdProvider), isNull);
      expect(container.read(heldPlacedFurnitureIndexProvider), isNull);
    });
  });
}
