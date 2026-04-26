import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/facilitator_style.dart';
import 'package:pixelcode/models/mission_briefing.dart';
import 'package:pixelcode/models/quest_line.dart';
import 'package:pixelcode/screens/facilitator/facilitator_intake_screen.dart';
import 'package:pixelcode/services/facilitator_onboarding.dart';
import 'package:pixelcode/services/facilitator_session_service.dart';
import 'package:pixelcode/widgets/facilitator/launch_facilitator_onboarding.dart';

const _score = ScopeScore(
  entityCount: 1,
  interactionSurface: 1,
  auth: 0,
  integrations: 0,
  realtime: 0,
);

FacilitatorStyle _style() => FacilitatorStyle(
      id: 'game_master',
      displayName: 'Game Master',
      tagline: '',
      laloux: Laloux.green,
      personaPrompt: '',
      lexicon: const {},
      ceremonySchedule: const [],
      intakeTemplate: const [],
      outputMapper: OutputFormat.missionBriefing,
      toneModifiers: const ToneModifiers(
        aggression: 0,
        formality: 0,
        verbosity: 0,
      ),
    );

FacilitatorOutput _output() => MissionBriefing(
      id: 'mb-1',
      projectPath: '/tmp',
      objective: 'x',
      missions: const [],
      scoreBreakdown: _score,
      createdAt: DateTime.utc(2026, 4, 26),
    );

/// Single-button host that captures whatever the launcher returns. Sits
/// inside a `MaterialApp` so the launcher has Navigator + ScaffoldMessenger
/// to talk to.
class _Host extends ConsumerStatefulWidget {
  const _Host({required this.run});
  final Future<FacilitatorOnboardingResult> Function(
    BuildContext context,
    WidgetRef ref,
  ) run;
  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  FacilitatorOnboardingResult? lastResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final r = await widget.run(context, ref);
            setState(() => lastResult = r);
          },
          child: const Text('go'),
        ),
      ),
    );
  }
}

Future<_HostState> _pump(
  WidgetTester tester,
  Future<FacilitatorOnboardingResult> Function(BuildContext, WidgetRef) run,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: _Host(run: run)),
    ),
  );
  return tester.state<_HostState>(find.byType(_Host));
}

void main() {
  testWidgets('disconnected — snackbar + Disconnected result, no navigation',
      (tester) async {
    final host = await _pump(tester, (context, ref) {
      return launchFacilitatorOnboarding(
        context: context,
        ref: ref,
        projectPath: '/tmp/proj',
        isWsConnected: () => false,
        loadStyles: () async => [_style()],
        loadExisting: (_) async => null,
        pickStyle: (_) async => fail('must not reach picker'),
        pickIntake: (_) async => fail('must not reach intake'),
        runSession: ({
          required projectPath,
          required style,
          required projectDescription,
          required answers,
        }) async =>
            fail('must not reach session'),
      );
    });

    await tester.tap(find.text('go'));
    await tester.pump(); // start the future
    await tester.pump(const Duration(milliseconds: 1));

    expect(host.lastResult, isA<FacilitatorOnboardingDisconnected>());
    expect(
      find.textContaining('needs a server connection'),
      findsOneWidget,
    );
  });

  testWidgets('skipped — existing output, no snackbar, no navigation',
      (tester) async {
    final host = await _pump(tester, (context, ref) {
      return launchFacilitatorOnboarding(
        context: context,
        ref: ref,
        projectPath: '/tmp/proj',
        isWsConnected: () => true,
        loadStyles: () async => fail('must not load styles'),
        loadExisting: (_) async => _output(),
        pickStyle: (_) async => fail('must not pick'),
        pickIntake: (_) async => fail('must not intake'),
        runSession: ({
          required projectPath,
          required style,
          required projectDescription,
          required answers,
        }) async =>
            fail('must not run'),
      );
    });

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(host.lastResult, isA<FacilitatorOnboardingSkipped>());
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('completed success — snackbar shows task count', (tester) async {
    final host = await _pump(tester, (context, ref) {
      return launchFacilitatorOnboarding(
        context: context,
        ref: ref,
        projectPath: '/tmp/proj',
        isWsConnected: () => true,
        loadStyles: () async => [_style()],
        loadExisting: (_) async => null,
        pickStyle: (styles) async => styles.first,
        pickIntake: (_) async => const IntakeSubmission(
          projectDescription: 'Build a todo app',
          answers: {},
        ),
        runSession: ({
          required projectPath,
          required style,
          required projectDescription,
          required answers,
        }) async =>
            FacilitatorSeedSuccess(
          styleId: style.id,
          output: _output(),
          kanbanTaskCount: 4,
        ),
      );
    });

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(host.lastResult, isA<FacilitatorOnboardingCompleted>());
    expect(find.textContaining('4 tasks added'), findsOneWidget);
  });

  testWidgets('completed failure — snackbar shows the error', (tester) async {
    final host = await _pump(tester, (context, ref) {
      return launchFacilitatorOnboarding(
        context: context,
        ref: ref,
        projectPath: '/tmp/proj',
        isWsConnected: () => true,
        loadStyles: () async => [_style()],
        loadExisting: (_) async => null,
        pickStyle: (styles) async => styles.first,
        pickIntake: (_) async => const IntakeSubmission(
          projectDescription: 'X',
          answers: {},
        ),
        runSession: ({
          required projectPath,
          required style,
          required projectDescription,
          required answers,
        }) async =>
            const FacilitatorSeedFailure('server exploded'),
      );
    });

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(host.lastResult, isA<FacilitatorOnboardingCompleted>());
    expect(find.textContaining('server exploded'), findsOneWidget);
  });

  test('resultSnackbarText — exhaustive mapping', () {
    expect(resultSnackbarText(const FacilitatorOnboardingSkipped()), isNull);
    expect(resultSnackbarText(const FacilitatorOnboardingCancelled()), isNull);
    expect(
      resultSnackbarText(const FacilitatorOnboardingDisconnected()),
      isNull,
    );
    expect(
      resultSnackbarText(FacilitatorOnboardingCompleted(
        FacilitatorSeedSuccess(
          styleId: 'x',
          output: _output(),
          kanbanTaskCount: 7,
        ),
      )),
      contains('7 tasks added'),
    );
    expect(
      resultSnackbarText(const FacilitatorOnboardingCompleted(
        FacilitatorSeedFailure('boom'),
      )),
      contains('boom'),
    );
  });
}
