/// Widget tests for the inline-rename affordance on [AgentDetailDrawer].
///
/// Covers the surface added in D.1+:
/// * Pencil-icon / tap-name → enters edit mode
/// * Submit (Enter) → calls [renameInstance] and exits edit mode
/// * Live nickname propagation back into the drawer header via [ref.watch]
/// * Reroll button picks a name from the role's [RoleCatalogEntry.nicknamePool]
/// * Cancel does not rename
/// * Empty submit is a no-op
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/providers/ws_provider.dart';
import 'package:pixelcode/widgets/roster/agent_detail_drawer.dart';

import '../../helpers/fake_ws_service.dart';

Future<ProviderContainer> _makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    wsServiceProvider.overrideWith((_) => FakeAgentWsService()),
  ]);
}

Future<void> _pumpDrawer(
  WidgetTester tester,
  ProviderContainer container,
  AgentGameData agent,
) {
  return tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        // Drawer expects a finite-height parent; provide one via SizedBox.
        body: SizedBox(
          height: 600,
          child: AgentDetailDrawer(
            agent: agent,
            scrollController: ScrollController(),
          ),
        ),
      ),
    ),
  ));
}

/// Unmount the widget tree + dispose the container so the passive-income
/// periodic timer, debounced save timer, and server-sync timer (all owned by
/// [GameEconomyNotifier]) get cancelled before the test framework checks for
/// pending timers.
Future<void> _teardown(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
}

void main() {
  group('AgentDetailDrawer — inline rename', () {
    testWidgets('initial state shows nickname text + pencil icon',
        (tester) async {
      final c = await _makeContainer();
      final agent = c.read(gameEconomyProvider).agents['coder#1']!;

      await _pumpDrawer(tester, c, agent);
      await tester.pumpAndSettle();

      expect(find.text(agent.nickname), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      // No edit affordances visible yet.
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.casino_outlined), findsNothing);

      await _teardown(tester, c);
    });

    testWidgets('tapping the name enters edit mode with TextField + reroll',
        (tester) async {
      final c = await _makeContainer();
      final agent = c.read(gameEconomyProvider).agents['coder#1']!;

      await _pumpDrawer(tester, c, agent);
      await tester.pumpAndSettle();

      await tester.tap(find.text(agent.nickname));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.casino_outlined), findsOneWidget);
      // Pencil disappears while editing.
      expect(find.byIcon(Icons.edit_outlined), findsNothing);

      await _teardown(tester, c);
    });

    testWidgets('tapping the pencil icon enters edit mode', (tester) async {
      final c = await _makeContainer();
      final agent = c.read(gameEconomyProvider).agents['coder#1']!;

      await _pumpDrawer(tester, c, agent);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);

      await _teardown(tester, c);
    });

    testWidgets('submit via Enter calls renameInstance and exits edit mode',
        (tester) async {
      final c = await _makeContainer();
      final agent = c.read(gameEconomyProvider).agents['coder#1']!;

      await _pumpDrawer(tester, c, agent);
      await tester.pumpAndSettle();

      await tester.tap(find.text(agent.nickname));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Термінатор');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(c.read(gameEconomyProvider).agents['coder#1']!.nickname,
          'Термінатор');
      // Editor closed, new name shows in the header.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Термінатор'), findsOneWidget);
      // Pencil is back.
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      await _teardown(tester, c);
    });

    testWidgets('empty submit is a no-op (nickname unchanged)', (tester) async {
      final c = await _makeContainer();
      final original = c.read(gameEconomyProvider).agents['coder#1']!.nickname;
      final agent = c.read(gameEconomyProvider).agents['coder#1']!;

      await _pumpDrawer(tester, c, agent);
      await tester.pumpAndSettle();

      await tester.tap(find.text(original));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(c.read(gameEconomyProvider).agents['coder#1']!.nickname, original);

      await _teardown(tester, c);
    });

    testWidgets('cancel button exits edit mode without renaming',
        (tester) async {
      final c = await _makeContainer();
      final original = c.read(gameEconomyProvider).agents['coder#1']!.nickname;
      final agent = c.read(gameEconomyProvider).agents['coder#1']!;

      await _pumpDrawer(tester, c, agent);
      await tester.pumpAndSettle();

      await tester.tap(find.text(original));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Не зберігай');
      await tester.pump();

      // Two close icons exist while editing: the editor's cancel and the
      // drawer's own top-right close. Target the cancel that lives in the
      // same Row as the casino reroll icon.
      final cancelIcon = find.descendant(
        of: find
            .ancestor(
              of: find.byIcon(Icons.casino_outlined),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byIcon(Icons.close),
      );
      expect(cancelIcon, findsOneWidget);
      await tester.tap(cancelIcon);
      await tester.pumpAndSettle();

      expect(c.read(gameEconomyProvider).agents['coder#1']!.nickname, original);
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      await _teardown(tester, c);
    });

    testWidgets(
        'reroll button replaces TextField text with a name from the pool',
        (tester) async {
      final c = await _makeContainer();
      final agent = c.read(gameEconomyProvider).agents['coder#1']!;
      // coder pool — see roleCatalog entry for 'coder' in game_economy.dart.
      final coderPool = roleCatalogFor('coder')!.nicknamePool;
      expect(coderPool, isNotEmpty,
          reason: 'roleCatalog must define a nicknamePool for coder');

      await _pumpDrawer(tester, c, agent);
      await tester.pumpAndSettle();

      await tester.tap(find.text(agent.nickname));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.casino_outlined));
      await tester.pumpAndSettle();

      final textFieldWidget = tester.widget<TextField>(find.byType(TextField));
      final suggested = textFieldWidget.controller!.text;
      expect(coderPool, contains(suggested),
          reason: 'reroll must pick from the role pool');

      await _teardown(tester, c);
    });

    testWidgets(
        'drawer header reflects live nickname after rename via provider',
        (tester) async {
      final c = await _makeContainer();
      final agent = c.read(gameEconomyProvider).agents['coder#1']!;

      await _pumpDrawer(tester, c, agent);
      await tester.pumpAndSettle();

      // Mutate via provider (bypassing the UI) and confirm the header re-renders.
      c
          .read(gameEconomyProvider.notifier)
          .renameInstance('coder#1', 'НовеІмʼя');
      await tester.pump();

      expect(find.text('НовеІмʼя'), findsOneWidget);
      // Pencil affordance still present (we're not in edit mode).
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      await _teardown(tester, c);
    });
  });
}
