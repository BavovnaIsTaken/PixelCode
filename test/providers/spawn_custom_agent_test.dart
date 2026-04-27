import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/widgets/personalization/custom_agent_spawn_form.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

Future<ProviderContainer> _makeContainer({int grymni = 100000}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  c.read(gameEconomyProvider.notifier).addGrymni(grymni);
  return c;
}

CustomAgentSpawnData _data({
  String nickname = 'Термінатор',
  String role = 'coder',
  String prompt = 'Пиши тільки на Rust.',
  String preset = 'speedster',
  Map<SkillType, int>? skills,
}) =>
    CustomAgentSpawnData(
      nickname: nickname,
      selectedRole: role,
      systemPrompt: prompt,
      personalityPreset: preset,
      skillWeights: skills ??
          {
            SkillType.speed: 5,
            SkillType.precision: 3,
            SkillType.creativity: 3,
            SkillType.insight: 3,
            SkillType.reliability: 2,
          },
    );

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('spawnCustomAgent', () {
    test('creates agent with correct roleType and nickname', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);

      final id = c.read(gameEconomyProvider.notifier).spawnCustomAgent(_data());

      expect(id, isNotNull);
      final agent = c.read(gameEconomyProvider).agents[id!];
      expect(agent, isNotNull);
      expect(agent!.roleType, 'coder');
      expect(agent.nickname, 'Термінатор');
    });

    test('persists customSystemPrompt on agent', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);

      final id = c
          .read(gameEconomyProvider.notifier)
          .spawnCustomAgent(_data(prompt: 'Always use TDD.'));

      final agent = c.read(gameEconomyProvider).agents[id!]!;
      expect(agent.customSystemPrompt, 'Always use TDD.');
    });

    test('persists personalityPreset on agent', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);

      final id = c
          .read(gameEconomyProvider.notifier)
          .spawnCustomAgent(_data(preset: 'creative'));

      final agent = c.read(gameEconomyProvider).agents[id!]!;
      expect(agent.personalityPreset, 'creative');
    });

    test('persists custom skill weights on agent', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);

      final weights = {
        SkillType.speed: 7,
        SkillType.precision: 2,
        SkillType.creativity: 5,
        SkillType.insight: 3,
        SkillType.reliability: 1,
      };
      final id = c
          .read(gameEconomyProvider.notifier)
          .spawnCustomAgent(_data(skills: weights));

      final agent = c.read(gameEconomyProvider).agents[id!]!;
      expect(agent.skills[SkillType.speed], 7);
      expect(agent.skills[SkillType.creativity], 5);
    });

    test('deducts hire cost from grymni', () async {
      final c = await _makeContainer(grymni: 1000);
      addTearDown(c.dispose);

      final before = c.read(gameEconomyProvider).grymni;
      // tech-lead costs 500₲ (coder is free/seeded and would produce no delta)
      final id = c
          .read(gameEconomyProvider.notifier)
          .spawnCustomAgent(_data(role: 'tech-lead'));
      expect(id, isNotNull);
      final after = c.read(gameEconomyProvider).grymni;

      expect(after, lessThan(before));
    });

    test('returns null when insufficient grymni', () async {
      final c = await _makeContainer(grymni: 0);
      addTearDown(c.dispose);

      // security costs 800₲; initial seed is 500₲ → insufficient
      final id = c
          .read(gameEconomyProvider.notifier)
          .spawnCustomAgent(_data(role: 'security'));
      expect(id, isNull);
    });

    test('returns null when team is at capacity', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(gameEconomyProvider.notifier);

      // Fill the team to max (hire until canHireMore is false).
      for (var i = 0; i < 20; i++) {
        if (!c.read(gameEconomyProvider).canHireMore) break;
        notifier.hireAgent('coder');
      }
      expect(c.read(gameEconomyProvider).canHireMore, isFalse);

      final id = notifier.spawnCustomAgent(_data());
      expect(id, isNull);
    });

    test('empty prompt is stored as null (no blank injection)', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);

      final id = c
          .read(gameEconomyProvider.notifier)
          .spawnCustomAgent(_data(prompt: ''));

      final agent = c.read(gameEconomyProvider).agents[id!]!;
      expect(agent.customSystemPrompt, isNull);
    });
  });

  group('AgentGameData serialization — custom fields', () {
    test('roundtrip preserves customSystemPrompt and personalityPreset',
        () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);

      final id = c.read(gameEconomyProvider.notifier).spawnCustomAgent(
            _data(prompt: 'Be concise.', preset: 'perfectionist'),
          );

      final original = c.read(gameEconomyProvider).agents[id!]!;
      final json = original.toJson();
      final restored = AgentGameData.fromJson(json);

      expect(restored.customSystemPrompt, 'Be concise.');
      expect(restored.personalityPreset, 'perfectionist');
    });

    test('fromJson with missing custom fields defaults to null', () {
      final json = {
        'instanceId': 'coder#1',
        'roleType': 'coder',
        'nickname': 'Кодер',
        'hardware': 0,
        'skills': <String, dynamic>{},
        'level': 1,
        'xp': 0,
        'provider': 0,
      };
      final agent = AgentGameData.fromJson(json);
      expect(agent.customSystemPrompt, isNull);
      expect(agent.personalityPreset, isNull);
    });
  });
}
