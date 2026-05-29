import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/providers/shop_navigation_provider.dart';
import 'package:pixelcode/widgets/canvas/build_decor_section.dart';

Future<ProviderContainer> _makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

Future<void> _pumpDecor(WidgetTester tester, ProviderContainer container) =>
    tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: BuildDecorSection())),
    ));

void main() {
  testWidgets('renders type chips for every FurnitureType', (tester) async {
    final container = await _makeContainer();
    await _pumpDecor(tester, container);
    await tester.pump();

    for (final type in FurnitureType.values) {
      expect(find.text(type.label), findsWidgets);
    }
    // Tear down within the test body to flush GameEconomyNotifier's periodic
    // timers before flutter_test's invariant check fires.
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('lists items only for the selected type', (tester) async {
    final container = await _makeContainer();
    await _pumpDecor(tester, container);
    await tester.pump();

    // Default type is coffeeTable. Tap snackTable chip and verify
    // the item list filters down.
    await tester.tap(find.text(FurnitureType.snackTable.label).first);
    await tester.pump();

    final snackOnly =
        furnitureCatalog.where((f) => f.type == FurnitureType.snackTable);
    expect(snackOnly, isNotEmpty, reason: 'fixture sanity');

    for (final item in snackOnly) {
      expect(find.text(item.name), findsOneWidget);
    }
    final coffeeFirst = furnitureCatalog
        .firstWhere((f) => f.type == FurnitureType.coffeeTable);
    expect(find.text(coffeeFirst.name), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets(
      'FurnitureEditModeCoord keeps editMode/selectedId/held invariants',
      (tester) async {
    final container = await _makeContainer();
    await _pumpDecor(tester, container);
    await tester.pump();

    expect(container.read(furnitureEditModeProvider), isFalse);

    // enterPlacement turns edit on and sets selected, clears held.
    FurnitureEditModeCoordContainer.enterPlacement(
        container, 'coffee_table_basic');
    expect(container.read(furnitureEditModeProvider), isTrue);
    expect(
        container.read(selectedFurnitureIdProvider), 'coffee_table_basic');
    expect(container.read(heldPlacedFurnitureIndexProvider), isNull);

    // enterMove swaps to held, clears selected, keeps edit on.
    FurnitureEditModeCoordContainer.enterMove(container, 3);
    expect(container.read(furnitureEditModeProvider), isTrue);
    expect(container.read(selectedFurnitureIdProvider), isNull);
    expect(container.read(heldPlacedFurnitureIndexProvider), 3);

    // releaseHold clears in-hand items but leaves edit mode on.
    FurnitureEditModeCoordContainer.releaseHold(container);
    expect(container.read(furnitureEditModeProvider), isTrue);
    expect(container.read(selectedFurnitureIdProvider), isNull);
    expect(container.read(heldPlacedFurnitureIndexProvider), isNull);

    // exit drops everything.
    FurnitureEditModeCoordContainer.exit(container);
    expect(container.read(furnitureEditModeProvider), isFalse);
    expect(container.read(selectedFurnitureIdProvider), isNull);
    expect(container.read(heldPlacedFurnitureIndexProvider), isNull);

    // enterEmpty (pencil button entry) flips edit on without any in-hand.
    FurnitureEditModeCoordContainer.enterEmpty(container);
    expect(container.read(furnitureEditModeProvider), isTrue);
    expect(container.read(selectedFurnitureIdProvider), isNull);
    expect(container.read(heldPlacedFurnitureIndexProvider), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('tapping Місце activates item and shows banner', (tester) async {
    final container = await _makeContainer();
    // Purchase one copy so the item has stock in inventory.
    container
        .read(gameEconomyProvider.notifier)
        .purchaseFurniture('coffee_table_basic');

    await _pumpDecor(tester, container);
    await tester.pump();

    expect(container.read(selectedFurnitureIdProvider), isNull);
    await tester.tap(find.text('Місце').first);
    await tester.pump();

    expect(container.read(selectedFurnitureIdProvider), 'coffee_table_basic');
    expect(container.read(furnitureEditModeProvider), isTrue);
    expect(find.textContaining('Тап на канвасі'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('tapping Скасувати releases the in-hand item but leaves edit mode on',
      (tester) async {
    final container = await _makeContainer();
    container
        .read(gameEconomyProvider.notifier)
        .purchaseFurniture('coffee_table_basic');
    FurnitureEditModeCoordContainer.enterPlacement(
        container, 'coffee_table_basic');

    await _pumpDecor(tester, container);
    await tester.pump();

    expect(container.read(furnitureEditModeProvider), isTrue);
    expect(container.read(selectedFurnitureIdProvider), 'coffee_table_basic');

    await tester.tap(find.text('Скасувати').first);
    await tester.pump();

    // Cancelling the in-flight pick drops the inventory hand …
    expect(container.read(selectedFurnitureIdProvider), isNull);
    // … but edit mode stays on so the player can pick a different item or
    // delete/move with empty hand. The pencil button is the explicit exit.
    expect(container.read(furnitureEditModeProvider), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
