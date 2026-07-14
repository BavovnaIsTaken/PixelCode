import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

void main() {
  group('GameState.inventoryOrder serialization', () {
    test('round-trips through toJson/fromJson, preserving empty-slot gaps', () {
      const state = GameState(inventoryOrder: ['desk_workstation', '', 'stool']);
      final back = GameState.fromJson(state.toJson());
      expect(back.inventoryOrder, ['desk_workstation', '', 'stool']);
    });

    test('empty order is omitted from JSON (backward compatible)', () {
      const state = GameState();
      expect(state.toJson().containsKey('inventoryOrder'), isFalse);
    });

    test('missing key decodes to an empty list', () {
      // A pre-inventory save has no inventoryOrder key.
      final json = const GameState().toJson()..remove('inventoryOrder');
      expect(GameState.fromJson(json).inventoryOrder, isEmpty);
    });
  });

  group('GameEconomyNotifier.setInventoryOrder', () {
    test('persists the slot order onto state', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(gameEconomyProvider).inventoryOrder, isEmpty);

      container
          .read(gameEconomyProvider.notifier)
          .setInventoryOrder(['coffee_table_basic', '', 'old_desk']);

      expect(
        container.read(gameEconomyProvider).inventoryOrder,
        ['coffee_table_basic', '', 'old_desk'],
      );
    });
  });
}
