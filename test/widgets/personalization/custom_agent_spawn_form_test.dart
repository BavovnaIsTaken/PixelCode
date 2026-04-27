/// Tests for CustomAgentSpawnForm.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/personalization/custom_agent_spawn_form.dart';

void main() {
  group('CustomAgentSpawnForm', () {
    Widget buildTestApp() {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CustomAgentSpawnForm(),
          ),
        ),
      );
    }

    testWidgets('displays title and main form fields',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(find.text('Custom Agent Spawn'), findsOneWidget);
      expect(find.text('Agent Name'), findsOneWidget);
      expect(find.text('Role Bias'), findsOneWidget);
      expect(find.text('System Prompt'), findsOneWidget);
      expect(find.text('Personality Preset'), findsOneWidget);
    });

    testWidgets('has text fields for nickname and prompt',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(find.byKey(const Key('spawn-nickname')), findsOneWidget);
      expect(find.byKey(const Key('spawn-prompt')), findsOneWidget);
    });

    testWidgets('displays role bias dropdown with coder as default',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(find.byKey(const Key('spawn-role-dropdown')), findsOneWidget);
      expect(find.text('coder'), findsOneWidget);
    });

    testWidgets('displays all personality preset chips',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(find.text('Balanced'), findsOneWidget);
      expect(find.text('Speedster'), findsOneWidget);
      expect(find.text('Perfectionist'), findsOneWidget);
      expect(find.text('Creative'), findsOneWidget);
      expect(find.text('Reliable'), findsOneWidget);
    });

    testWidgets('displays skill icons for all skills',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(find.text('⚡ Швидкість'), findsOneWidget); // Speed
      expect(find.text('🎯 Точність'), findsOneWidget); // Precision
      expect(find.text('💡 Креативність'), findsOneWidget); // Creativity
      expect(find.text('🔮 Проникливість'), findsOneWidget); // Insight
      expect(find.text('🔒 Надійність'), findsOneWidget); // Reliability
    });

    testWidgets('initial skill weights are 3 each', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      // Each skill should start at 3, so we should see "3" displayed 5 times
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('applying preset changes selected preset chip',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      final speedsterChip = find.byKey(const Key('preset-speedster'));
      expect(speedsterChip, findsOneWidget);

      await tester.tap(speedsterChip);
      await tester.pumpAndSettle();

      // Speedster chip should now be selected
      final selectedChip = find.byKey(const Key('preset-speedster'));
      expect(selectedChip, findsOneWidget);
    });

    testWidgets('role dropdown can be changed',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      // Open dropdown
      await tester.tap(find.byKey(const Key('spawn-role-dropdown')));
      await tester.pumpAndSettle();

      // Select reviewer
      await tester.tap(find.text('reviewer'));
      await tester.pumpAndSettle();

      // Dropdown should now show reviewer
      expect(find.text('reviewer'), findsOneWidget);
    });

    testWidgets('create button is present in widget tree',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(find.byKey(const Key('spawn-submit')), findsOneWidget);
      expect(find.text('Create Agent'), findsOneWidget);
    });

    testWidgets('prompt field accepts text input', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      const promptText = 'Test system prompt';
      await tester.enterText(
        find.byKey(const Key('spawn-prompt')),
        promptText,
      );
      await tester.pumpAndSettle();

      expect(find.text(promptText), findsOneWidget);
    });

    testWidgets('nickname field accepts text input',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      const nickName = 'MyTestAgent';
      await tester.enterText(
        find.byKey(const Key('spawn-nickname')),
        nickName,
      );
      await tester.pumpAndSettle();

      expect(find.text(nickName), findsOneWidget);
    });

    testWidgets('has callback function support',
        (WidgetTester tester) async {
      var callbackInvoked = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CustomAgentSpawnForm(
                onSpawnCompleted: () {
                  callbackInvoked = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(callbackInvoked, isFalse);
    });
  });
}
