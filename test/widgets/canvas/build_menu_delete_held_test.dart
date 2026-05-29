/// Regression coverage for the explicit "delete held furniture" button in
/// the build menu. The button replaces the long-press-on-canvas affordance
/// that caused furniture to vanish on borderline clicks. These tests pin:
///   1. Empty hand → button is NOT rendered (the surface stays inert).
///   2. Held furniture → button renders and removes that exact item when
///      pressed, then clears the hold.
///   3. Stale held index (item gone underneath us) → pressing the button
///      releases the hold gracefully without crashing or corrupting the
///      placement list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/providers/build_mode_provider.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/providers/shop_navigation_provider.dart';
import 'package:pixelcode/widgets/canvas/build_menu.dart';

Future<ProviderContainer> _makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

Future<void> _pumpBuildMenu(
    WidgetTester tester, ProviderContainer container) async {
  await tester.binding.setSurfaceSize(const Size(1024, 600));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, child: BuildMenu())),
    ),
  ));
  await tester.pump();
}

/// Places one coffee table into the office economy and returns the index
/// of the freshly-placed item. The default office may already contain
/// canonical furniture (sample tables, plants), so we capture the length
/// pre- and post-place rather than asserting a clean slate.
int _placeOneTable(ProviderContainer c) {
  final notifier = c.read(gameEconomyProvider.notifier);
  notifier.purchaseFurniture('coffee_table_basic');
  final before = c.read(gameEconomyProvider).placedFurniture.length;
  notifier.placeFurniture('coffee_table_basic', 4, 4);
  final after = c.read(gameEconomyProvider).placedFurniture.length;
  expect(after, before + 1, reason: 'placement should append one item');
  return after - 1;
}

void main() {
  testWidgets('delete button is hidden when nothing is held',
      (tester) async {
    final container = await _makeContainer();
    container.read(buildModeProvider.notifier).enter();
    FurnitureEditModeCoordContainer.enterEmpty(container);

    await _pumpBuildMenu(tester, container);

    expect(find.byTooltip('Видалити вибране'), findsNothing,
        reason: 'edit mode with empty hand exposes no destructive action — '
            'the player has to pick something up first');

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('delete button is hidden when edit mode is OFF even if held '
      'state somehow lingers', (tester) async {
    final container = await _makeContainer();
    container.read(buildModeProvider.notifier).enter();
    // Drive the held provider directly to simulate a stale state. In
    // production FurnitureEditModeCoord enforces the invariant, but the
    // button must still not render outside edit mode.
    container.read(heldPlacedFurnitureIndexProvider.notifier).state = 0;

    await _pumpBuildMenu(tester, container);

    expect(find.byTooltip('Видалити вибране'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('held furniture → delete button appears, press removes that '
      'item and clears the hold', (tester) async {
    final container = await _makeContainer();
    container.read(buildModeProvider.notifier).enter();
    final idx = _placeOneTable(container);
    final beforeCount =
        container.read(gameEconomyProvider).placedFurniture.length;
    FurnitureEditModeCoordContainer.enterMove(container, idx);

    await _pumpBuildMenu(tester, container);

    expect(find.byTooltip('Видалити вибране'), findsOneWidget,
        reason: 'held state surfaces the explicit delete affordance');

    await tester.tap(find.byTooltip('Видалити вибране'));
    await tester.pump();

    expect(
        container.read(gameEconomyProvider).placedFurniture, hasLength(beforeCount - 1),
        reason: 'pressing delete removes exactly the held item');
    expect(container.read(heldPlacedFurnitureIndexProvider), isNull,
        reason: 'hold clears so the player exits the move flow cleanly');
    // Edit mode itself stays on — the player may want to pick a different
    // action next; only the explicit pencil-off / X exits edit mode.
    expect(container.read(furnitureEditModeProvider), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('stale held index → button press releases the hold safely '
      'without crashing or mutating placement list',
      (tester) async {
    final container = await _makeContainer();
    container.read(buildModeProvider.notifier).enter();
    _placeOneTable(container);
    // Held points past the end of the placement list — simulates the
    // race where another path removed the item underneath us.
    FurnitureEditModeCoordContainer.enterMove(container, 99);

    await _pumpBuildMenu(tester, container);

    final beforeCount =
        container.read(gameEconomyProvider).placedFurniture.length;

    expect(find.byTooltip('Видалити вибране'), findsOneWidget);
    await tester.tap(find.byTooltip('Видалити вибране'));
    await tester.pump();

    // Real placement list is untouched — the button's bounds check refuses
    // to call removePlacedFurniture for a stale index.
    expect(container.read(gameEconomyProvider).placedFurniture,
        hasLength(beforeCount));
    expect(container.read(heldPlacedFurnitureIndexProvider), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('selected inventory item (placement flow) does NOT surface the '
      'delete button — delete is only for held placed items',
      (tester) async {
    final container = await _makeContainer();
    container.read(buildModeProvider.notifier).enter();
    container
        .read(gameEconomyProvider.notifier)
        .purchaseFurniture('coffee_table_basic');
    FurnitureEditModeCoordContainer.enterPlacement(
        container, 'coffee_table_basic');

    await _pumpBuildMenu(tester, container);

    expect(find.byTooltip('Видалити вибране'), findsNothing,
        reason: 'selected = placement flow (no placed item to delete yet); '
            'the delete affordance must only appear for the move flow');

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
