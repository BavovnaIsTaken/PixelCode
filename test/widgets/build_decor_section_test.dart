import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/game_economy.dart';
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

  testWidgets('toggles edit mode via the action row', (tester) async {
    final container = await _makeContainer();
    await _pumpDecor(tester, container);
    await tester.pump();

    expect(container.read(furnitureEditModeProvider), isFalse);
    await tester.tap(find.text('Розмістити меблі'));
    await tester.pump();
    expect(container.read(furnitureEditModeProvider), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
