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
  void log(String msg) => debugPrint('[Facilitator] $msg');

  log('launch start projectPath=$projectPath');

  final ws = ref.read(wsServiceProvider);
  final connected = isWsConnected ?? () => ws.isConnected;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);

  void toast(String text) {
    log('toast: $text');
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  if (!connected()) {
    toast(
      'Facilitator setup needs a server connection — connect and try again.',
    );
    return const FacilitatorOnboardingDisconnected();
  }
  log('ws connected — proceeding');

  final session = FacilitatorSessionService.bindToWsService(ws);

  final controller = FacilitatorOnboardingController(
    loadStyles: loadStyles ??
        () async {
          log('loading default styles…');
          final styles = await FacilitatorStyleLoader.loadDefaults();
          log('loaded ${styles.length} styles: '
              '${styles.map((s) => s.id).join(", ")}');
          return styles;
        },
    loadExisting: loadExisting ??
        (path) async {
          log('checking existing output at $path');
          final existing = await FacilitatorOutputPersistenceService.load(path);
          log('existing output: ${existing == null ? "none" : "FOUND — skipping onboarding"}');
          return existing;
        },
    pickStyle: pickStyle ??
        (styles) {
          log('pushing FacilitatorPickerScreen (${styles.length} styles)');
          return navigator.push<FacilitatorStyle>(
            MaterialPageRoute(
              builder: (_) => FacilitatorPickerScreen(styles: styles),
              fullscreenDialog: true,
            ),
          );
        },
    pickIntake: pickIntake ??
        (style) {
          log('pushing FacilitatorIntakeScreen for style=${style.id}');
          return navigator.push<IntakeSubmission>(
            MaterialPageRoute(
              builder: (_) => FacilitatorIntakeScreen(style: style),
              fullscreenDialog: true,
            ),
          );
        },
    runSession: runSession ??
        ({
          required projectPath,
          required style,
          required projectDescription,
          required answers,
        }) {
          log('starting session style=${style.id}');
          return session.start(
            projectPath: projectPath,
            style: style,
            projectDescription: projectDescription,
            answers: answers,
          );
        },
  );

  FacilitatorOnboardingResult result;
  try {
    result = await controller.runIfNeeded(projectPath);
    log('result: ${result.runtimeType}');
  } catch (e, st) {
    log('ERROR during onboarding: $e\n$st');
    if (context.mounted) toast('Facilitator onboarding error: $e');
    rethrow;
  }

  if (context.mounted) {
    final text = resultSnackbarText(result);
    if (text != null) {
      toast(text);
    } else {
      // Always surface SOMETHING so the user knows the launcher ran.
      toast(switch (result) {
        FacilitatorOnboardingSkipped() =>
          'Project already has a facilitator setup — skipping onboarding.',
        FacilitatorOnboardingCancelled() =>
          'Facilitator setup cancelled.',
        FacilitatorOnboardingDisconnected() =>
          'Facilitator setup needs a server connection.',
        _ => 'Facilitator: $result',
      });
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
