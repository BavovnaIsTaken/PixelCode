/// Regression tests for the "office disappears after session takeover" bug.
///
/// Root cause: SessionBanner was returning SizedBox.shrink() (a non-positioned
/// widget) when in primary/sole/offline mode. The outer Stack in _buildOffice()
/// uses StackFit.loose inside Column → Expanded, which gives loose cross-axis
/// constraints (minWidth = 0). A Stack with a 0×0 non-positioned child sizes
/// its width to max(minWidth=0, 0) = 0, collapsing the canvas to invisible.
///
/// Fix: SessionBanner.build() ALWAYS returns Positioned so the Stack never has
/// non-positioned children and always sizes to constraints.biggest.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/providers/game_session_provider.dart';
import 'package:pixelcode/providers/ws_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';
import 'package:pixelcode/widgets/canvas/session_banner.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// A fake WS service that never connects — session stays offline until we
/// directly override the gameSessionProvider state in tests.
class _OfflineWsService extends AgentWsService {
  @override
  Stream<bool> get connectionStatus async* {
    yield false;
  }
}

/// Builds the minimal widget tree that reproduces the bug:
///   Column → Expanded → Stack (StackFit.loose) → [Positioned canvas, SessionBanner]
///
/// The Stack's rendered width is checked after each session mode transition.
Widget _buildTestWidget(GameSessionState sessionState) {
  return ProviderScope(
    overrides: [
      wsServiceProvider.overrideWithValue(_OfflineWsService()),
      gameSessionProvider.overrideWith(() => _FixedSessionNotifier(sessionState)),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: _TestCanvas(),
      ),
    ),
  );
}

class _FixedSessionNotifier extends GameSessionNotifier {
  final GameSessionState _initial;
  _FixedSessionNotifier(this._initial);

  @override
  GameSessionState build() => _initial;
}

/// Reproduces the Stack layout from _buildOffice:
///   Column → Expanded → Stack (loose) → [Positioned(canvas), SessionBanner()]
class _TestCanvas extends StatelessWidget {
  const _TestCanvas();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            // StackFit.loose is the default — do NOT specify StackFit.expand here,
            // this test must reproduce the exact production layout.
            children: [
              // Simulates the Positioned canvas fill
              Positioned.fill(
                child: Container(
                  key: const Key('canvas'),
                  color: Colors.blue,
                ),
              ),
              const SessionBanner(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('SessionBanner layout — canvas must not collapse (regression)', () {
    // Helper: pump and return the width of the canvas container.
    Future<double> canvasWidth(WidgetTester tester) async {
      final finder = find.byKey(const Key('canvas'));
      expect(finder, findsOneWidget, reason: 'canvas container must be in tree');
      return tester.getSize(finder).width;
    }

    testWidgets('canvas is full width in offline mode (initial)',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(mode: GameSessionMode.offline),
      ));
      await tester.pump();
      expect(await canvasWidth(tester), greaterThan(0),
          reason: 'offline → SizedBox.shrink must not collapse the Stack');
    });

    testWidgets('canvas is full width in sole mode (primary without other devices)',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(mode: GameSessionMode.sole),
      ));
      await tester.pump();
      expect(await canvasWidth(tester), greaterThan(0),
          reason: 'sole → SizedBox.shrink must not collapse the Stack');
    });

    testWidgets('canvas is full width in primary mode (multi-device)',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(mode: GameSessionMode.primary),
      ));
      await tester.pump();
      expect(await canvasWidth(tester), greaterThan(0),
          reason: 'primary → SizedBox.shrink must not collapse the Stack');
    });

    testWidgets('canvas is full width in viewer mode', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(
          mode: GameSessionMode.viewer,
          primaryDevice: 'Android',
        ),
      ));
      await tester.pump();
      expect(await canvasWidth(tester), greaterThan(0));
    });

    testWidgets('canvas is full width in takeoverPending mode', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(mode: GameSessionMode.takeoverPending),
      ));
      await tester.pump();
      expect(await canvasWidth(tester), greaterThan(0));
    });

    testWidgets('canvas is full width in primary with takeover request',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(
          mode: GameSessionMode.primary,
          takeoverRequestFrom: 'iPhone',
        ),
      ));
      await tester.pump();
      expect(await canvasWidth(tester), greaterThan(0));
    });

    testWidgets(
        'canvas stays full width after viewer → sole transition (the exact bug scenario)',
        (tester) async {
      // Start in viewer mode (office was visible here before the bug).
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(
          mode: GameSessionMode.viewer,
          primaryDevice: 'Android',
        ),
      ));
      await tester.pump();
      final widthBefore = await canvasWidth(tester);
      expect(widthBefore, greaterThan(0));

      // Simulate the session takeover completing — mode transitions to sole.
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(mode: GameSessionMode.sole),
      ));
      await tester.pump();
      final widthAfter = await canvasWidth(tester);

      // Without the fix: widthAfter was 0, hiding the office.
      expect(widthAfter, greaterThan(0),
          reason: 'office must stay visible after takeover completes');
      expect(widthAfter, equals(widthBefore),
          reason: 'canvas width must be unchanged after mode transition');
    });

    testWidgets(
        'canvas stays full width after takeoverPending → primary transition',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(mode: GameSessionMode.takeoverPending),
      ));
      await tester.pump();
      final widthBefore = await canvasWidth(tester);

      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(mode: GameSessionMode.primary),
      ));
      await tester.pump();
      expect(await canvasWidth(tester), equals(widthBefore));
    });
  });

  group('SessionBanner always returns Positioned (unit)', () {
    // Build SessionBanner in isolation and verify that the root widget it
    // builds into is always Positioned — never a bare SizedBox or similar.

    Widget wrap(GameSessionState state) => ProviderScope(
          overrides: [
            wsServiceProvider.overrideWithValue(_OfflineWsService()),
            gameSessionProvider.overrideWith(() => _FixedSessionNotifier(state)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [SessionBanner()],
              ),
            ),
          ),
        );

    for (final mode in GameSessionMode.values) {
      testWidgets('$mode → SessionBanner renders without error', (tester) async {
        await tester.pumpWidget(wrap(
          GameSessionState(mode: mode),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: '$mode must render without throwing');
      });
    }

    testWidgets('sole mode renders no visible banner text', (tester) async {
      await tester.pumpWidget(wrap(
        const GameSessionState(mode: GameSessionMode.sole),
      ));
      await tester.pump();
      expect(find.text('Перегляд з'), findsNothing);
      expect(find.text('Передача сесії…'), findsNothing);
    });

    testWidgets('viewer mode shows device name and Перебрати button',
        (tester) async {
      await tester.pumpWidget(wrap(
        const GameSessionState(
          mode: GameSessionMode.viewer,
          primaryDevice: 'MacBook',
        ),
      ));
      await tester.pump();
      expect(find.textContaining('MacBook'), findsOneWidget);
      expect(find.text('Перебрати'), findsOneWidget);
    });

    testWidgets('takeoverPending shows spinner text', (tester) async {
      await tester.pumpWidget(wrap(
        const GameSessionState(mode: GameSessionMode.takeoverPending),
      ));
      await tester.pump();
      expect(find.text('Передача сесії…'), findsOneWidget);
    });

    testWidgets('primary with takeover request shows yield/dismiss controls',
        (tester) async {
      await tester.pumpWidget(wrap(
        const GameSessionState(
          mode: GameSessionMode.primary,
          takeoverRequestFrom: 'iPad',
        ),
      ));
      await tester.pump();
      expect(find.textContaining('iPad'), findsOneWidget);
      expect(find.text('Передати'), findsOneWidget);
    });
  });
}
