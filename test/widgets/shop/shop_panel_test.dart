/// Widget tests for `ShopPanel` — covers the tab-routing, balance header,
/// office tab, cosmetics tab, and donation tab. The hiring (Roster) tab has
/// dedicated coverage in `roster_tab_test.dart`; we deliberately don't
/// duplicate it here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/providers/shop_navigation_provider.dart';
import 'package:pixelcode/widgets/shop/shop_panel.dart';

import '../../helpers/fake_ws_service.dart';

Future<ProviderContainer> _makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    wsServiceProvider.overrideWith((_) => FakeAgentWsService()),
  ]);
}

Future<void> _pumpShopPanel(WidgetTester tester, ProviderContainer container) =>
    tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: ShopPanel())),
    ));

void main() {
  group('ShopPanel — tab bar', () {
    testWidgets('renders all five tab labels', (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      // Tab labels — Ukrainian strings from the panel.
      expect(find.text('Наймання'), findsOneWidget);
      expect(find.text('Навички'), findsOneWidget);
      expect(find.text('Офіс'), findsOneWidget);
      expect(find.text('Косметика'), findsOneWidget);
      expect(find.text('Донат'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('shopDeepLinkProvider switches the active tab', (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      // Hop to the Office tab via deep-link.
      container.read(shopDeepLinkProvider.notifier).state = shopTabOffice;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      // Office tab specific header.
      expect(find.text('Офіс'), findsWidgets);
      expect(find.text('Гараж'), findsWidgets);

      // Deep-link self-clears after consumption.
      expect(container.read(shopDeepLinkProvider), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('tapping a tab navigates to its content', (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      // Tap the Donation tab and verify donation-only content shows.
      await tester.tap(find.text('Донат'));
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Ринок гримень'), findsOneWidget);
      expect(find.text('Підтримай розвиток студії!'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });

  group('ShopPanel — balance header', () {
    testWidgets('renders compact balance with ₲ summary', (tester) async {
      final container = await _makeContainer();
      // Default initial state has 500₲, totalEarned 0.
      await _pumpShopPanel(tester, container);
      await tester.pump();

      // Default balance is 500.
      expect(find.text('500'), findsOneWidget);
      // Total-earned summary shows the ₲ glyph.
      expect(find.textContaining('Зароблено:'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('balance header reflects state changes (donation purchase)',
        (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      // Trigger a donation purchase (+100₲) and rebuild.
      container
          .read(gameEconomyProvider.notifier)
          .purchaseDonation(donationPackages.first);
      await tester.pump();

      // 500 + 100 = 600 — formatGrymni(600) === "600".
      expect(find.text('600'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });

  group('ShopPanel — Office tab', () {
    testWidgets('lists every OfficeLevel with localised label',
        (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      container.read(shopDeepLinkProvider.notifier).state = shopTabOffice;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      // Each OfficeLevel.label appears in the list.
      for (final level in OfficeLevel.values) {
        expect(find.text(level.label), findsWidgets,
            reason: '${level.label} should be visible on Office tab');
      }

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('shows "ЗАРАЗ" badge on the current tier', (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      container.read(shopDeepLinkProvider.notifier).state = shopTabOffice;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      // Current tier badge.
      expect(find.text('ЗАРАЗ'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('next-tier upgrade button is disabled when broke',
        (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      container.read(shopDeepLinkProvider.notifier).state = shopTabOffice;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      // smallOffice costs 1K — initial state has 500₲, so it's unaffordable.
      expect(find.text('1K₲'), findsOneWidget);

      // Tapping the disabled button should not change state.
      final grymniBefore = container.read(gameEconomyProvider).grymni;
      await tester.tap(find.text('1K₲'));
      await tester.pump();
      expect(container.read(gameEconomyProvider).grymni, grymniBefore);
      // Office tier unchanged.
      expect(container.read(gameEconomyProvider).officeLevel,
          OfficeLevel.garage);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('upgrades to smallOffice when affordable', (tester) async {
      final container = await _makeContainer();

      // Top up to 5000₲ before pumping.
      container.read(gameEconomyProvider.notifier).purchaseDonation(
            const DonationPackage(
                grymni: 5000, price: 'free', label: 'Test'),
          );

      await _pumpShopPanel(tester, container);
      await tester.pump();

      container.read(shopDeepLinkProvider.notifier).state = shopTabOffice;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      // Tap the upgrade button (next tier cost = 1K).
      await tester.tap(find.text('1K₲'));
      await tester.pump();

      expect(container.read(gameEconomyProvider).officeLevel,
          OfficeLevel.smallOffice);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });

  group('ShopPanel — Cosmetics tab', () {
    testWidgets('renders category chips for every CosmeticType',
        (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      // Tab index 3 = cosmetics.
      container.read(shopDeepLinkProvider.notifier).state = 3;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      for (final type in CosmeticType.values) {
        expect(find.text(type.label), findsWidgets,
            reason: '${type.label} chip should be visible');
      }

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('filters items by selected cosmetic type', (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      container.read(shopDeepLinkProvider.notifier).state = 3;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      // Default selection is nicknameDecor → "Зірки" should appear.
      expect(find.text('Зірки'), findsOneWidget);
      // Skin item should NOT appear under decor selection.
      expect(find.text('Кежуал'), findsNothing);

      // Switch to skins.
      await tester.tap(find.text('Скіни').last);
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Кежуал'), findsOneWidget);
      // The decor item should now be hidden.
      expect(find.text('Зірки'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('owned cosmetic shows "Одягнути" instead of price',
        (tester) async {
      final container = await _makeContainer();

      // Award the player decor_angles (cost 100) by direct purchase.
      container.read(gameEconomyProvider.notifier).purchaseDonation(
            const DonationPackage(grymni: 1000, price: 'x', label: 'x'),
          );
      container
          .read(gameEconomyProvider.notifier)
          .purchaseCosmetic('decor_angles');

      await _pumpShopPanel(tester, container);
      await tester.pump();

      container.read(shopDeepLinkProvider.notifier).state = 3;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      // Item is now owned → action button shows "Одягнути".
      expect(find.text('Одягнути'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('equipped cosmetic shows "ОДЯГНЕНО" badge and "Зняти" button',
        (tester) async {
      final container = await _makeContainer();

      container.read(gameEconomyProvider.notifier).purchaseDonation(
            const DonationPackage(grymni: 1000, price: 'x', label: 'x'),
          );
      container
          .read(gameEconomyProvider.notifier)
          .purchaseCosmetic('decor_angles');
      container
          .read(gameEconomyProvider.notifier)
          .equipCosmetic('decor_angles');

      await _pumpShopPanel(tester, container);
      await tester.pump();

      container.read(shopDeepLinkProvider.notifier).state = 3;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('ОДЯГНЕНО'), findsOneWidget);
      expect(find.text('Зняти'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('free unowned cosmetic (send_classic) shows "Безкоштовно" CTA',
        (tester) async {
      final container = await _makeContainer();
      // Tall viewport so every cosmetic card is laid out without lazy clipping.
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpShopPanel(tester, container);
      await tester.pump();

      container.read(shopDeepLinkProvider.notifier).state = 3;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      // send_classic (Класичний) is the only cost-0 cosmetic NOT seeded as
      // owned in `GameState.initial`, so its CTA still renders "Безкоштовно".
      await tester.tap(find.text('Кнопка «Надіслати»').last);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Класичний'), findsOneWidget);
      expect(find.text('Безкоштовно'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('seeded title_rookie shows "Одягнути" (auto-owned starter)',
        (tester) async {
      final container = await _makeContainer();
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpShopPanel(tester, container);
      await tester.pump();

      container.read(shopDeepLinkProvider.notifier).state = 3;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Титули').last);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      // title_rookie is seeded into ownedCosmetics → owned but not equipped.
      expect(find.text('Новачок'), findsWidgets);
      expect(find.text('Одягнути'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });

  group('ShopPanel — Donation tab', () {
    testWidgets('renders every donation package with label and price',
        (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      container.read(shopDeepLinkProvider.notifier).state = shopTabDonation;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      for (final pkg in donationPackages) {
        expect(find.text(pkg.label), findsOneWidget,
            reason: '${pkg.label} label should be visible');
        expect(find.text(pkg.price), findsOneWidget,
            reason: '${pkg.price} price should be visible');
      }

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('shows "НАЙКРАЩА ЦІНА" badge on the best-value pack',
        (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      container.read(shopDeepLinkProvider.notifier).state = shopTabDonation;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('НАЙКРАЩА ЦІНА'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('tapping a donation package adds grymni to the balance',
        (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      container.read(shopDeepLinkProvider.notifier).state = shopTabDonation;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      final grymniBefore = container.read(gameEconomyProvider).grymni;
      // Cheapest package: $0.99 → 100₲.
      await tester.tap(find.text('\$0.99'));
      await tester.pump();

      expect(
        container.read(gameEconomyProvider).grymni,
        grymniBefore + 100,
      );

      // Cleanup the floating SnackBar so the test exits cleanly.
      await tester.pump(const Duration(seconds: 3));

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });

  group('ShopPanel — Skills tab', () {
    testWidgets('renders the skill section header for hired agents',
        (tester) async {
      final container = await _makeContainer();
      await _pumpShopPanel(tester, container);
      await tester.pump();

      // Skills tab is index 1.
      container.read(shopDeepLinkProvider.notifier).state = 1;
      // TabBar `animateTo` is a 300ms animation; plus the SpinningCoin in the
      // header runs a perpetual repeat loop, so pumpAndSettle never returns.
      // Pump in steps, long enough for the controller to settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      // Auto-selects the first hired agent → Skill section appears.
      expect(find.text('Обери агента'), findsOneWidget);
      expect(find.text('Навички'), findsWidgets);

      // Each SkillType label is rendered.
      for (final s in SkillType.values) {
        expect(find.text(s.label), findsOneWidget,
            reason: '${s.label} should be visible');
      }

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });
}
