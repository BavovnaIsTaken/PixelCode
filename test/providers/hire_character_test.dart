import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/models/roster_catalog.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

Future<ProviderContainer> _makeContainer({int grymni = 100000}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  container.read(gameEconomyProvider.notifier).addGrymni(grymni);
  return container;
}

void main() {
  group('canHireCharacter', () {
    test('returns false for unknown id', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      expect(notifier.canHireCharacter('does_not_exist'), isFalse);
    });

    test('returns true when character exists and player can afford', () async {
      final c = await _makeContainer(grymni: 1000);
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      // Тетяна costs 350.
      expect(notifier.canHireCharacter('tetyana_tester'), isTrue);
    });

    test('returns false when player cannot afford', () async {
      final c = await _makeContainer(grymni: 0);
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      // Reset wallet — fresh game state already starts with some grymni.
      // Even Тетяна (350) should be unreachable when we drain via spend below.
      // Since addGrymni(0) leaves seed value, we instead pick a price the seed
      // can never afford: Максим at 2000 ₲.
      expect(notifier.canHireCharacter('maxim_llm'), isFalse);
    });

    test('seed character (price 0) can always be hired', () async {
      final c = await _makeContainer(grymni: 0);
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      expect(notifier.canHireCharacter('andriy_coder'), isTrue);
    });
  });

  group('hireCharacter', () {
    test('returns instanceId on success and persists characterId', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);

      final id = notifier.hireCharacter('tetyana_tester');
      expect(id, isNotNull);

      final state = c.read(gameEconomyProvider);
      final agent = state.agents[id!];
      expect(agent, isNotNull);
      expect(agent!.characterId, 'tetyana_tester');
      expect(agent.roleType, 'tester');
      expect(agent.nickname, 'Тетяна');
    });

    test('uses character.statWeights instead of role defaults', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      final character =
          rosterCatalog.firstWhere((r) => r.id == 'tetyana_tester');

      final id = notifier.hireCharacter('tetyana_tester')!;
      final agent = c.read(gameEconomyProvider).agents[id]!;

      for (final stat in SkillType.values) {
        expect(
          agent.skills[stat],
          character.statWeights[stat],
          reason: 'stat $stat mismatch',
        );
      }
    });

    test('uses character.defaultProvider', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);

      // Соня defaults to Gemini (AgentProviderType.local).
      final id = notifier.hireCharacter('sonya_designer')!;
      final agent = c.read(gameEconomyProvider).agents[id]!;
      expect(agent.provider, AgentProviderType.local);
    });

    test('charges character.price (not role.hireCost)', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      final balanceBefore = c.read(gameEconomyProvider).grymni;

      // Тетяна (tester role) — character.price = 350, role.hireCost = 300.
      notifier.hireCharacter('tetyana_tester');

      final balanceAfter = c.read(gameEconomyProvider).grymni;
      expect(balanceBefore - balanceAfter, 350);
    });

    test('returns null when player cannot afford', () async {
      final c = await _makeContainer(grymni: 0);
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      // Максим costs 2000 — seed wallet cannot afford.
      final id = notifier.hireCharacter('maxim_llm');
      expect(id, isNull);
    });

    test('returns null for unknown character id', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      expect(notifier.hireCharacter('phantom'), isNull);
    });

    test('hiring two of same character appends ordinal to nickname', () async {
      final c = await _makeContainer(grymni: 10000);
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);
      // Garage caps at 3 agents (manager + coder seeded → 1 slot left).
      // Upgrade office so two extra hires fit.
      notifier.upgradeOffice();

      final first = notifier.hireCharacter('tetyana_tester')!;
      final second = notifier.hireCharacter('tetyana_tester')!;

      final state = c.read(gameEconomyProvider);
      expect(state.agents[first]!.nickname, 'Тетяна');
      expect(state.agents[second]!.nickname, 'Тетяна 2');
      // Both share characterId.
      expect(state.agents[first]!.characterId, 'tetyana_tester');
      expect(state.agents[second]!.characterId, 'tetyana_tester');
    });
  });
}
