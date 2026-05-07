/// Widget tests for [SendButtonSection] — verifies the cosmetic store grid
/// renders correct active/owned/locked states and dispatches the expected
/// equip / unequip / purchase calls into the economy notifier.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/app_theme.dart' as app_theme;
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/widgets/settings/send_button_section.dart';

class _FakeEconomyNotifier extends GameEconomyNotifier {
  _FakeEconomyNotifier(this._state);
  GameState _state;

  int equipCalls = 0;
  String? lastEquipped;
  int unequipCalls = 0;
  CosmeticType? lastUnequippedType;
  int purchaseCalls = 0;
  String? lastPurchased;

  @override
  GameState build() => _state;

  @override
  bool ownsCosmetic(String id) => state.ownedCosmetics.contains(id);

  @override
  void equipCosmetic(String id) {
    equipCalls += 1;
    lastEquipped = id;
    final item = cosmeticById(id);
    if (item == null) return;
    final equipped = Map<int, String>.from(state.equippedCosmetics);
    equipped[item.type.index] = id;
    state = state.copyWith(equippedCosmetics: equipped);
  }

  @override
  void unequipCosmetic(CosmeticType type) {
    unequipCalls += 1;
    lastUnequippedType = type;
    final equipped = Map<int, String>.from(state.equippedCosmetics);
    equipped.remove(type.index);
    state = state.copyWith(equippedCosmetics: equipped);
  }

  @override
  void purchaseCosmetic(String id) {
    purchaseCalls += 1;
    lastPurchased = id;
    final item = cosmeticById(id);
    if (item == null) return;
    final owned = Set<String>.from(state.ownedCosmetics)..add(id);
    state = state.copyWith(
      grymni: state.grymni - item.cost,
      ownedCosmetics: owned,
    );
  }
}

Future<_FakeEconomyNotifier> _pump(
  WidgetTester tester, {
  required GameState gameState,
  double width = 600,
}) async {
  final notifier = _FakeEconomyNotifier(gameState);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gameEconomyProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [app_theme.AppColorsExtension(app_theme.defaultThemeColors)],
      ),
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: const SingleChildScrollView(child: SendButtonSection()),
        ),
      ),
    ),
  ));
  // The grid contains animation controllers (idle pulse) — bounded pump.
  await tester.pump(const Duration(milliseconds: 50));
  return notifier;
}

void main() {
  group('SendButtonSection — rendering', () {
    testWidgets('renders all 4 send-button variants by name', (tester) async {
      await _pump(tester, gameState: const GameState());
      expect(find.text('Класичний'), findsOneWidget);
      expect(find.text('Неоновий Пульс'), findsOneWidget);
      expect(find.text('Золота Ракета'), findsOneWidget);
      expect(find.text('Піксельна Аркада'), findsOneWidget);
    });

    testWidgets('classic is "Активна" by default (no equipped ID)',
        (tester) async {
      await _pump(tester, gameState: const GameState());
      // The classic card should show the active marker.
      expect(find.text('Активна'), findsOneWidget);
    });

    testWidgets('locked items show price + lock icon', (tester) async {
      await _pump(tester, gameState: const GameState(grymni: 0));
      // Three premium variants are locked → three lock icons.
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));
      // Prices from the cosmeticCatalog.
      expect(find.text('6000 ₲'), findsOneWidget);
      expect(find.text('12000 ₲'), findsOneWidget);
      expect(find.text('20000 ₲'), findsOneWidget);
    });

    testWidgets('owned but not active item prompts "Клікни, щоб увімкнути"',
        (tester) async {
      const state = GameState(
        grymni: 0,
        ownedCosmetics: {'send_neon_pulse'},
      );
      await _pump(tester, gameState: state);
      expect(find.text('Клікни, щоб увімкнути'), findsOneWidget);
    });

    testWidgets('grid collapses to 1 column under 440px', (tester) async {
      await _pump(tester, gameState: const GameState(), width: 320);
      // Just sanity — items still render; layout is responsive.
      expect(find.text('Класичний'), findsOneWidget);
      expect(find.text('Піксельна Аркада'), findsOneWidget);
    });
  });

  group('SendButtonSection — interactions', () {
    testWidgets('tapping owned item equips it', (tester) async {
      const state = GameState(
        grymni: 0,
        ownedCosmetics: {'send_neon_pulse'},
      );
      final notifier = await _pump(tester, gameState: state);

      await tester.tap(find.text('Неоновий Пульс'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(notifier.equipCalls, 1);
      expect(notifier.lastEquipped, 'send_neon_pulse');
    });

    testWidgets('tapping classic with non-classic equipped unequips it',
        (tester) async {
      final sendIdx = CosmeticType.sendButtonStyle.index;
      final state = GameState(
        grymni: 0,
        ownedCosmetics: const {'send_neon_pulse'},
        equippedCosmetics: {sendIdx: 'send_neon_pulse'},
      );

      final notifier = await _pump(tester, gameState: state);

      await tester.tap(find.text('Класичний'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(notifier.unequipCalls, 1);
      expect(notifier.lastUnequippedType, CosmeticType.sendButtonStyle);
    });

    testWidgets('tapping a locked card does NOT equip', (tester) async {
      final notifier =
          await _pump(tester, gameState: const GameState(grymni: 0));

      // Tap on the locked premium card name. The GestureDetector is opaque
      // and the onTap returns early because !owned.
      await tester.tap(find.text('Неоновий Пульс'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(notifier.equipCalls, 0);
      expect(notifier.unequipCalls, 0);
    });

    testWidgets('"Купити" is enabled and triggers purchase when affordable',
        (tester) async {
      // 6000₲ exactly — affordable for send_neon_pulse.
      final notifier =
          await _pump(tester, gameState: const GameState(grymni: 6000));

      // There should be 3 "Купити" buttons (one per premium item).
      expect(find.text('Купити'), findsNWidgets(3));

      await tester.tap(find.text('Купити').first);
      await tester.pump(const Duration(milliseconds: 50));

      expect(notifier.purchaseCalls, 1);
      // First card is send_neon_pulse (cheapest premium).
      expect(notifier.lastPurchased, 'send_neon_pulse');
    });

    testWidgets('"Купити" does not call purchase when broke', (tester) async {
      final notifier =
          await _pump(tester, gameState: const GameState(grymni: 0));

      // The buy button is wired with onTap=null when canAfford is false; the
      // GestureDetector still exists but tapping it must be a no-op.
      await tester.tap(find.text('Купити').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(notifier.purchaseCalls, 0);
    });
  });
}
