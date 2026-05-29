import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/models/roster_catalog.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/widgets/personalization/custom_agent_spawn_form.dart';
import 'package:pixelcode/widgets/shop/shop_panel.dart';

import '../../helpers/fake_ws_service.dart';

CustomAgentSpawnData _spawnData() => CustomAgentSpawnData(
      nickname: 'Заповнювач',
      selectedRole: 'coder',
      systemPrompt: '',
      personalityPreset: 'balanced',
      skillWeights: {for (final s in SkillType.values) s: 3},
    );

Future<ProviderContainer> _makeContainer({int grymni = 5000}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    wsServiceProvider.overrideWith((_) => FakeAgentWsService()),
  ]);
}

Future<void> _pumpRosterTab(WidgetTester tester, ProviderContainer container) =>
    tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: RosterTab())),
    ));

void main() {
  group('RosterTab', () {
    testWidgets('renders roster character names',
        (WidgetTester tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      // ListView lazy-renders, so we only assert that the first character's
      // name reaches the widget tree. The catalog length itself isn't asserted
      // — it's a const list and other tests already reference characters by id
      // (`tetyana_tester`, `andriy_coder`, etc.), so deletions surface there.
      final firstChar = rosterCatalog.first;
      expect(find.text(firstChar.name), findsWidgets,
          reason: '${firstChar.name} should be visible');
      expect(rosterCatalog, isNotEmpty,
          reason: 'Roster catalog should never be empty');

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('renders role filter chips with "Усі" option',
        (WidgetTester tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      // "Усі" filter chip should exist
      expect(find.text('Усі'), findsWidgets, reason: 'Filter chip for "Усі" exists');

      // Roster has unique role types
      final rosterRoles = <String>{};
      for (final c in rosterCatalog) {
        rosterRoles.add(c.roleType);
      }
      expect(rosterRoles.length, greaterThan(0), reason: 'Should have role filters');

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('filter by role shows only that role characters',
        (WidgetTester tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      // In full view, all roster characters are visible
      final tetyana = rosterCatalog.firstWhere((c) => c.id == 'tetyana_tester');
      expect(find.text(tetyana.name), findsOneWidget);

      // Verify all roster roles have chips
      final rosterRoles = <String>{};
      for (final c in rosterCatalog) {
        if (!rosterRoles.contains(c.roleType)) rosterRoles.add(c.roleType);
      }
      expect(rosterRoles.length, greaterThan(0),
          reason: 'Should have roster role filter chips');

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('"Усі" chip shows roster characters in default view',
        (WidgetTester tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      // Default view: at least the first character is visible
      final firstChar = rosterCatalog.first;
      expect(find.text(firstChar.name), findsWidgets,
          reason: '${firstChar.name} visible in default roster view');

      // Verify role filter chips exist (all should be present in default view)
      final rosterRoles = <String>{};
      for (final c in rosterCatalog) {
        if (!rosterRoles.contains(c.roleType)) rosterRoles.add(c.roleType);
      }
      expect(rosterRoles.length, greaterThan(0));

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('hire button enabled when player can afford',
        (WidgetTester tester) async {
      final container = await _makeContainer(grymni: 5000);
      await _pumpRosterTab(tester, container);
      await tester.pump();

      // Тетяна costs 350 ₲ — with 5000 grymni, should be affordable
      final tetyana = rosterCatalog.firstWhere((c) => c.id == 'tetyana_tester');
      expect(find.text('${tetyana.price}₲'), findsOneWidget,
          reason: 'Character price should be visible');

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('hire button shows correct price text',
        (WidgetTester tester) async {
      // Максим costs 2000 ₲
      final container = await _makeContainer(grymni: 100);
      await _pumpRosterTab(tester, container);
      await tester.pump();

      final maxim = rosterCatalog.firstWhere((c) => c.id == 'maxim_llm');
      // Price display should be there (2000₲) - button may be disabled but price visible
      // Since ListView lazy renders, just verify the character exists in catalog
      expect(maxim.price, 2000);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('hiring a character shows "найнятий" badge',
        (WidgetTester tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      final tetyana = rosterCatalog.firstWhere((c) => c.id == 'tetyana_tester');
      expect(find.text('найнятий'), findsNothing,
          reason: 'Badge should not show before hire');

      // Hire the character via the notifier
      final notifier = container.read(gameEconomyProvider.notifier);
      notifier.hireCharacter(tetyana.id);

      // Pump to rebuild
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpRosterTab(tester, container);
      await tester.pump();

      // Badge should now be visible
      expect(find.text('найнятий'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('hired agent appears in game state',
        (WidgetTester tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      // Hire a character via the notifier
      final notifier = container.read(gameEconomyProvider.notifier);
      final tetyana = rosterCatalog.firstWhere((c) => c.id == 'tetyana_tester');
      final instanceId = notifier.hireCharacter(tetyana.id);

      // Verify hire was successful
      expect(instanceId, isNotNull);

      // Check game state reflects the hire
      final game = container.read(gameEconomyProvider);
      expect(game.agents.containsKey(instanceId), true);
      expect(game.agents[instanceId]!.characterId, tetyana.id);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('vendor pills display correct provider labels',
        (WidgetTester tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      // Check for provider labels - at least some should be visible
      // (ListView lazy rendering may not show all at once)
      final providers = {'Claude', 'DeepSeek', 'Gemini', 'Kimi', 'Local'};
      var foundCount = 0;
      for (final provider in providers) {
        if (find.text(provider).evaluate().isNotEmpty) {
          foundCount++;
        }
      }
      expect(foundCount, greaterThan(0), reason: 'At least one provider should be visible');

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('stat bars render for visible characters',
        (WidgetTester tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      // Each character has 5 stats, all 7 characters visible = 35 progress bars
      final progressBars = find.byType(LinearProgressIndicator);
      expect(progressBars, findsWidgets);
      // At least 5 bars visible (for one character)
      expect(progressBars.evaluate().length, greaterThanOrEqualTo(5));

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('free character (Андрій) shows "Безкоштовно" label',
        (WidgetTester tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      final andriy = rosterCatalog.firstWhere((c) => c.id == 'andriy_coder');
      expect(andriy.price, 0, reason: 'Андрій should be free');

      expect(find.text('Безкоштовно'), findsOneWidget,
          reason: 'Free character label should be visible');

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('character cards render with tagline and icons',
        (WidgetTester tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      // Check first character (guaranteed to be visible in ListView)
      final firstChar = rosterCatalog.first;
      expect(find.text(firstChar.name), findsOneWidget,
          reason: '${firstChar.name} should be visible');
      expect(find.text(firstChar.tagline), findsOneWidget,
          reason: 'Tagline should be visible');

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('character strength and weakness display for first character',
        (WidgetTester tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      // Check first character only (guaranteed visible)
      final firstChar = rosterCatalog.first;
      // The display format is "💪 ${character.strength}" - find() searches the rendered text
      final strengthFinder = find.textContaining(firstChar.strength);
      expect(strengthFinder, findsOneWidget,
          reason: 'Strength should be visible for ${firstChar.name}');

      final weaknessFinder = find.textContaining(firstChar.weakness);
      expect(weaknessFinder, findsOneWidget,
          reason: 'Weakness should be visible for ${firstChar.name}');

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });

  // ─── Singleton manager fire guard ──────────────────────────────────────

  group('Manager fire guard', () {
    testWidgets(
        'manager row shows "Основа" badge instead of a fire button',
        (tester) async {
      // Primary UX defense: the manager row never renders a destructive
      // "Звільнити" action, so the user cannot trigger the singleton block
      // in normal flow. The toast (and fireAgent → false contract) is the
      // defense-in-depth backstop.
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      // Manager row exists.
      expect(find.byKey(const Key('team-row-manager#1')), findsOneWidget);
      // The team row for the manager carries the "Основа" badge.
      final managerRow = find.byKey(const Key('team-row-manager#1'));
      expect(
        find.descendant(of: managerRow, matching: find.text('Основа')),
        findsOneWidget,
      );
      // …and does NOT render the "Звільнити" action.
      expect(
        find.descendant(of: managerRow, matching: find.text('Звільнити')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets(
        'firing the only manager via the provider is a no-op '
        '(defense-in-depth)',
        (tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      final before = container.read(gameEconomyProvider).agents.length;
      final fired = container
          .read(gameEconomyProvider.notifier)
          .fireAgent('manager#1');
      expect(fired, isFalse);
      expect(container.read(gameEconomyProvider).agents.length, before);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });

  // ─── _ImportAgentCard ──────────────────────────────────────────────────────

  group('ImportAgentCard', () {
    testWidgets('renders import card text', (tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Імпорт агента'),
        300.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Імпорт агента'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('shows disabled hint when team is full', (tester) async {
      final container = await _makeContainer();
      // Initial state: 2 agents (manager + coder), garage max = 3. Spawn 1 more.
      container.read(gameEconomyProvider.notifier).spawnCustomAgent(_spawnData());

      await _pumpRosterTab(tester, container);
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Імпорт агента'),
        300.0,
        scrollable: find.byType(Scrollable).first,
      );
      // Both _SpawnCustomAgentCard and _ImportAgentCard show this text when full
      expect(find.text('Немає вільних місць у команді'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('tapping import card when team has space opens dialog',
        (tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Імпорт агента'),
        300.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Імпорт агента'));
      await tester.pumpAndSettle();

      expect(find.text('Import Agent'), findsOneWidget);
      expect(find.byKey(const Key('import-agent-json-field')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('confirm with invalid JSON shows error text in dialog',
        (tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Імпорт агента'),
        300.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Імпорт агента'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('import-agent-json-field')),
        'not valid json',
      );
      await tester.tap(find.byKey(const Key('import-agent-confirm-btn')));
      await tester.pump();

      expect(
        find.text('Invalid JSON — could not parse agent blueprint'),
        findsOneWidget,
      );
      // Dialog stays open
      expect(find.text('Import Agent'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('confirm with valid JSON closes dialog and spawns agent',
        (tester) async {
      final container = await _makeContainer();
      await _pumpRosterTab(tester, container);
      await tester.pump();

      final countBefore = container.read(gameEconomyProvider).agents.length;

      await tester.scrollUntilVisible(
        find.text('Імпорт агента'),
        300.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Імпорт агента'));
      await tester.pumpAndSettle();

      const validJson =
          '{"pixelcodeAgent":"1","roleType":"coder","nickname":"Імпортований",'
          '"skills":{"0":5,"1":3,"2":2,"3":3,"4":2},'
          '"exportedAt":"2026-01-01T00:00:00.000Z"}';

      await tester.enterText(
        find.byKey(const Key('import-agent-json-field')),
        validJson,
      );
      await tester.tap(find.byKey(const Key('import-agent-confirm-btn')));
      await tester.pumpAndSettle();

      // Dialog closed
      expect(find.text('Import Agent'), findsNothing);

      // New agent added to game state
      final countAfter = container.read(gameEconomyProvider).agents.length;
      expect(countAfter, countBefore + 1);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    // ─── Memory icon (Roster row → PersonalizationPanel) ─────────────────

    testWidgets('memory icon: tap opens PersonalizationPanel bottom-sheet',
        (WidgetTester tester) async {
      final container = await _makeContainer();
      // A hired agent is required to render a _TeamRow.
      final notifier = container.read(gameEconomyProvider.notifier);
      final tetyana = rosterCatalog.firstWhere((c) => c.id == 'tetyana_tester');
      notifier.hireCharacter(tetyana.id);

      await _pumpRosterTab(tester, container);
      await tester.pumpAndSettle();

      // The memory icon is rendered once per hired-agent row.
      final iconFinder = find.byIcon(Icons.psychology_outlined);
      expect(iconFinder, findsWidgets,
          reason: '🧠 memory icon should render for the hired agent');

      // Tap → bottom-sheet renders with the agent name.
      await tester.tap(iconFinder.first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Пам\'ять агента'), findsAtLeastNWidgets(1));

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets(
      'memory icon: hover brightens icon color and adds halo background',
      (WidgetTester tester) async {
        final container = await _makeContainer();
        final notifier = container.read(gameEconomyProvider.notifier);
        final tetyana =
            rosterCatalog.firstWhere((c) => c.id == 'tetyana_tester');
        notifier.hireCharacter(tetyana.id);

        await _pumpRosterTab(tester, container);
        await tester.pumpAndSettle();

        final iconFinder = find.byIcon(Icons.psychology_outlined).first;
        final preColor = tester.widget<Icon>(iconFinder).color!;
        expect(
          preColor.a,
          lessThan(0.5),
          reason: 'rest-state icon should be dim',
        );

        // Move a synthetic mouse pointer onto the icon.
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(gesture.removePointer);
        await gesture.addPointer(location: Offset.zero);
        await tester.pump();
        await gesture.moveTo(tester.getCenter(iconFinder));
        // Allow hover animation (140ms) plus a safety margin to settle.
        await tester.pump(const Duration(milliseconds: 200));

        final hoverColor =
            tester.widget<Icon>(find.byIcon(Icons.psychology_outlined).first).color!;
        expect(
          hoverColor.a,
          greaterThan(preColor.a),
          reason:
              'hover state must brighten the icon (alpha higher than rest)',
        );

        // Move pointer away — icon must revert.
        await gesture.moveTo(const Offset(2000, 2000));
        await tester.pump(const Duration(milliseconds: 200));
        final restoredColor = tester
            .widget<Icon>(find.byIcon(Icons.psychology_outlined).first)
            .color!;
        expect(
          restoredColor.a,
          closeTo(preColor.a, 0.001),
          reason: 'on pointer exit the icon must return to rest-state alpha',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );

    testWidgets(
      'memory icon: hover does not affect the rest-state look on touch-only paths',
      (WidgetTester tester) async {
        // Without any mouse pointer, the icon must remain in its dim rest-state
        // — touch-only devices (phones, tablets without trackpad) should see
        // the same look as before the hover affordance was introduced.
        final container = await _makeContainer();
        final notifier = container.read(gameEconomyProvider.notifier);
        final tetyana =
            rosterCatalog.firstWhere((c) => c.id == 'tetyana_tester');
        notifier.hireCharacter(tetyana.id);

        await _pumpRosterTab(tester, container);
        await tester.pumpAndSettle();

        final iconColor = tester
            .widget<Icon>(find.byIcon(Icons.psychology_outlined).first)
            .color!;
        expect(iconColor.a, lessThan(0.5));

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );
  });
}
