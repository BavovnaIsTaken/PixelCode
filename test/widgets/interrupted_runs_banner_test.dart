/// Widget tests for [InterruptedRunsBanner] — surfaces interrupted runs
/// filtered to the currently-selected agent, with ack affordance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/agent_runs_provider.dart';
import 'package:pixelcode/widgets/chat/interrupted_runs_banner.dart';

AgentRunSnapshot _run(
  String id, {
  required AgentRunStatus status,
  String agentId = 'manager#1',
  String? snippet,
}) =>
    AgentRunSnapshot(
      runId: id,
      agentId: agentId,
      taskType: AgentRunTaskType.chat,
      status: status,
      userMessageSnippet: snippet,
      toolCalls: const [],
      startedAt: '2026-05-17T10:00:00Z',
    );

class _FixedSelectedAgent extends SelectedAgentNotifier {
  _FixedSelectedAgent(this._value);
  final String _value;
  @override
  String build() => _value;
}

Widget _harness({required String selectedAgent}) => ProviderScope(
      overrides: [
        selectedAgentProvider
            .overrideWith(() => _FixedSelectedAgent(selectedAgent)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: InterruptedRunsBanner()),
      ),
    );

void main() {
  testWidgets('nothing rendered when there are no interrupted runs',
      (tester) async {
    await tester.pumpWidget(_harness(selectedAgent: 'manager#1'));
    expect(find.byType(InterruptedRunsBanner), findsOneWidget);
    // The banner identifies itself by the replay icon — its absence is
    // the "show nothing" contract. Material above belongs to Scaffold.
    expect(find.byIcon(Icons.replay_circle_filled_outlined), findsNothing);
    expect(find.text('Сховати'), findsNothing);
  });

  testWidgets('shows compact headline for a single interrupted run',
      (tester) async {
    await tester.pumpWidget(_harness(selectedAgent: 'manager#1'));
    final ctx = tester.element(find.byType(InterruptedRunsBanner));
    final container = ProviderScope.containerOf(ctx);
    container.read(agentRunsProvider.notifier).debugIngest([
      _run('r1', status: AgentRunStatus.interrupted, snippet: 'fix the build'),
    ]);
    await tester.pump();

    expect(find.textContaining('Виконання перервано'), findsOneWidget);
    expect(find.text('Сховати'), findsOneWidget);
  });

  testWidgets('plural headline reads "N виконань" when count > 1',
      (tester) async {
    await tester.pumpWidget(_harness(selectedAgent: 'manager#1'));
    final ctx = tester.element(find.byType(InterruptedRunsBanner));
    final container = ProviderScope.containerOf(ctx);
    container.read(agentRunsProvider.notifier).debugIngest([
      _run('r1', status: AgentRunStatus.interrupted),
      _run('r2', status: AgentRunStatus.interrupted),
      _run('r3', status: AgentRunStatus.interrupted),
    ]);
    await tester.pump();

    expect(find.textContaining('3 виконань'), findsOneWidget);
  });

  testWidgets('filters out runs for OTHER agents — multi-agent UI safe',
      (tester) async {
    await tester.pumpWidget(_harness(selectedAgent: 'manager#1'));
    final ctx = tester.element(find.byType(InterruptedRunsBanner));
    final container = ProviderScope.containerOf(ctx);
    container.read(agentRunsProvider.notifier).debugIngest([
      _run('r1', status: AgentRunStatus.interrupted, agentId: 'coder#1'),
    ]);
    await tester.pump();

    expect(find.textContaining('Виконання перервано'), findsNothing,
        reason: 'run for a different agent must not appear in this chat');
  });

  testWidgets('non-interrupted statuses do NOT trigger the banner',
      (tester) async {
    await tester.pumpWidget(_harness(selectedAgent: 'manager#1'));
    final ctx = tester.element(find.byType(InterruptedRunsBanner));
    final container = ProviderScope.containerOf(ctx);
    container.read(agentRunsProvider.notifier).debugIngest([
      _run('done', status: AgentRunStatus.completed),
      _run('fail', status: AgentRunStatus.failed),
      _run('cncl', status: AgentRunStatus.cancelled),
    ]);
    await tester.pump();

    expect(find.textContaining('Виконання перервано'), findsNothing);
  });

  testWidgets('tap on "Сховати" acks all and hides the banner',
      (tester) async {
    await tester.pumpWidget(_harness(selectedAgent: 'manager#1'));
    final ctx = tester.element(find.byType(InterruptedRunsBanner));
    final container = ProviderScope.containerOf(ctx);
    container.read(agentRunsProvider.notifier).debugIngest([
      _run('r1', status: AgentRunStatus.interrupted),
      _run('r2', status: AgentRunStatus.interrupted),
    ]);
    await tester.pump();
    expect(find.textContaining('Перервано 2'), findsOneWidget);

    await tester.tap(find.text('Сховати'));
    await tester.pump();
    expect(find.textContaining('Перервано'), findsNothing);
  });

  testWidgets('opening the details sheet shows snippet + partial output',
      (tester) async {
    await tester.pumpWidget(_harness(selectedAgent: 'manager#1'));
    final ctx = tester.element(find.byType(InterruptedRunsBanner));
    final container = ProviderScope.containerOf(ctx);
    container.read(agentRunsProvider.notifier).debugIngest([
      AgentRunSnapshot(
        runId: 'r1',
        agentId: 'manager#1',
        taskType: AgentRunTaskType.chat,
        status: AgentRunStatus.interrupted,
        userMessageSnippet: 'fix the build',
        partialOutput: 'Looking at the logs now…',
        toolCalls: const [],
        startedAt: '2026-05-17T10:00:00Z',
        reason: 'server-respawn',
      ),
    ]);
    await tester.pump();

    // Tap the banner body to open the sheet (the inkwell wraps the row).
    await tester.tap(find.textContaining('Виконання перервано'));
    await tester.pumpAndSettle();

    expect(find.text('Перервані виконання'), findsOneWidget);
    expect(find.text('fix the build'), findsOneWidget);
    expect(find.textContaining('Looking at the logs'), findsOneWidget);
    expect(find.textContaining('server-respawn'), findsOneWidget);
  });
}
