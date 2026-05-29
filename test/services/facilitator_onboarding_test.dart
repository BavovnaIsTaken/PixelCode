import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/facilitator_style.dart';
import 'package:pixelcode/models/mission_briefing.dart';
import 'package:pixelcode/models/quest_line.dart';
import 'package:pixelcode/screens/facilitator/facilitator_intake_screen.dart';
import 'package:pixelcode/services/facilitator_onboarding.dart';
import 'package:pixelcode/services/facilitator_session_service.dart';
import 'package:pixelcode/services/project_scanner.dart';

// ─── Fixtures ────────────────────────────────────────────────────────────────

const _score = ScopeScore(
  entityCount: 1,
  interactionSurface: 1,
  auth: 0,
  integrations: 0,
  realtime: 0,
);

FacilitatorStyle _style({String id = 'game_master'}) => FacilitatorStyle(
      id: id,
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

ScannedProjectContext _scannedContext({
  String readme = 'A project.',
  String gitLog = 'abc1234 init',
  String directoryStructure = 'lib/\ntest/',
  String pubspecInfo = 'name: test_project',
}) =>
    ScannedProjectContext(
      readme: readme,
      gitLog: gitLog,
      directoryStructure: directoryStructure,
      pubspecInfo: pubspecInfo,
    );

class _Spy {
  int pickProjectModeCalls = 0;
  int loadStylesCalls = 0;
  int loadExistingCalls = 0;
  int pickStyleCalls = 0;
  int pickIntakeCalls = 0;
  int scanProjectCalls = 0;
  int runSessionCalls = 0;
}

FacilitatorOnboardingController _make({
  required _Spy spy,
  FacilitatorOutput? existing,
  ProjectMode projectMode = ProjectMode.fresh,
  List<FacilitatorStyle> styles = const [],
  FacilitatorStyle? pickedStyle,
  IntakeSubmission? pickedIntake,
  ScannedProjectContext? scannedContext,
  FacilitatorSessionResult? sessionResult,
}) {
  return FacilitatorOnboardingController(
    pickProjectMode: () async {
      spy.pickProjectModeCalls += 1;
      return projectMode;
    },
    loadExisting: (_) async {
      spy.loadExistingCalls += 1;
      return existing;
    },
    loadStyles: () async {
      spy.loadStylesCalls += 1;
      return styles;
    },
    pickStyle: (_) async {
      spy.pickStyleCalls += 1;
      return pickedStyle;
    },
    pickIntake: (_) async {
      spy.pickIntakeCalls += 1;
      return pickedIntake;
    },
    scanProject: (_) async {
      spy.scanProjectCalls += 1;
      return scannedContext ?? _scannedContext();
    },
    runSession: ({
      required projectPath,
      required style,
      required projectDescription,
      required answers,
    }) async {
      spy.runSessionCalls += 1;
      return sessionResult ??
          FacilitatorSeedSuccess(
            styleId: style.id,
            output: _output(),
            kanbanTaskCount: 0,
          );
    },
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  test('runIfNeeded — skipped when an output is already saved', () async {
    final spy = _Spy();
    final c = _make(spy: spy, existing: _output());

    final result = await c.runIfNeeded('/tmp/proj');
    expect(result, isA<FacilitatorOnboardingSkipped>());
    expect(spy.loadExistingCalls, 1);
    expect(spy.loadStylesCalls, 0);
    expect(spy.pickStyleCalls, 0);
    expect(spy.pickIntakeCalls, 0);
    expect(spy.runSessionCalls, 0);
  });

  test('runIfNeeded — cancelled when no styles are available', () async {
    final spy = _Spy();
    final c = _make(spy: spy, styles: const []);

    final result = await c.runIfNeeded('/tmp/proj');
    expect(result, isA<FacilitatorOnboardingCancelled>());
    expect(spy.pickStyleCalls, 0);
  });

  test('runIfNeeded — cancelled when picker returns null', () async {
    final spy = _Spy();
    final c = _make(spy: spy, styles: [_style()], pickedStyle: null);

    final result = await c.runIfNeeded('/tmp/proj');
    expect(result, isA<FacilitatorOnboardingCancelled>());
    expect(spy.pickStyleCalls, 1);
    expect(spy.pickIntakeCalls, 0);
    expect(spy.runSessionCalls, 0);
  });

  test('runIfNeeded — cancelled when intake returns null', () async {
    final spy = _Spy();
    final style = _style();
    final c = _make(
      spy: spy,
      styles: [style],
      pickedStyle: style,
      pickedIntake: null,
    );

    final result = await c.runIfNeeded('/tmp/proj');
    expect(result, isA<FacilitatorOnboardingCancelled>());
    expect(spy.pickIntakeCalls, 1);
    expect(spy.runSessionCalls, 0);
  });

  test('runIfNeeded — completed with success forwards intake to runSession',
      () async {
    final style = _style();
    final intake = const IntakeSubmission(
      projectDescription: 'Build a todo app',
      answers: {'party': 'Solo'},
    );
    String? capturedDesc;
    Map<String, String>? capturedAnswers;
    String? capturedPath;
    final c = FacilitatorOnboardingController(
      pickProjectMode: () async => ProjectMode.fresh,
      loadExisting: (_) async => null,
      loadStyles: () async => [style],
      pickStyle: (_) async => style,
      pickIntake: (_) async => intake,
      scanProject: (_) async => _scannedContext(),
      runSession: ({
        required projectPath,
        required style,
        required projectDescription,
        required answers,
      }) async {
        capturedPath = projectPath;
        capturedDesc = projectDescription;
        capturedAnswers = answers;
        return FacilitatorSeedSuccess(
          styleId: style.id,
          output: _output(),
          kanbanTaskCount: 3,
        );
      },
    );

    final result = await c.runIfNeeded('/tmp/proj');
    expect(result, isA<FacilitatorOnboardingCompleted>());
    final completed = result as FacilitatorOnboardingCompleted;
    expect(completed.session, isA<FacilitatorSeedSuccess>());
    expect((completed.session as FacilitatorSeedSuccess).kanbanTaskCount, 3);
    expect(capturedPath, '/tmp/proj');
    expect(capturedDesc, 'Build a todo app');
    expect(capturedAnswers, {'party': 'Solo'});
  });

  test('runIfNeeded — completed with failure still returns Completed',
      () async {
    final spy = _Spy();
    final style = _style();
    final c = _make(
      spy: spy,
      styles: [style],
      pickedStyle: style,
      pickedIntake: const IntakeSubmission(
        projectDescription: 'X',
        answers: {},
      ),
      sessionResult: const FacilitatorSeedFailure('server exploded'),
    );

    final result = await c.runIfNeeded('/tmp/proj');
    expect(result, isA<FacilitatorOnboardingCompleted>());
    expect(
      ((result as FacilitatorOnboardingCompleted).session
              as FacilitatorSeedFailure)
          .message,
      'server exploded',
    );
    expect(spy.runSessionCalls, 1);
  });

  test('runIfNeeded — cancelled when pickProjectMode returns null', () async {
    final spy = _Spy();
    // _make does not support null mode directly; build inline to test null.
    final c = FacilitatorOnboardingController(
      pickProjectMode: () async => null,
      loadExisting: (_) async {
        spy.loadExistingCalls += 1;
        return null;
      },
      loadStyles: () async {
        spy.loadStylesCalls += 1;
        return [_style()];
      },
      pickStyle: (_) async => _style(),
      pickIntake: (_) async => null,
      scanProject: (_) async => _scannedContext(),
      runSession: ({
        required projectPath,
        required style,
        required projectDescription,
        required answers,
      }) async =>
          FacilitatorSeedSuccess(
            styleId: style.id,
            output: _output(),
            kanbanTaskCount: 0,
          ),
    );

    final result = await c.runIfNeeded('/tmp/proj');
    expect(result, isA<FacilitatorOnboardingCancelled>());
    expect(spy.loadExistingCalls, 1);
    expect(spy.loadStylesCalls, 0);
  });

  test('runIfNeeded — existing mode skips picker+intake, uses scanned context',
      () async {
    final style = _style();
    final ctx = _scannedContext(
      readme: 'My app',
      gitLog: 'abc init',
      pubspecInfo: 'name: my_app',
    );
    String? capturedDesc;
    Map<String, String>? capturedAnswers;
    String? capturedStyleId;

    final c = FacilitatorOnboardingController(
      pickProjectMode: () async => ProjectMode.existing,
      loadExisting: (_) async => null,
      loadStyles: () async => [style],
      pickStyle: (_) async => throw StateError('must not be called'),
      pickIntake: (_) async => throw StateError('must not be called'),
      scanProject: (_) async => ctx,
      runSession: ({
        required projectPath,
        required style,
        required projectDescription,
        required answers,
      }) async {
        capturedStyleId = style.id;
        capturedDesc = projectDescription;
        capturedAnswers = answers;
        return FacilitatorSeedSuccess(
          styleId: style.id,
          output: _output(),
          kanbanTaskCount: 2,
        );
      },
    );

    final result = await c.runIfNeeded('/tmp/proj');
    expect(result, isA<FacilitatorOnboardingCompleted>());
    expect(capturedStyleId, 'game_master');
    expect(capturedDesc, ctx.toDescription());
    expect(capturedAnswers, ctx.toAnswers());
  });
}
