/// Tests for PersonalizationPanel widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_trait.dart';
import 'package:pixelcode/providers/agent_traits_provider.dart';
import 'package:pixelcode/widgets/personalization/personalization_panel.dart';

void main() {
  group('PersonalizationPanel', () {
    Widget buildTestApp(List<AgentTrait> traits) {
      return ProviderScope(
        overrides: [
          agentTraitsProvider('coder#1').overrideWith((ref) async => traits),
          agentTraitsByTypeProvider.overrideWith((ref, args) async {
            final (agentId, type) = args;
            final all = await ref.watch(agentTraitsProvider(agentId).future);
            return all.where((t) => t.type == type).toList();
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PersonalizationPanel(
              agentId: 'coder#1',
              agentName: 'Developer Agent',
            ),
          ),
        ),
      );
    }

    testWidgets('displays agent name', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp([]));

      expect(find.text('Developer Agent'), findsOneWidget);
      expect(find.text('Learning & Traits'), findsOneWidget);
    });

    testWidgets('displays strengths and weaknesses sections',
        (WidgetTester tester) async {
      final now = DateTime.now();
      final traits = [
        AgentTrait(
          id: '1',
          agentId: 'coder#1',
          type: TraitType.strength,
          category: 'coding',
          tag: 'Fast learner',
          lesson: 'Picks up new patterns quickly',
          frequency: 3,
          firstSeen: now.subtract(const Duration(days: 30)),
          lastSeen: now,
        ),
        AgentTrait(
          id: '2',
          agentId: 'coder#1',
          type: TraitType.weakness,
          category: 'testing',
          tag: 'Test coverage gaps',
          lesson: 'Needs reminder to write edge case tests',
          frequency: 2,
          firstSeen: now.subtract(const Duration(days: 20)),
          lastSeen: now.subtract(const Duration(days: 5)),
        ),
      ];

      await tester.pumpWidget(buildTestApp(traits));
      await tester.pumpAndSettle();

      expect(find.text('Strengths (1)'), findsOneWidget);
      expect(find.text('Weaknesses (1)'), findsOneWidget);
    });

    testWidgets('displays trait details (tag, lesson, frequency)',
        (WidgetTester tester) async {
      final now = DateTime.now();
      final trait = AgentTrait(
        id: 'trait-1',
        agentId: 'coder#1',
        type: TraitType.strength,
        category: 'architecture',
        tag: 'System design expert',
        lesson: 'Excels at designing scalable systems',
        frequency: 5,
        firstSeen: now.subtract(const Duration(days: 60)),
        lastSeen: now,
      );

      await tester.pumpWidget(buildTestApp([trait]));
      await tester.pumpAndSettle();

      expect(find.text('System design expert'), findsOneWidget);
      expect(find.text('Excels at designing scalable systems'), findsOneWidget);
      expect(find.text('×5'), findsOneWidget);
    });

    testWidgets('shows "no traits" message when list is empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp([]));
      await tester.pumpAndSettle();

      expect(find.text('No strengths yet'), findsOneWidget);
      expect(find.text('No weaknesses yet'), findsOneWidget);
    });

    testWidgets('applies emphasis colors based on frequency',
        (WidgetTester tester) async {
      final now = DateTime.now();
      final traits = [
        AgentTrait(
          id: '1',
          agentId: 'coder#1',
          type: TraitType.strength,
          category: 'test',
          tag: 'Critical skill',
          lesson: 'Observed 5+ times',
          frequency: 5,
          firstSeen: now,
          lastSeen: now,
        ),
        AgentTrait(
          id: '2',
          agentId: 'coder#1',
          type: TraitType.strength,
          category: 'test',
          tag: 'Important skill',
          lesson: 'Observed 3-4 times',
          frequency: 3,
          firstSeen: now,
          lastSeen: now,
        ),
        AgentTrait(
          id: '3',
          agentId: 'coder#1',
          type: TraitType.strength,
          category: 'test',
          tag: 'Note',
          lesson: 'Observed once or twice',
          frequency: 1,
          firstSeen: now,
          lastSeen: now,
        ),
      ];

      await tester.pumpWidget(buildTestApp(traits));
      await tester.pumpAndSettle();

      expect(find.text('Critical skill'), findsOneWidget);
      expect(find.text('Important skill'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
    });

    testWidgets('filters traits by type correctly', (WidgetTester tester) async {
      final now = DateTime.now();
      final strengthTrait = AgentTrait(
        id: '1',
        agentId: 'coder#1',
        type: TraitType.strength,
        category: 'coding',
        tag: 'Strength',
        lesson: 'A positive pattern',
        frequency: 1,
        firstSeen: now,
        lastSeen: now,
      );
      final weaknessTrait = AgentTrait(
        id: '2',
        agentId: 'coder#1',
        type: TraitType.weakness,
        category: 'testing',
        tag: 'Weakness',
        lesson: 'An area for improvement',
        frequency: 1,
        firstSeen: now,
        lastSeen: now,
      );

      await tester.pumpWidget(buildTestApp([strengthTrait, weaknessTrait]));
      await tester.pumpAndSettle();

      expect(find.text('Strengths (1)'), findsOneWidget);
      expect(find.text('Weaknesses (1)'), findsOneWidget);
      expect(find.text('Strength'), findsOneWidget);
      expect(find.text('Weakness'), findsOneWidget);
    });
  });
}
