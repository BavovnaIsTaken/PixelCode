/// Tests for PersonalizationPanel widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_trait.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/widgets/personalization/personalization_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PersonalizationPanel', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'learningConsentEnabled': true,
      });
      prefs = await SharedPreferences.getInstance();
    });

    Widget buildTestApp(List<AgentTrait> traits) {
      return ProviderScope(
        overrides: [
          traitsProvider.overrideWith(() => _FakeTraitsNotifier(traits)),
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: PersonalizationPanel(
                agentId: 'coder#1',
                agentName: 'Developer Agent',
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows agent name in header', (tester) async {
      await tester.pumpWidget(buildTestApp([]));
      await tester.pumpAndSettle();
      expect(find.text('Developer Agent'), findsOneWidget);
    });

    testWidgets('shows empty state when no traits', (tester) async {
      await tester.pumpWidget(buildTestApp([]));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.psychology_outlined), findsWidgets);
      expect(find.textContaining('немає'), findsOneWidget);
    });

    testWidgets('displays strengths section', (tester) async {
      final now = DateTime.now();
      final traits = [
        AgentTrait(
          id: '1',
          agentId: 'coder#1',
          type: TraitType.strength,
          category: 'coding',
          tag: 'fast-learner',
          lesson: 'Picks up new patterns quickly',
          frequency: 3,
          firstSeen: now.subtract(const Duration(days: 30)),
          lastSeen: now,
        ),
      ];

      await tester.pumpWidget(buildTestApp(traits));
      await tester.pumpAndSettle();

      expect(find.textContaining('(1)'), findsWidgets);
      expect(find.text('Picks up new patterns quickly'), findsOneWidget);
    });

    testWidgets('displays weaknesses section', (tester) async {
      final now = DateTime.now();
      final traits = [
        AgentTrait(
          id: '2',
          agentId: 'coder#1',
          type: TraitType.weakness,
          category: 'testing',
          tag: 'coverage-gaps',
          lesson: 'Needs reminder to write edge case tests',
          frequency: 2,
          firstSeen: now.subtract(const Duration(days: 20)),
          lastSeen: now,
        ),
      ];

      await tester.pumpWidget(buildTestApp(traits));
      await tester.pumpAndSettle();

      expect(find.text('Needs reminder to write edge case tests'),
          findsOneWidget);
    });

    testWidgets('shows frequency in trait card', (tester) async {
      final now = DateTime.now();
      final traits = [
        AgentTrait(
          id: '1',
          agentId: 'coder#1',
          type: TraitType.strength,
          category: 'architecture',
          tag: 'system-design',
          lesson: 'Excels at designing scalable systems',
          frequency: 5,
          firstSeen: now,
          lastSeen: now,
        ),
      ];

      await tester.pumpWidget(buildTestApp(traits));
      await tester.pumpAndSettle();

      expect(find.text('Excels at designing scalable systems'), findsOneWidget);
      expect(find.textContaining('×5'), findsOneWidget);
    });

    testWidgets('filters traits to only show matching agentId',
        (tester) async {
      final now = DateTime.now();
      final traits = [
        AgentTrait(
          id: '1',
          agentId: 'coder#1',
          type: TraitType.strength,
          category: 'coding',
          tag: 'belongs-here',
          lesson: 'Visible',
          frequency: 1,
          firstSeen: now,
          lastSeen: now,
        ),
        AgentTrait(
          id: '2',
          agentId: 'reviewer#1',
          type: TraitType.strength,
          category: 'review',
          tag: 'not-mine',
          lesson: 'Hidden',
          frequency: 1,
          firstSeen: now,
          lastSeen: now,
        ),
      ];

      await tester.pumpWidget(buildTestApp(traits));
      await tester.pumpAndSettle();

      expect(find.text('Visible'), findsOneWidget);
      expect(find.text('Hidden'), findsNothing);
    });

    testWidgets('has consent toggle', (tester) async {
      await tester.pumpWidget(buildTestApp([]));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('shows lesson count badge when traits exist', (tester) async {
      final now = DateTime.now();
      final traits = [
        AgentTrait(
          id: '1',
          agentId: 'coder#1',
          type: TraitType.strength,
          category: 'coding',
          tag: 'x',
          lesson: 'L1',
          frequency: 1,
          firstSeen: now,
          lastSeen: now,
        ),
        AgentTrait(
          id: '2',
          agentId: 'coder#1',
          type: TraitType.weakness,
          category: 'testing',
          tag: 'y',
          lesson: 'L2',
          frequency: 1,
          firstSeen: now,
          lastSeen: now,
        ),
      ];

      await tester.pumpWidget(buildTestApp(traits));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 уроки'), findsOneWidget);
    });

    testWidgets('has delete icon on trait cards', (tester) async {
      final now = DateTime.now();
      final traits = [
        AgentTrait(
          id: '1',
          agentId: 'coder#1',
          type: TraitType.strength,
          category: 'coding',
          tag: 'deletable',
          lesson: 'Can be removed',
          frequency: 2,
          firstSeen: now,
          lastSeen: now,
        ),
      ];

      await tester.pumpWidget(buildTestApp(traits));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });
  });
}

class _FakeTraitsNotifier extends TraitsNotifier {
  final List<AgentTrait> _initial;
  _FakeTraitsNotifier(this._initial);

  @override
  List<AgentTrait> build() => _initial;
}
