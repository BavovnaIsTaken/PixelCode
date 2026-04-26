import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/project.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/project_provider.dart';
import 'package:pixelcode/services/facilitator_onboarding.dart';
import 'package:pixelcode/widgets/facilitator/facilitator_auto_onboarder.dart';

// ─── Pure helper tests ───────────────────────────────────────────────────────

void main() {
  group('shouldAutoOnboard', () {
    final project = Project(path: '/tmp/proj', name: 'proj', lastOpened: DateTime.now());

    test('returns null when WS disconnected', () {
      expect(
        shouldAutoOnboard(connected: false, project: project, attempted: {}),
        isNull,
      );
    });

    test('returns null when no project', () {
      expect(
        shouldAutoOnboard(connected: true, project: null, attempted: {}),
        isNull,
      );
    });

    test('returns null when project already attempted', () {
      expect(
        shouldAutoOnboard(
          connected: true,
          project: project,
          attempted: {'/tmp/proj'},
        ),
        isNull,
      );
    });

    test('returns project path when all preconditions met', () {
      expect(
        shouldAutoOnboard(connected: true, project: project, attempted: {}),
        '/tmp/proj',
      );
    });

    test('different project not blocked by attempted set', () {
      expect(
        shouldAutoOnboard(
          connected: true,
          project: project,
          attempted: {'/tmp/other'},
        ),
        '/tmp/proj',
      );
    });
  });

  // ─── Widget integration ──────────────────────────────────────────────────

  group('FacilitatorAutoOnboarder widget', () {
    /// Recorded launcher that returns Skipped synchronously and counts
    /// invocations + paths.
    final calls = <String>[];

    Future<FacilitatorOnboardingResult> fakeLauncher({
      required BuildContext context,
      required WidgetRef ref,
      required String projectPath,
    }) async {
      calls.add(projectPath);
      return const FacilitatorOnboardingSkipped();
    }

    setUp(() => calls.clear());

    Future<void> pumpWith(
      WidgetTester tester, {
      required StreamController<bool> connection,
      required Project? initialProject,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionStatusProvider
                .overrideWith((ref) => connection.stream),
            projectProvider.overrideWith(_FakeProjectNotifier.new),
          ],
          child: MaterialApp(
            home: _TestHost(
              initialProject: initialProject,
              child: FacilitatorAutoOnboarder(
                launcher: fakeLauncher,
                child: const Scaffold(body: SizedBox()),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('does not run when starting disconnected', (tester) async {
      final conn = StreamController<bool>();
      await pumpWith(
        tester,
        connection: conn,
        initialProject: Project(
          path: '/tmp/a',
          name: 'a',
          lastOpened: DateTime.now(),
        ),
      );
      conn.add(false);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await conn.close();
    });

    testWidgets('runs when connection comes up after a disconnected start',
        (tester) async {
      final conn = StreamController<bool>();
      await pumpWith(
        tester,
        connection: conn,
        initialProject: Project(
          path: '/tmp/a',
          name: 'a',
          lastOpened: DateTime.now(),
        ),
      );
      conn.add(false);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      conn.add(true);
      await tester.pumpAndSettle();
      expect(calls, ['/tmp/a']);

      await conn.close();
    });

    testWidgets('runs only once per project even on multiple connection ticks',
        (tester) async {
      final conn = StreamController<bool>();
      await pumpWith(
        tester,
        connection: conn,
        initialProject: Project(
          path: '/tmp/a',
          name: 'a',
          lastOpened: DateTime.now(),
        ),
      );
      conn.add(true);
      await tester.pumpAndSettle();
      conn.add(false);
      await tester.pumpAndSettle();
      conn.add(true);
      await tester.pumpAndSettle();
      expect(calls, ['/tmp/a']);
      await conn.close();
    });

    testWidgets('runs again when project changes', (tester) async {
      final conn = StreamController<bool>();
      await pumpWith(
        tester,
        connection: conn,
        initialProject: Project(
          path: '/tmp/a',
          name: 'a',
          lastOpened: DateTime.now(),
        ),
      );
      conn.add(true);
      await tester.pumpAndSettle();
      expect(calls, ['/tmp/a']);

      // Switch project via the overridden notifier.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FacilitatorAutoOnboarder)),
      );
      final notifier = container.read(projectProvider.notifier)
          as _FakeProjectNotifier;
      notifier.setProject(
        Project(path: '/tmp/b', name: 'b', lastOpened: DateTime.now()),
      );
      await tester.pumpAndSettle();
      expect(calls, ['/tmp/a', '/tmp/b']);
      await conn.close();
    });

    testWidgets('does not run when project is null', (tester) async {
      final conn = StreamController<bool>();
      await pumpWith(tester, connection: conn, initialProject: null);
      conn.add(true);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await conn.close();
    });
  });
}

// ─── Test scaffolding ────────────────────────────────────────────────────────

class _FakeProjectNotifier extends ProjectNotifier {
  Project? _seed;
  @override
  Project? build() => _seed;
  void setProject(Project p) {
    _seed = p;
    state = p;
  }
}

/// Seeds the overridden ProjectNotifier with [initialProject] before the
/// child builds, so the auto-onboarder sees a real value on first frame.
class _TestHost extends ConsumerStatefulWidget {
  const _TestHost({required this.child, required this.initialProject});
  final Widget child;
  final Project? initialProject;
  @override
  ConsumerState<_TestHost> createState() => _TestHostState();
}

class _TestHostState extends ConsumerState<_TestHost> {
  @override
  void initState() {
    super.initState();
    if (widget.initialProject != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (ref.read(projectProvider.notifier) as _FakeProjectNotifier)
            .setProject(widget.initialProject!);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
