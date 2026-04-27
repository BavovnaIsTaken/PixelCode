/// Tests for ConsentFlowWidget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/personalization/consent_flow.dart';

void main() {
  group('ConsentFlowWidget', () {
    Widget buildTestApp() {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ConsentFlowWidget(
              agentId: 'coder#1',
              agentName: 'Developer',
            ),
          ),
        ),
      );
    }

    testWidgets('displays title and description', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(find.text('Learning Recording'), findsOneWidget);
      expect(find.text('Allow Developer to learn from its experiences'),
          findsOneWidget);
    });

    testWidgets('has toggle switch', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('default state shows consent is enabled',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(
          find.text(
              '✓ Lessons are being recorded. The agent will improve over time.'),
          findsOneWidget);
    });

    testWidgets('toggling switch changes consent state',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(
          find.text(
              '✓ Lessons are being recorded. The agent will improve over time.'),
          findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
          find.text(
              '✗ Lessons are not being recorded. The agent will not learn from this session.'),
          findsOneWidget);
    });

    testWidgets('callback is invoked when consent changes',
        (WidgetTester tester) async {
      var callCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ConsentFlowWidget(
                agentId: 'coder#1',
                agentName: 'Developer',
                onConsentChanged: () => callCount++,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(callCount, 1);
    });

    testWidgets('displays agent name in description', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ConsentFlowWidget(
                agentId: 'reviewer#1',
                agentName: 'Code Reviewer',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Allow Code Reviewer to learn from its experiences'),
          findsOneWidget);
    });

    testWidgets('state persists across rebuilds', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
          find.text(
              '✗ Lessons are not being recorded. The agent will not learn from this session.'),
          findsOneWidget);

      // Trigger rebuild by changing app theme or something
      await tester.pumpWidget(buildTestApp());

      expect(
          find.text(
              '✗ Lessons are not being recorded. The agent will not learn from this session.'),
          findsOneWidget);
    });
  });
}
