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
/// It no-ops if the project already has a saved facilitator output.
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
}) async {
  final ws = ref.read(wsServiceProvider);
  final session = FacilitatorSessionService.bindToWsService(ws);
  final navigator = Navigator.of(context);

  final controller = FacilitatorOnboardingController(
    loadStyles: FacilitatorStyleLoader.loadDefaults,
    loadExisting: FacilitatorOutputPersistenceService.load,
    pickStyle: (styles) => navigator.push<FacilitatorStyle>(
      MaterialPageRoute(
        builder: (_) => FacilitatorPickerScreen(styles: styles),
        fullscreenDialog: true,
      ),
    ),
    pickIntake: (style) => navigator.push<IntakeSubmission>(
      MaterialPageRoute(
        builder: (_) => FacilitatorIntakeScreen(style: style),
        fullscreenDialog: true,
      ),
    ),
    runSession: ({
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      final text = _resultMessage(result);
      if (text != null) {
        messenger.showSnackBar(SnackBar(content: Text(text)));
      }
    }
  }

  return result;
}

String? _resultMessage(FacilitatorOnboardingResult result) {
  return switch (result) {
    FacilitatorOnboardingSkipped() => null,
    FacilitatorOnboardingCancelled() => null,
    FacilitatorOnboardingCompleted(:final session) => switch (session) {
        FacilitatorSeedSuccess(:final kanbanTaskCount) =>
          'Facilitator ready — $kanbanTaskCount tasks added to the board.',
        FacilitatorSeedFailure(:final message) =>
          'Facilitator setup failed: $message',
      },
  };
}
