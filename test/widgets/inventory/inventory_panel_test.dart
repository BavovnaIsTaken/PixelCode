import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/build_mode_provider.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/providers/shop_navigation_provider.dart';
import 'package:pixelcode/widgets/inventory/inventory_panel.dart';

Future<ProviderContainer> _makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) =>
    tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: InventoryPanel())),
    ));

Future<void> _teardown(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
}

void main() {
  group('InventoryPanel (item grid)', () {
    testWidgets('renders owned furniture cells, not settings cosmetics/themes',
        (tester) async {
      final container = await _makeContainer();
      container
          .read(gameEconomyProvider.notifier)
          .purchaseFurniture('coffee_table_basic');

      await _pump(tester, container);
      await tester.pump();

      // Owned furniture shows as a cell (tooltip = item name).
      final owned =
          furnitureCatalog.firstWhere((f) => f.id == 'coffee_table_basic');
      expect(find.byTooltip(owned.name), findsOneWidget);

      // The settings-style sections from the old inventory are gone.
      expect(find.text('Команда'), findsNothing);
      expect(find.text('Косметика'), findsNothing);
      expect(find.text('Теми'), findsNothing);

      await _teardown(tester, container);
    });

    testWidgets('shows owned wall/floor skin packs as cells', (tester) async {
      final container = await _makeContainer();
      await _pump(tester, container);
      await tester.pump();

      // The free "classic" wall + floor packs are owned by default; each pack
      // cell carries a category tag (🧱 wall / 🟫 floor).
      expect(wallSkinPackCatalog.any((p) => p.cost == 0), isTrue);
      expect(floorSkinPackCatalog.any((p) => p.cost == 0), isTrue);
      expect(find.text('🧱'), findsWidgets);
      expect(find.text('🟫'), findsWidgets);

      await _teardown(tester, container);
    });

    testWidgets('tapping a furniture cell hands it to the canvas',
        (tester) async {
      final container = await _makeContainer();
      container
          .read(gameEconomyProvider.notifier)
          .purchaseFurniture('coffee_table_basic');

      await _pump(tester, container);
      await tester.pump();

      expect(container.read(selectedFurnitureIdProvider), isNull);
      expect(container.read(buildModeProvider).active, isFalse);
      expect(container.read(officeDeepLinkProvider), isNull);

      final owned =
          furnitureCatalog.firstWhere((f) => f.id == 'coffee_table_basic');
      await tester.tap(find.byTooltip(owned.name));
      await tester.pump();

      expect(container.read(selectedFurnitureIdProvider), 'coffee_table_basic');
      expect(container.read(furnitureEditModeProvider), isTrue);
      expect(container.read(buildModeProvider).active, isTrue);
      expect(container.read(officeDeepLinkProvider), isNotNull);

      await _teardown(tester, container);
    });

    testWidgets('"Сортувати" persists a slot order', (tester) async {
      final container = await _makeContainer();
      container
          .read(gameEconomyProvider.notifier)
          .purchaseFurniture('coffee_table_basic');

      await _pump(tester, container);
      await tester.pump();

      expect(container.read(gameEconomyProvider).inventoryOrder, isEmpty);

      await tester.tap(find.text('Сортувати'));
      await tester.pump();

      final order = container.read(gameEconomyProvider).inventoryOrder;
      expect(order, isNotEmpty);
      expect(order, contains('coffee_table_basic'));
      // Sorted order groups by catalog (furniture before skin packs).
      expect(order.indexOf('coffee_table_basic'),
          lessThan(order.indexOf('classic_wall')));

      await _teardown(tester, container);
    });
  });
}
