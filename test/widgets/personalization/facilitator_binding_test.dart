/// Tests for FacilitatorBindingWidget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/personalization/facilitator_binding.dart';

void main() {
  group('FacilitatorBindingWidget', () {
    testWidgets('displays title and default description',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: FacilitatorBindingWidget(
                agentId: 'coder#1',
                agentName: 'Developer',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Facilitator Style'), findsOneWidget);
      expect(find.text('Balanced approach to all tasks'), findsOneWidget);
      expect(find.text('Default'), findsWidgets);
    });

    testWidgets('displays facilitation styles info box',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: FacilitatorBindingWidget(
                agentId: 'reviewer#1',
                agentName: 'Code Reviewer',
              ),
            ),
          ),
        ),
      );

      // Verify info box is rendered with default style info
      expect(find.text('Default'), findsWidgets);
      expect(find.text('Balanced approach to all tasks'), findsOneWidget);
    });

    testWidgets('provider initializes with default style', (WidgetTester tester) async {
      var capturedStyle = FacilitatorStyle.default_;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                capturedStyle = ref.watch(agentFacilitatorProvider('test-agent'));
                return Scaffold(
                  body: FacilitatorBindingWidget(
                    agentId: 'test-agent',
                    agentName: 'Test',
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(capturedStyle, FacilitatorStyle.default_);
    });

    testWidgets('all facilitator styles have labels and descriptions',
        (WidgetTester tester) async {
      // Verify enum extension methods work correctly
      expect(FacilitatorStyle.default_.label, 'Default');
      expect(FacilitatorStyle.technical.label, 'Technical');
      expect(FacilitatorStyle.creative.label, 'Creative');
      expect(FacilitatorStyle.strategic.label, 'Strategic');

      expect(
          FacilitatorStyle.default_.description,
          'Balanced approach to all tasks');
      expect(
          FacilitatorStyle.technical.description,
          'Focus on architectural & implementation details');
      expect(FacilitatorStyle.creative.description,
          'Emphasis on design & exploration');
      expect(FacilitatorStyle.strategic.description,
          'Big-picture planning & risk analysis');
    });
  });
}
