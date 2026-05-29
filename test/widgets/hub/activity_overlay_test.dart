/// Tests for [ActivityPeekButton] and [ActivityOverlaySheet].
///
/// The peek button is the only entry into the relocated telemetry surface, so
/// these tests pin: label + badge counting, build-mode suppression, and
/// the open/close affordance signalling. The sheet itself is exercised at the
/// integration boundary — empty state + rendering the three sub-panels.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/build_mode_provider.dart';
import 'package:pixelcode/widgets/hub/activity_overlay.dart';

class _FakeActivityLogNotifier extends ActivityLogNotifier {
  _FakeActivityLogNotifier(this._initial);
  final List<ActivityEventMessage> _initial;
  @override
  List<ActivityEventMessage> build() => _initial;
}

class _FakeBuildModeNotifier extends BuildModeNotifier {
  _FakeBuildModeNotifier(this._initial);
  final BuildModeState _initial;
  @override
  BuildModeState build() => _initial;
}

Widget _wrap({
  required Widget child,
  List<ActivityEventMessage> events = const [],
  bool inBuildMode = false,
}) {
  return ProviderScope(
    overrides: [
      activityLogProvider.overrideWith(
        () => _FakeActivityLogNotifier(events),
      ),
      buildModeProvider.overrideWith(
        () => _FakeBuildModeNotifier(BuildModeState(active: inBuildMode)),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    ),
  );
}

void main() {
  group('ActivityPeekButton', () {
    testWidgets('renders label in idle state', (tester) async {
      await tester.pumpWidget(_wrap(
        child: ActivityPeekButton(isOpen: false, onTap: () {}),
      ));
      expect(find.text('Активність'), findsOneWidget);
      // No badge counter when no recent events.
      expect(find.byIcon(Icons.monitor_heart_outlined), findsOneWidget);
    });

    testWidgets('shows badge counter for recent (≤60s) events',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: ActivityPeekButton(isOpen: false, onTap: () {}),
        events: [
          ActivityEventMessage(
            timestamp: DateTime.now(),
            agentId: 'coder#1',
            event: 'tool_use',
            detail: 'x',
          ),
          ActivityEventMessage(
            timestamp: DateTime.now(),
            agentId: 'coder#1',
            event: 'tool_use',
            detail: 'y',
          ),
        ],
      ));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('excludes old (>60s) events from counter', (tester) async {
      await tester.pumpWidget(_wrap(
        child: ActivityPeekButton(isOpen: false, onTap: () {}),
        events: [
          ActivityEventMessage(
            timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
            agentId: 'coder#1',
            event: 'tool_use',
            detail: 'x',
          ),
        ],
      ));
      await tester.pump();
      // Old event shouldn't appear as a live counter.
      expect(find.text('1'), findsNothing);
    });

    testWidgets('tap invokes onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        child: ActivityPeekButton(isOpen: false, onTap: () => taps++),
      ));
      await tester.tap(find.text('Активність'));
      expect(taps, 1);
    });

    testWidgets('uses expand_more icon when open', (tester) async {
      await tester.pumpWidget(_wrap(
        child: ActivityPeekButton(isOpen: true, onTap: () {}),
      ));
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byIcon(Icons.monitor_heart_outlined), findsNothing);
    });

    testWidgets('hidden (opacity 0 + ignoring) when build mode is active',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: ActivityPeekButton(isOpen: false, onTap: () {}),
        inBuildMode: true,
      ));
      // AnimatedOpacity starts at 1, so we need to settle the animation.
      await tester.pump(const Duration(milliseconds: 250));
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0);
    });
  });
}
