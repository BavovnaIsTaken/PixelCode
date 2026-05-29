/// Tests for [SelectedAgentNotifier] — the self-healing chat-tab selector.
///
/// The notifier centralises a contract that used to live in every widget that
/// could remove an agent: "if the user is looking at someone who's no longer
/// on the team, snap them to a manager." Tests cover the positive (manual
/// `select`, default-on-build) and negative (deleted current selection,
/// fallback when no manager exists) paths.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('SelectedAgentNotifier — initial value', () {
    test('defaults to the seeded manager instance on first launch', () async {
      final c = await _container();
      // Force the game economy to build, then read the selected agent.
      c.read(gameEconomyProvider);
      expect(c.read(selectedAgentProvider), 'manager#1');
    });

    test('returns the literal fallback when no manager exists', () async {
      final c = await _container();
      // Touch gameEconomy first so its build runs and persists state, then
      // wipe the agents map to simulate a corrupted/empty roster.
      c.read(gameEconomyProvider);
      final notifier = c.read(gameEconomyProvider.notifier);
      notifier.state = notifier.state.copyWith(agents: {});
      // selectedAgentProvider hasn't been built yet — its build reads the
      // (now empty) agents map and falls back to the literal id.
      expect(c.read(selectedAgentProvider), 'manager#1');
    });
  });

  group('SelectedAgentNotifier.select', () {
    test('switches to the requested instance', () async {
      final c = await _container();
      c.read(gameEconomyProvider);
      c.read(selectedAgentProvider.notifier).select('coder#1');
      expect(c.read(selectedAgentProvider), 'coder#1');
    });
  });

  group('SelectedAgentNotifier — self-heal on agent removal', () {
    test('snaps to manager when the selected agent is fired', () async {
      final c = await _container();
      c.read(gameEconomyProvider); // ensure build
      // Hire a tester so we have a non-manager to fire.
      c.read(gameEconomyProvider.notifier).addGrymni(10000);
      c.read(gameEconomyProvider.notifier).hireAgent('tester');
      final testerId = c.read(gameEconomyProvider).hiredAgentIds
          .firstWhere((id) => id.startsWith('tester'));

      c.read(selectedAgentProvider.notifier).select(testerId);
      expect(c.read(selectedAgentProvider), testerId);

      final fired = c.read(gameEconomyProvider.notifier).fireAgent(testerId);
      expect(fired, isTrue);

      // Self-heal should have run via the agents-map listener.
      expect(c.read(selectedAgentProvider), 'manager#1');
    });

    test('keeps the selection when an UNRELATED agent is fired', () async {
      // Garage office caps the team at 3, and initial seeds (manager + coder)
      // already eat two slots — so we only need one extra hire to set up the
      // "fire X while focused on Y" scenario.
      final c = await _container();
      c.read(gameEconomyProvider);
      c.read(gameEconomyProvider.notifier).addGrymni(10000);
      c.read(gameEconomyProvider.notifier).hireAgent('tester');
      final testerId = c.read(gameEconomyProvider).hiredAgentIds
          .firstWhere((id) => id.startsWith('tester'));

      c.read(selectedAgentProvider.notifier).select('coder#1');
      c.read(gameEconomyProvider.notifier).fireAgent(testerId);
      expect(c.read(selectedAgentProvider), 'coder#1');
    });

    test('no-op when fire is blocked (selection unchanged)', () async {
      final c = await _container();
      c.read(gameEconomyProvider);
      c.read(selectedAgentProvider.notifier).select('coder#1');
      // Singleton manager fire is blocked by the economy guard.
      final fired =
          c.read(gameEconomyProvider.notifier).fireAgent('manager#1');
      expect(fired, isFalse);
      expect(c.read(selectedAgentProvider), 'coder#1');
    });

    test('snaps to manager when agents map is wiped externally', () async {
      final c = await _container();
      c.read(gameEconomyProvider);
      // Hire + select a non-manager to set up a dangling selection scenario.
      c.read(gameEconomyProvider.notifier).addGrymni(10000);
      c.read(gameEconomyProvider.notifier).hireAgent('tester');
      final testerId = c.read(gameEconomyProvider).hiredAgentIds
          .firstWhere((id) => id.startsWith('tester'));
      c.read(selectedAgentProvider.notifier).select(testerId);

      // Simulate a server sync that drops the tester (but keeps manager#1).
      final econ = c.read(gameEconomyProvider.notifier);
      final remaining = Map.of(c.read(gameEconomyProvider).agents)
        ..remove(testerId);
      econ.state = c.read(gameEconomyProvider).copyWith(agents: remaining);

      expect(c.read(selectedAgentProvider), 'manager#1');
    });
  });
}
