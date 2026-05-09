/// Tests for SelfPlayProgressWidget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/personalization/self_play_progress.dart';

void main() {
  group('SelfPlayProgressWidget', () {
    Widget buildTestApp({
      int completedRuns = 0,
      int totalRuns = 10,
      AgentGameData? beforeStats,
      AgentGameData? afterStats,
      bool isTraining = false,
      VoidCallback? onCancel,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SelfPlayProgressWidget(
            agentId: 'coder#1',
            agentName: 'Test Agent',
            completedRuns: completedRuns,
            totalRuns: totalRuns,
            beforeStats: beforeStats,
            afterStats: afterStats,
            isTraining: isTraining,
            onCancel: onCancel,
          ),
        ),
      );
    }

    testWidgets('displays title and agent name', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(find.text('Self-Play Training'), findsOneWidget);
      expect(find.text('Agent: Test Agent'), findsOneWidget);
    });

    testWidgets('displays progress counter', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(
        completedRuns: 3,
        totalRuns: 10,
      ));

      expect(find.byKey(const Key('progress-counter')), findsOneWidget);
      expect(find.text('3 / 10 runs'), findsOneWidget);
    });

    testWidgets('displays progress bar', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(
        completedRuns: 5,
        totalRuns: 10,
      ));

      expect(find.byKey(const Key('progress-bar')), findsOneWidget);
    });

    testWidgets('shows training in progress message when training',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(
        completedRuns: 3,
        totalRuns: 10,
        isTraining: true,
      ));

      expect(find.text('Training in progress...'), findsOneWidget);
    });

    testWidgets('shows complete message when all runs finished',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(
        completedRuns: 10,
        totalRuns: 10,
        isTraining: false,
      ));

      expect(find.text('Training complete! ✓'), findsOneWidget);
    });

    testWidgets('displays before/after stats when provided',
        (WidgetTester tester) async {
      final beforeStats = AgentGameData(
        instanceId: 'coder#1',
        roleType: 'coder',
        nickname: 'Test',
        level: 1,
        xp: 0,
        skills: {
          SkillType.speed: 1,
          SkillType.precision: 1,
          SkillType.creativity: 1,
          SkillType.insight: 1,
          SkillType.reliability: 1,
        },
      );

      final afterStats = AgentGameData(
        instanceId: 'coder#1',
        roleType: 'coder',
        nickname: 'Test',
        level: 2,
        xp: 100,
        skills: {
          SkillType.speed: 2,
          SkillType.precision: 2,
          SkillType.creativity: 2,
          SkillType.insight: 2,
          SkillType.reliability: 2,
        },
      );

      await tester.pumpWidget(buildTestApp(
        beforeStats: beforeStats,
        afterStats: afterStats,
        completedRuns: 10,
        totalRuns: 10,
      ));

      expect(find.text('Stats Improvement'), findsOneWidget);
      expect(find.text('Level'), findsOneWidget);
      expect(find.text('Avg Skill'), findsOneWidget);
      expect(find.text('XP'), findsOneWidget);
    });

    testWidgets('shows stat changes correctly', (WidgetTester tester) async {
      final beforeStats = AgentGameData(
        instanceId: 'coder#1',
        roleType: 'coder',
        nickname: 'Test',
        level: 1,
        xp: 50,
        skills: {},
      );

      final afterStats = AgentGameData(
        instanceId: 'coder#1',
        roleType: 'coder',
        nickname: 'Test',
        level: 3,
        xp: 150,
        skills: {},
      );

      await tester.pumpWidget(buildTestApp(
        beforeStats: beforeStats,
        afterStats: afterStats,
      ));

      expect(find.byKey(const Key('stat-Level')), findsOneWidget);
      expect(find.text('1 → 3'), findsOneWidget);
      expect(find.text('50 → 150'), findsOneWidget);
    });

    testWidgets('displays cancel button when training',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(
        isTraining: true,
        completedRuns: 3,
        totalRuns: 10,
        onCancel: () {},
      ));

      expect(find.byKey(const Key('cancel-training')), findsOneWidget);
      expect(find.text('Cancel Training'), findsOneWidget);
    });

    testWidgets('hides cancel button when not training',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(
        isTraining: false,
        completedRuns: 10,
        totalRuns: 10,
      ));

      expect(find.byKey(const Key('cancel-training')), findsNothing);
    });

    testWidgets('shows ready message when not started',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(
        completedRuns: 0,
        totalRuns: 10,
        isTraining: false,
      ));

      expect(find.text('Ready to train'), findsOneWidget);
    });

    testWidgets('progress counter displays zero runs',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(
        completedRuns: 0,
        totalRuns: 10,
      ));

      expect(find.text('0 / 10 runs'), findsOneWidget);
    });

    testWidgets('handles zero total runs gracefully',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(
        completedRuns: 0,
        totalRuns: 0,
      ));

      expect(find.text('0 / 0 runs'), findsOneWidget);
    });
  });
}
