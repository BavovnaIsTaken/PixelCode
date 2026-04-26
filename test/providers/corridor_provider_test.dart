import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

Future<ProviderContainer> _makeContainer({int grymni = 50000}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  container.read(gameEconomyProvider.notifier).addGrymni(grymni);
  return container;
}

List<({int col, int row})> _tiles(int count) =>
    List.generate(count, (i) => (col: i, row: 0));

void main() {
  group('corridorCostPerTile', () {
    test('narrow costs 50', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      expect(c.read(gameEconomyProvider.notifier).corridorCostPerTile(), 50);
    });

    test('wide costs 90', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      expect(
          c.read(gameEconomyProvider.notifier).corridorCostPerTile(wide: true),
          90);
    });
  });

  group('corridorCost', () {
    test('narrow: tiles × 50', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      expect(c.read(gameEconomyProvider.notifier).corridorCost(_tiles(4)), 200);
    });

    test('wide: tiles × 90', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      expect(
          c.read(gameEconomyProvider.notifier).corridorCost(_tiles(3),
              wide: true),
          270);
    });

    test('empty tiles → 0', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      expect(c.read(gameEconomyProvider.notifier).corridorCost([]), 0);
    });
  });

  group('canPlaceCorridor', () {
    test('returns true when balance covers cost', () async {
      // Initial state has 500 ₲; 4 narrow tiles = 200 ₲ — affordable.
      final c = await _makeContainer(grymni: 0);
      addTearDown(c.dispose);
      expect(
          c.read(gameEconomyProvider.notifier).canPlaceCorridor(_tiles(4)),
          isTrue);
    });

    test('returns false when cost exceeds balance', () async {
      // Initial 500 ₲; 11 narrow tiles = 550 ₲ — not affordable.
      final c = await _makeContainer(grymni: 0);
      addTearDown(c.dispose);
      expect(
          c.read(gameEconomyProvider.notifier).canPlaceCorridor(_tiles(11)),
          isFalse);
    });

    test('returns false for empty tile list', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      expect(
          c.read(gameEconomyProvider.notifier).canPlaceCorridor([]),
          isFalse);
    });
  });

  group('placeCorridor — narrow', () {
    test('deducts cost and appends corridor', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);
      final tiles = _tiles(4); // 4 × 50 = 200 ₲
      final before = c.read(gameEconomyProvider).grymni;

      n.placeCorridor(tiles);

      final state = c.read(gameEconomyProvider);
      expect(state.grymni, before - 200);
      expect(state.totalSpent, 200);
      expect(state.placedCorridors.length, 1);
      expect(state.placedCorridors.first.wide, isFalse);
      expect(state.placedCorridors.first.tiles.length, 4);
    });

    test('does nothing when cost exceeds balance', () async {
      // Initial 500 ₲; 11 narrow tiles = 550 ₲.
      final c = await _makeContainer(grymni: 0);
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);

      n.placeCorridor(_tiles(11));

      expect(c.read(gameEconomyProvider).placedCorridors, isEmpty);
    });
  });

  group('placeCorridor — wide', () {
    test('deducts 90×tiles and sets wide=true', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);
      final tiles = _tiles(3); // 3 × 90 = 270 ₲
      final before = c.read(gameEconomyProvider).grymni;

      n.placeCorridor(tiles, wide: true);

      final state = c.read(gameEconomyProvider);
      expect(state.grymni, before - 270);
      expect(state.placedCorridors.first.wide, isTrue);
    });

    test('does nothing when wide cost exceeds balance', () async {
      // Initial 500 ₲; 6 wide tiles = 540 ₲.
      final c = await _makeContainer(grymni: 0);
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);

      n.placeCorridor(_tiles(6), wide: true);

      expect(c.read(gameEconomyProvider).placedCorridors, isEmpty);
    });
  });

  group('multiple corridors', () {
    test('each placement appends a new corridor', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);

      n.placeCorridor(_tiles(2));
      n.placeCorridor(_tiles(3), wide: true);

      final state = c.read(gameEconomyProvider);
      expect(state.placedCorridors.length, 2);
      expect(state.placedCorridors[0].wide, isFalse);
      expect(state.placedCorridors[1].wide, isTrue);
    });

    test('each corridor gets a unique id', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final n = c.read(gameEconomyProvider.notifier);

      n.placeCorridor(_tiles(1));
      n.placeCorridor(_tiles(1));

      final ids =
          c.read(gameEconomyProvider).placedCorridors.map((cor) => cor.id);
      expect(ids.toSet().length, 2);
    });
  });
}
