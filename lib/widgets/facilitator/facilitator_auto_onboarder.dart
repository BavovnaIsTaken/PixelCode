/// Watches `(connectionStatus, projectProvider)` and fires the onboarding
/// flow whenever both pre-conditions hold and the current project hasn't
/// been attempted yet in this app session.
///
/// Why this exists:
///   The user-driven trigger in `project_selector` only fires when the user
///   clicks "Open folder…" — but if the WS isn't connected at that moment,
///   `launchFacilitatorOnboarding` short-circuits with a snackbar and
///   nothing else watches for the connection coming back up. This widget
///   is the missing edge: connection-up + active project = retry.
///
/// State stays in-memory (`_attempted` set, app-session scoped). The
/// launcher itself consults disk for an existing `facilitator_output.json`
/// and skips if found, so cross-session deduplication is already handled.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/project.dart';
import '../../providers/agent_provider.dart';
import '../../providers/project_provider.dart';
import '../../services/facilitator_onboarding.dart';
import 'launch_facilitator_onboarding.dart';

/// Decision helper extracted for unit testing. Returns the project path
/// the launcher should be run against, or `null` if no run should happen.
@visibleForTesting
String? shouldAutoOnboard({
  required bool connected,
  required Project? project,
  required Set<String> attempted,
}) {
  if (!connected) return null;
  if (project == null) return null;
  if (attempted.contains(project.path)) return null;
  return project.path;
}

typedef LaunchFn = Future<FacilitatorOnboardingResult> Function({
  required BuildContext context,
  required WidgetRef ref,
  required String projectPath,
});

class FacilitatorAutoOnboarder extends ConsumerStatefulWidget {
  const FacilitatorAutoOnboarder({
    super.key,
    required this.child,
    @visibleForTesting this.launcher,
  });

  final Widget child;

  /// Test seam — defaults to the real [launchFacilitatorOnboarding].
  final LaunchFn? launcher;

  @override
  ConsumerState<FacilitatorAutoOnboarder> createState() =>
      _FacilitatorAutoOnboarderState();
}

class _FacilitatorAutoOnboarderState
    extends ConsumerState<FacilitatorAutoOnboarder> {
  final Set<String> _attempted = {};
  bool _running = false;

  LaunchFn get _launcher => widget.launcher ?? launchFacilitatorOnboarding;

  @override
  void initState() {
    super.initState();
    // The very first build's state never goes through ref.listen (which
    // only fires on transitions). Schedule a post-frame check so initial
    // (connected, project) pairs aren't missed.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeRun();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(connectionStatusProvider, (_, _) {
      _maybeRun();
    });
    ref.listen<Project?>(projectProvider, (_, _) {
      _maybeRun();
    });
    return widget.child;
  }

  Future<void> _maybeRun() async {
    if (_running) return;
    final connected =
        ref.read(connectionStatusProvider).valueOrNull ?? false;
    final project = ref.read(projectProvider);
    final path = shouldAutoOnboard(
      connected: connected,
      project: project,
      attempted: _attempted,
    );
    if (path == null) return;

    _attempted.add(path);
    _running = true;
    try {
      if (!mounted) return;
      await _launcher(
        context: context,
        ref: ref,
        projectPath: path,
      );
    } finally {
      _running = false;
    }
  }
}
