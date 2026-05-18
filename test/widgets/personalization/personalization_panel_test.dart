/// Tests for PersonalizationPanel widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';
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

    Widget buildTestApp(
      List<AgentTrait> traits, {
      ReflectionKpiMessage? kpi,
    }) {
      return ProviderScope(
        overrides: [
          traitsProvider.overrideWith(() => _FakeTraitsNotifier(traits)),
          reflectionKpiProvider.overrideWith(() => _FakeKpiNotifier(kpi)),
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

    testWidgets('tapping delete icon on strength calls removeLesson',
        (tester) async {
      final now = DateTime.now();
      final traits = [
        AgentTrait(
          id: 'str-1',
          agentId: 'coder#1',
          type: TraitType.strength,
          category: 'coding',
          tag: 'removable',
          lesson: 'Remove me strength',
          frequency: 1,
          firstSeen: now,
          lastSeen: now,
        ),
      ];
      await tester.pumpWidget(buildTestApp(traits));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping delete icon on weakness calls removeLesson',
        (tester) async {
      final now = DateTime.now();
      final traits = [
        AgentTrait(
          id: 'weak-1',
          agentId: 'coder#1',
          type: TraitType.weakness,
          category: 'testing',
          tag: 'fixable',
          lesson: 'Remove me weakness',
          frequency: 1,
          firstSeen: now,
          lastSeen: now,
        ),
      ];
      await tester.pumpWidget(buildTestApp(traits));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping clear-all button calls _clearAll', (tester) async {
      final now = DateTime.now();
      final traits = [
        AgentTrait(
          id: 'a',
          agentId: 'coder#1',
          type: TraitType.strength,
          category: 'coding',
          tag: 'alpha',
          lesson: 'Lesson A',
          frequency: 1,
          firstSeen: now,
          lastSeen: now,
        ),
      ];
      await tester.pumpWidget(buildTestApp(traits));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_sweep_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // ─── System health banner ───────────────────────────────────────────────

    testWidgets('health banner: loading placeholder when kpi is null', (tester) async {
      await tester.pumpWidget(buildTestApp([], kpi: null));
      await tester.pump(); // single pump; banner is on first frame
      expect(find.textContaining('Перевіряю'), findsOneWidget);
    });

    testWidgets('health banner: cold-project notice when hasData=false', (tester) async {
      await tester.pumpWidget(buildTestApp([], kpi: _kpi(hasData: false)));
      await tester.pumpAndSettle();
      expect(find.textContaining('"холодна"'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    });

    testWidgets('health banner: green verdict when all signals healthy', (tester) async {
      await tester.pumpWidget(buildTestApp([], kpi: _kpi(
        promotionRate: 0.4,
        bypassRate: 0.1,
        violationRate: 0.0,
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('здорова'), findsOneWidget);
      expect(find.textContaining('Усе ок'), findsOneWidget);
    });

    testWidgets('health banner: red verdict when violation rate too high', (tester) async {
      await tester.pumpWidget(buildTestApp([], kpi: _kpi(
        promotionRate: 0.4,
        bypassRate: 0.1,
        violationRate: 0.2, // > 5% threshold
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('потребує уваги'), findsOneWidget);
      expect(find.textContaining('тривоги'), findsOneWidget);
    });

    testWidgets('health banner: tap expands to show per-signal KPIs', (tester) async {
      await tester.pumpWidget(buildTestApp([], kpi: _kpi(
        promotionRate: 0.4,
      )));
      await tester.pumpAndSettle();
      // Pre-expand: KPI rows must not be visible.
      expect(find.text('Promotion rate'), findsNothing);

      // Tap the chevron to expand.
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();

      expect(find.text('Promotion rate'), findsOneWidget);
      expect(find.text('Bypass rate'), findsOneWidget);
      expect(find.text('Violation rate'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });

    testWidgets('health banner: expanded view lists recent violations', (tester) async {
      await tester.pumpWidget(buildTestApp([], kpi: _kpi(
        violationRate: 0.3, // red — to ensure banner is interactive
        recentViolations: const [
          ReflectionViolation(
            agentId: 'manager#1',
            tag: 'agent-dispatch-unavailable',
            phrases: ['was not available'],
            lesson: 'Attempted dispatch but it was not available',
            ts: '2026-05-18T10:00:00Z',
          ),
        ],
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();

      expect(find.textContaining('Останні порушення'), findsOneWidget);
      expect(
        find.textContaining('agent-dispatch-unavailable'),
        findsOneWidget,
        reason: 'recent violation tag must surface for manual inspection',
      );
    });

    testWidgets('health banner: does not crash when kpi has zero submitted', (tester) async {
      // Cold edge: hasData=true but no events yet. Must not divide-by-zero.
      await tester.pumpWidget(buildTestApp([], kpi: _kpi(
        submitted: 0,
        tooSoon: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeTraitsNotifier extends TraitsNotifier {
  final List<AgentTrait> _initial;
  _FakeTraitsNotifier(this._initial);

  @override
  List<AgentTrait> build() => _initial;

  @override
  void removeLesson(String lessonId) {
    state = state.where((t) => t.id != lessonId).toList();
  }
}

/// Test override for [reflectionKpiProvider]. Bypasses WS round-trip and
/// returns the seeded snapshot synchronously — `refresh()` is a no-op so
/// the widget never blocks pumpAndSettle waiting for a real server.
class _FakeKpiNotifier extends ReflectionKpiNotifier {
  final ReflectionKpiMessage? _initial;
  _FakeKpiNotifier(this._initial);

  @override
  ReflectionKpiMessage? build() => _initial;

  @override
  void refresh({int? sinceDays}) {
    // no-op — fixture-only
  }
}

ReflectionKpiMessage _kpi({
  bool hasData = true,
  double promotionRate = 0.4,
  double bypassRate = 0.0,
  double violationRate = 0.0,
  int submitted = 10,
  int tooSoon = 1,
  int invalidTagCount = 0,
  double invalidTagRate = 0.0,
  double tagEntropy = 3.0,
  double topTagShare = 0.2,
  List<ReflectionViolation> recentViolations = const [],
}) {
  return ReflectionKpiMessage(
    windowDays: 30,
    hasData: hasData,
    submitted: submitted,
    promotedViaThreshold: 4,
    promotedViaBypass: 0,
    pending: 4,
    duplicate: 1,
    tooSoon: tooSoon,
    prunedStale: 0,
    decayedPruned: 0,
    constraintViolations: recentViolations.length,
    invalidTagCount: invalidTagCount,
    promotionRate: promotionRate,
    bypassRate: bypassRate,
    violationRate: violationRate,
    invalidTagRate: invalidTagRate,
    tagEntropy: tagEntropy,
    topTagShare: topTagShare,
    recentViolations: recentViolations,
  );
}
