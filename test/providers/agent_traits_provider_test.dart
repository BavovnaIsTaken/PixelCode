import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/agent_trait.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/agent_traits_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

// ─── Helper: build a TraitsNotifier that starts with preset traits ──────────

class _PresetTraitsNotifier extends TraitsNotifier {
  final List<AgentTrait> initial;
  _PresetTraitsNotifier(this.initial);

  @override
  List<AgentTrait> build() => initial;
}

AgentTrait _trait({
  required String id,
  required String agentId,
  required TraitType type,
  required String tag,
  int frequency = 1,
  String category = 'code_quality',
}) {
  final now = DateTime(2026, 1, 1);
  return AgentTrait(
    id: id,
    agentId: agentId,
    type: type,
    category: category,
    tag: tag,
    lesson: 'Lesson for $tag',
    frequency: frequency,
    firstSeen: now,
    lastSeen: now,
  );
}

ProviderContainer _containerWith(List<AgentTrait> traits) {
  return ProviderContainer(
    overrides: [
      traitsProvider.overrideWith(() => _PresetTraitsNotifier(traits)),
    ],
  );
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('agentTraitsProvider', () {
    test('returns empty list when no traits exist', () {
      final c = _containerWith([]);
      addTearDown(c.dispose);

      expect(c.read(agentTraitsProvider('agent-1')), isEmpty);
    });

    test('filters traits by agentId', () {
      final c = _containerWith([
        _trait(id: 't1', agentId: 'agent-1', type: TraitType.strength, tag: 'precision'),
        _trait(id: 't2', agentId: 'agent-2', type: TraitType.strength, tag: 'speed'),
        _trait(id: 't3', agentId: 'agent-1', type: TraitType.weakness, tag: 'null-checks'),
      ]);
      addTearDown(c.dispose);

      final result = c.read(agentTraitsProvider('agent-1'));
      expect(result.length, 2);
      expect(result.every((t) => t.agentId == 'agent-1'), isTrue);
    });

    test('unknown agentId returns empty', () {
      final c = _containerWith([
        _trait(id: 't1', agentId: 'agent-1', type: TraitType.strength, tag: 'x'),
      ]);
      addTearDown(c.dispose);

      expect(c.read(agentTraitsProvider('unknown')), isEmpty);
    });

    test('result is sorted by frequency descending', () {
      final c = _containerWith([
        _trait(id: 't1', agentId: 'a', type: TraitType.strength, tag: 'low', frequency: 1),
        _trait(id: 't2', agentId: 'a', type: TraitType.strength, tag: 'high', frequency: 8),
        _trait(id: 't3', agentId: 'a', type: TraitType.weakness, tag: 'mid', frequency: 4),
      ]);
      addTearDown(c.dispose);

      final result = c.read(agentTraitsProvider('a'));
      expect(result[0].frequency, 8);
      expect(result[1].frequency, 4);
      expect(result[2].frequency, 1);
    });
  });

  group('agentTraitsByTypeProvider', () {
    test('returns only strengths when type is strength', () {
      final c = _containerWith([
        _trait(id: 's1', agentId: 'a', type: TraitType.strength, tag: 'str1'),
        _trait(id: 'w1', agentId: 'a', type: TraitType.weakness, tag: 'wk1'),
        _trait(id: 's2', agentId: 'a', type: TraitType.strength, tag: 'str2'),
      ]);
      addTearDown(c.dispose);

      final result = c.read(agentTraitsByTypeProvider(('a', TraitType.strength)));
      expect(result.length, 2);
      expect(result.every((t) => t.type == TraitType.strength), isTrue);
    });

    test('returns only weaknesses when type is weakness', () {
      final c = _containerWith([
        _trait(id: 's1', agentId: 'a', type: TraitType.strength, tag: 'str1'),
        _trait(id: 'w1', agentId: 'a', type: TraitType.weakness, tag: 'wk1'),
      ]);
      addTearDown(c.dispose);

      final result = c.read(agentTraitsByTypeProvider(('a', TraitType.weakness)));
      expect(result.length, 1);
      expect(result.first.type, TraitType.weakness);
    });

    test('returns empty list when agent has no traits of requested type', () {
      final c = _containerWith([
        _trait(id: 's1', agentId: 'a', type: TraitType.strength, tag: 'x'),
      ]);
      addTearDown(c.dispose);

      final result = c.read(agentTraitsByTypeProvider(('a', TraitType.weakness)));
      expect(result, isEmpty);
    });

    test('does not bleed across agents', () {
      final c = _containerWith([
        _trait(id: 's1', agentId: 'agent-1', type: TraitType.strength, tag: 'x'),
        _trait(id: 's2', agentId: 'agent-2', type: TraitType.strength, tag: 'y'),
      ]);
      addTearDown(c.dispose);

      final result =
          c.read(agentTraitsByTypeProvider(('agent-1', TraitType.strength)));
      expect(result.length, 1);
      expect(result.first.agentId, 'agent-1');
    });
  });

  group('agentTopicAffinitiesProvider', () {
    test('returns empty list when no traits exist', () {
      final c = _containerWith([]);
      addTearDown(c.dispose);

      expect(c.read(agentTopicAffinitiesProvider('agent-1')), isEmpty);
    });

    test('aggregates single trait with strength', () {
      final c = _containerWith([
        _trait(
          id: 't1',
          agentId: 'agent-1',
          type: TraitType.strength,
          tag: 'arch-design',
          category: 'architecture',
          frequency: 3,
        ),
      ]);
      addTearDown(c.dispose);

      final result = c.read(agentTopicAffinitiesProvider('agent-1'));
      expect(result.length, 1);
      expect(result[0].category, LessonCategory.architecture);
      expect(result[0].strengthCount, 1);
      expect(result[0].weaknessCount, 0);
      expect(result[0].totalFrequency, 3);
    });

    test('sums counts and frequencies within same category', () {
      final c = _containerWith([
        _trait(
          id: 't1',
          agentId: 'agent-1',
          type: TraitType.strength,
          tag: 'test1',
          category: 'testing',
          frequency: 2,
        ),
        _trait(
          id: 't2',
          agentId: 'agent-1',
          type: TraitType.weakness,
          tag: 'test-flaky',
          category: 'testing',
          frequency: 4,
        ),
        _trait(
          id: 't3',
          agentId: 'agent-1',
          type: TraitType.strength,
          tag: 'test2',
          category: 'testing',
          frequency: 3,
        ),
      ]);
      addTearDown(c.dispose);

      final result = c.read(agentTopicAffinitiesProvider('agent-1'));
      expect(result.length, 1);
      expect(result[0].strengthCount, 2);
      expect(result[0].weaknessCount, 1);
      expect(result[0].totalFrequency, 2 + 4 + 3); // 9
    });

    test('multiple categories sorted by totalFrequency descending', () {
      final c = _containerWith([
        _trait(
          id: 't1',
          agentId: 'agent-1',
          type: TraitType.strength,
          tag: 'arch',
          category: 'architecture',
          frequency: 5,
        ),
        _trait(
          id: 't2',
          agentId: 'agent-1',
          type: TraitType.strength,
          tag: 'quality',
          category: 'code_quality',
          frequency: 2,
        ),
        _trait(
          id: 't3',
          agentId: 'agent-1',
          type: TraitType.strength,
          tag: 'sec',
          category: 'security',
          frequency: 8,
        ),
      ]);
      addTearDown(c.dispose);

      final result = c.read(agentTopicAffinitiesProvider('agent-1'));
      expect(result.length, 3);
      expect(result[0].category, LessonCategory.security); // 8
      expect(result[1].category, LessonCategory.architecture); // 5
      expect(result[2].category, LessonCategory.codeQuality); // 2
    });

    test('skips traits with unknown category and does not crash', () {
      final c = _containerWith([
        _trait(
          id: 't1',
          agentId: 'agent-1',
          type: TraitType.strength,
          tag: 'valid',
          category: 'testing',
        ),
        _trait(
          id: 't2',
          agentId: 'agent-1',
          type: TraitType.strength,
          tag: 'invalid',
          category: 'unknown-category',
        ),
      ]);
      addTearDown(c.dispose);

      final result = c.read(agentTopicAffinitiesProvider('agent-1'));
      expect(result.length, 1);
      expect(result[0].category, LessonCategory.testing);
    });

    test('filters by agentId and returns empty for unknown agent', () {
      final c = _containerWith([
        _trait(
          id: 't1',
          agentId: 'agent-1',
          type: TraitType.strength,
          tag: 'x',
          category: 'architecture',
        ),
      ]);
      addTearDown(c.dispose);

      expect(c.read(agentTopicAffinitiesProvider('unknown-agent')), isEmpty);
    });
  });

  group('settingsProvider — learningConsentEnabled', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<ProviderContainer> makeContainer() async {
      final prefs = await SharedPreferences.getInstance();
      return ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
    }

    test('defaults to true', () async {
      final c = await makeContainer();
      addTearDown(c.dispose);

      expect(c.read(settingsProvider).learningConsentEnabled, isTrue);
    });

    test('can be set to false and persists', () async {
      final c = await makeContainer();
      addTearDown(c.dispose);

      await c.read(settingsProvider.notifier).setLearningConsentEnabled(false);
      expect(c.read(settingsProvider).learningConsentEnabled, isFalse);
    });

    test('can be toggled back to true', () async {
      final c = await makeContainer();
      addTearDown(c.dispose);

      await c.read(settingsProvider.notifier).setLearningConsentEnabled(false);
      await c.read(settingsProvider.notifier).setLearningConsentEnabled(true);
      expect(c.read(settingsProvider).learningConsentEnabled, isTrue);
    });
  });
}
