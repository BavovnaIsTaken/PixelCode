/// Widget tests for _ChatHeaderTraitBadges (rendered inside ChatPanel).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/agent_trait.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/widgets/chat/chat_panel.dart';

import '../../helpers/fake_ws_service.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

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
}) {
  final now = DateTime(2026, 1, 1);
  return AgentTrait(
    id: id,
    agentId: agentId,
    type: type,
    category: 'code_quality',
    tag: tag,
    lesson: 'Lesson for $tag',
    frequency: frequency,
    firstSeen: now,
    lastSeen: now,
  );
}

Future<ProviderContainer> _makeContainer({
  List<AgentTrait> traits = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    wsServiceProvider.overrideWith((_) => FakeAgentWsService()),
    if (traits.isNotEmpty)
      traitsProvider.overrideWith(() => _PresetTraitsNotifier(traits)),
  ]);
}

Future<void> _pumpChatPanel(
  WidgetTester tester,
  ProviderContainer container,
) =>
    tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: ChatPanel()),
      ),
    ));

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // selectedAgentProvider defaults to manager#1 (the seeded manager).
  const managerInstanceId = 'manager#1';

  group('chat header trait badges', () {
    testWidgets('no trait chips rendered when agent has no traits', (tester) async {
      final container = await _makeContainer(traits: [
        // Only a trait for a different agent — should not bleed to manager header.
        _trait(id: 'x1', agentId: 'coder#1', type: TraitType.strength, tag: 'precision'),
      ]);
      await _pumpChatPanel(tester, container);
      await tester.pump();

      expect(find.text('precision'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('renders top-3 trait chips for selected agent', (tester) async {
      final container = await _makeContainer(traits: [
        _trait(id: 's1', agentId: managerInstanceId, type: TraitType.strength, tag: 'delegation', frequency: 8),
        _trait(id: 's2', agentId: managerInstanceId, type: TraitType.strength, tag: 'planning', frequency: 5),
        _trait(id: 'w1', agentId: managerInstanceId, type: TraitType.weakness, tag: 'micromanaging', frequency: 3),
        _trait(id: 'w2', agentId: managerInstanceId, type: TraitType.weakness, tag: 'context-loss', frequency: 1),
      ]);
      await _pumpChatPanel(tester, container);
      await tester.pump();

      // Top-3 by frequency: delegation(8), planning(5), micromanaging(3).
      expect(find.text('delegation'), findsOneWidget);
      expect(find.text('planning'), findsOneWidget);
      expect(find.text('micromanaging'), findsOneWidget);
      // 4th trait must be hidden.
      expect(find.text('context loss'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('traits of a different agent are not shown', (tester) async {
      final container = await _makeContainer(traits: [
        _trait(id: 's1', agentId: 'coder#1', type: TraitType.strength, tag: 'precision', frequency: 9),
      ]);
      await _pumpChatPanel(tester, container);
      await tester.pump();

      expect(find.text('precision'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('weakness chips use hyphens replaced with spaces', (tester) async {
      final container = await _makeContainer(traits: [
        _trait(id: 'w1', agentId: managerInstanceId, type: TraitType.weakness, tag: 'null-checks', frequency: 4),
      ]);
      await _pumpChatPanel(tester, container);
      await tester.pump();

      expect(find.text('null checks'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });
}
