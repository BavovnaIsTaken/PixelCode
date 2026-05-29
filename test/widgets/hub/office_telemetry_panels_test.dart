/// Unit tests for the three telemetry panels extracted out of `agent_canvas`.
///
/// These panels are pure StatelessWidget/StatefulWidget consumers of their
/// data — no providers needed. The tests verify each one renders its expected
/// shape (header, chips, empty state) so the relocation into
/// [ActivityOverlaySheet] doesn't silently regress what was on the canvas.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/widgets/hub/office_telemetry_panels.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(width: 500, height: 400, child: child),
      ),
    );

void main() {
  group('TeamMetricsBar', () {
    testWidgets('renders header + chip per agent', (tester) async {
      await tester.pumpWidget(_wrap(TeamMetricsBar(metrics: {
        'coder#1': const AgentMetrics(
            tasksAssigned: 3, tasksCompleted: 1, reworkCount: 0),
        'character-artist#1': const AgentMetrics(
            tasksAssigned: 2, tasksCompleted: 2, reworkCount: 1),
      })));

      expect(find.text('Метрики команди'), findsOneWidget);
      expect(find.text('DEV#1'), findsOneWidget);
      expect(find.text('ART#1'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
      // Rework chip surfaces when reworkCount > 0
      expect(find.text('1rw'), findsOneWidget);
    });
  });

  group('CommGraphPanel', () {
    testWidgets('shows empty hint when no events in window', (tester) async {
      await tester.pumpWidget(_wrap(const CommGraphPanel(events: [])));
      expect(find.text('Комунікації'), findsOneWidget);
      expect(find.text('Немає комунікацій у цьому вікні'), findsOneWidget);
    });

    testWidgets('aggregates edges and shows count chip', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await tester.pumpWidget(_wrap(CommGraphPanel(events: [
        CommEvent(timestamp: now, from: 'user', to: 'manager#1'),
        CommEvent(timestamp: now, from: 'user', to: 'manager#1'),
        CommEvent(
            timestamp: now, from: 'manager#1', to: 'character-artist#1'),
      ])));
      // 'user' is rendered as 'Ви' in the edge chip.
      expect(find.text('Ви'), findsWidgets);
      expect(find.text('manager#1'), findsWidgets);
      expect(find.text('character-artist#1'), findsWidgets);
      // Aggregated count for the Ви → manager#1 edge:
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('time-window filter excludes old events', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      // 35 minutes old — outside the default 30m window.
      final old = now - 35 * 60 * 1000;
      await tester.pumpWidget(_wrap(CommGraphPanel(events: [
        CommEvent(timestamp: old, from: 'user', to: 'manager#1'),
      ])));
      expect(find.text('Немає комунікацій у цьому вікні'), findsOneWidget);
    });
  });

  group('ActivityLogPanel', () {
    testWidgets('shows empty state when no events', (tester) async {
      await tester.pumpWidget(_wrap(ActivityLogPanel(
        events: const [],
        onClear: () {},
        fillHeight: false,
      )));
      expect(find.text('Журнал активності'), findsOneWidget);
      expect(find.text('Поки що немає активності'), findsOneWidget);
    });

    testWidgets('renders row per event with agent id + detail', (tester) async {
      await tester.pumpWidget(_wrap(ActivityLogPanel(
        events: [
          ActivityEventMessage(
            timestamp: DateTime(2026, 5, 19, 12, 34, 56),
            agentId: 'coder#1',
            event: 'tool_use',
            detail: 'Reading lib/main.dart',
          ),
        ],
        onClear: () {},
        fillHeight: false,
      )));
      expect(find.text('coder#1'), findsOneWidget);
      expect(find.text('Reading lib/main.dart'), findsOneWidget);
      // Count badge in header.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('clear button invokes callback when events exist',
        (tester) async {
      var clearCalls = 0;
      await tester.pumpWidget(_wrap(ActivityLogPanel(
        events: [
          ActivityEventMessage(
            timestamp: DateTime.now(),
            agentId: 'coder#1',
            event: 'tool_use',
            detail: 'x',
          ),
        ],
        onClear: () => clearCalls++,
        fillHeight: false,
      )));
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      expect(clearCalls, 1);
    });

    testWidgets('hides header when showHeader=false', (tester) async {
      await tester.pumpWidget(_wrap(ActivityLogPanel(
        events: const [],
        onClear: () {},
        showHeader: false,
        fillHeight: false,
      )));
      expect(find.text('Журнал активності'), findsNothing);
    });
  });
}
