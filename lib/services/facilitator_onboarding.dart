/// Onboarding flow controller — turns the four UI/IO seams of
/// "first-time facilitator setup" into a single decision pipeline:
///
///   load existing output? → skip
///   pick style → cancel?
///   intake submission → cancel?
///   run session → complete (success or failure surfaces inside)
///
/// The screen-side wiring (Navigator.push for picker/intake, riverpod
/// for the WS service) lives in `widgets/facilitator/launch_facilitator_onboarding.dart`.
/// Keeping the orchestration here means the branch matrix is unit-testable
/// without spinning up Flutter or WebSocket infrastructure.
library;

import '../models/facilitator_output.dart';
import '../models/facilitator_style.dart';
import '../screens/facilitator/facilitator_intake_screen.dart';
import 'facilitator_session_service.dart';

// ─── Result types ────────────────────────────────────────────────────────────

sealed class FacilitatorOnboardingResult {
  const FacilitatorOnboardingResult();
}

/// Project already has a saved facilitator output — no need to onboard.
class FacilitatorOnboardingSkipped extends FacilitatorOnboardingResult {
  const FacilitatorOnboardingSkipped();
}

/// User dismissed picker or intake before completing.
class FacilitatorOnboardingCancelled extends FacilitatorOnboardingResult {
  const FacilitatorOnboardingCancelled();
}

/// Onboarding ran end-to-end. The wrapped [FacilitatorSessionResult] tells
/// the caller whether the seed itself succeeded or failed.
class FacilitatorOnboardingCompleted extends FacilitatorOnboardingResult {
  final FacilitatorSessionResult session;
  const FacilitatorOnboardingCompleted(this.session);
}

// ─── Injection seams ─────────────────────────────────────────────────────────

typedef LoadStylesFn = Future<List<FacilitatorStyle>> Function();
typedef LoadExistingOutputFn = Future<FacilitatorOutput?> Function(
  String projectPath,
);
typedef PickStyleFn = Future<FacilitatorStyle?> Function(
  List<FacilitatorStyle> styles,
);
typedef PickIntakeFn = Future<IntakeSubmission?> Function(
  FacilitatorStyle style,
);
typedef RunSessionFn = Future<FacilitatorSessionResult> Function({
  required String projectPath,
  required FacilitatorStyle style,
  required String projectDescription,
  required Map<String, String> answers,
});

// ─── Controller ──────────────────────────────────────────────────────────────

class FacilitatorOnboardingController {
  final LoadStylesFn _loadStyles;
  final LoadExistingOutputFn _loadExisting;
  final PickStyleFn _pickStyle;
  final PickIntakeFn _pickIntake;
  final RunSessionFn _runSession;

  const FacilitatorOnboardingController({
    required LoadStylesFn loadStyles,
    required LoadExistingOutputFn loadExisting,
    required PickStyleFn pickStyle,
    required PickIntakeFn pickIntake,
    required RunSessionFn runSession,
  })  : _loadStyles = loadStyles,
        _loadExisting = loadExisting,
        _pickStyle = pickStyle,
        _pickIntake = pickIntake,
        _runSession = runSession;

  /// Runs onboarding only if the project has no saved facilitator output.
  /// Returns one of the three result types so the caller can show the
  /// appropriate snackbar/toast.
  Future<FacilitatorOnboardingResult> runIfNeeded(String projectPath) async {
    final existing = await _loadExisting(projectPath);
    if (existing != null) return const FacilitatorOnboardingSkipped();

    final styles = await _loadStyles();
    if (styles.isEmpty) return const FacilitatorOnboardingCancelled();

    final style = await _pickStyle(styles);
    if (style == null) return const FacilitatorOnboardingCancelled();

    final intake = await _pickIntake(style);
    if (intake == null) return const FacilitatorOnboardingCancelled();

    final session = await _runSession(
      projectPath: projectPath,
      style: style,
      projectDescription: intake.projectDescription,
      answers: intake.answers,
    );
    return FacilitatorOnboardingCompleted(session);
  }
}
