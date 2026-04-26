/// Thin Flutter glue around [FacilitatorOnboardingController] — wires the
/// pure controller to:
///
///   - default style loader (asset bundle)
///   - persistence loader (per-project disk)
///   - picker / intake screens (Navigator.push)
///   - live WS session via riverpod
///
/// Call [launchFacilitatorOnboarding] right after a project becomes
/// active (e.g. when the user opens a folder via the project selector).
/// It no-ops if the project already has a saved facilitator output and
/// short-circuits with a helpful snackbar if the WS is disconnected.
///
/// Every collaborator is exposed as an optional override so widget
/// tests can drive the flow without touching the asset bundle, the
/// filesystem, or the WS.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/facilitator_style.dart';
import '../../providers/agent_provider.dart';
import '../../screens/facilitator/facilitator_intake_screen.dart';
import '../../screens/facilitator/facilitator_picker_screen.dart';
import '../../services/facilitator_onboarding.dart';
import '../../services/facilitator_output_persistence_service.dart';
import '../../services/facilitator_session_service.dart';
import '../../services/facilitator_style_loader.dart';

Future<FacilitatorOnboardingResult> launchFacilitatorOnboarding({
  required BuildContext context,
  required WidgetRef ref,
  required String projectPath,
  // ── Optional overrides (test seams) ──────────────────────────────────────
  bool Function()? isWsConnected,
  LoadStylesFn? loadStyles,
  LoadExistingOutputFn? loadExisting,
  PickStyleFn? pickStyle,
  PickIntakeFn? pickIntake,
  RunSessionFn? runSession,
}) async {
  final ws = ref.read(wsServiceProvider);
  final connected = isWsConnected ?? () => ws.isConnected;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);

  if (!connected()) {
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(
          'Facilitator setup needs a server connection — connect and try again.',
        ),
      ),
    );
    return const FacilitatorOnboardingDisconnected();
  }

  final session = FacilitatorSessionService.bindToWsService(ws);

  final controller = FacilitatorOnboardingController(
    loadStyles: loadStyles ?? FacilitatorStyleLoader.loadDefaults,
    loadExisting: loadExisting ?? FacilitatorOutputPersistenceService.load,
    pickStyle: pickStyle ??
        (styles) => navigator.push<FacilitatorStyle>(
              MaterialPageRoute(
                builder: (_) => FacilitatorPickerScreen(styles: styles),
                fullscreenDialog: true,
              ),
            ),
    pickIntake: pickIntake ??
        (style) => navigator.push<IntakeSubmission>(
              MaterialPageRoute(
                builder: (_) => FacilitatorIntakeScreen(style: style),
                fullscreenDialog: true,
              ),
            ),
    runSession: runSession ??
        ({
          required projectPath,
          required style,
          required projectDescription,
          required answers,
        }) =>
            session.start(
              projectPath: projectPath,
              style: style,
              projectDescription: projectDescription,
              answers: answers,
            ),
  );

  final result = await controller.runIfNeeded(projectPath);

  if (context.mounted) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      final text = resultSnackbarText(result);
      if (text != null) {
        m.showSnackBar(SnackBar(content: Text(text)));
      }
    }
  }

  return result;
}

/// Public for tests — maps a result to the snackbar copy (or null if
/// no snackbar should be shown).
@visibleForTesting
String? resultSnackbarText(FacilitatorOnboardingResult result) {
  return switch (result) {
    FacilitatorOnboardingSkipped() => null,
    FacilitatorOnboardingCancelled() => null,
    FacilitatorOnboardingDisconnected() => null, // already shown earlier
    FacilitatorOnboardingCompleted(:final session) => switch (session) {
        FacilitatorSeedSuccess(:final kanbanTaskCount) =>
          'Facilitator ready — $kanbanTaskCount tasks added to the board.',
        FacilitatorSeedFailure(:final message) =>
          'Facilitator setup failed: $message',
      },
  };
}
