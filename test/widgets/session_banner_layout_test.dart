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

class _OfflineWsService extends AgentWsService {
  @override
  Stream<bool> get connectionStatus async* {
    yield false;
  }
}

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

class _TestCanvas extends StatelessWidget {
  const _TestCanvas();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
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
    Future<double> canvasWidth(WidgetTester tester) async {
      final finder = find.byKey(const Key('canvas'));
      expect(finder, findsOneWidget, reason: 'canvas container must be in tree');
      return tester.getSize(finder).width;
    }

    testWidgets('canvas is full width in offline mode', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(mode: GameSessionMode.offline),
      ));
      await tester.pump();
      expect(await canvasWidth(tester), greaterThan(0),
          reason: 'SessionBanner must return Positioned, not a bare SizedBox');
    });

    testWidgets('canvas is full width in sole mode', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(mode: GameSessionMode.sole),
      ));
      await tester.pump();
      expect(await canvasWidth(tester), greaterThan(0));
    });

    testWidgets('canvas is full width in primary mode', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(mode: GameSessionMode.primary),
      ));
      await tester.pump();
      expect(await canvasWidth(tester), greaterThan(0));
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

    testWidgets(
        'canvas stays full width after viewer → sole transition (the exact bug scenario)',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(
          mode: GameSessionMode.viewer,
          primaryDevice: 'Android',
        ),
      ));
      await tester.pump();
      final widthBefore = await canvasWidth(tester);
      expect(widthBefore, greaterThan(0));

      await tester.pumpWidget(_buildTestWidget(
        const GameSessionState(mode: GameSessionMode.sole),
      ));
      await tester.pump();
      final widthAfter = await canvasWidth(tester);

      expect(widthAfter, greaterThan(0),
          reason: 'office must stay visible after takeover completes');
      expect(widthAfter, equals(widthBefore),
          reason: 'canvas width must be unchanged after mode transition');
    });
  });

  group('SessionBanner always returns Positioned', () {
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
      testWidgets('$mode → renders without error', (tester) async {
        await tester.pumpWidget(wrap(GameSessionState(mode: mode)));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: '$mode must render without throwing');
      });
    }

    testWidgets('never shows any banner text (fully silent)', (tester) async {
      for (final mode in GameSessionMode.values) {
        await tester.pumpWidget(wrap(GameSessionState(mode: mode)));
        await tester.pump();
        expect(find.textContaining('Перегляд'), findsNothing,
            reason: '$mode must show no viewer text');
        expect(find.textContaining('Передача'), findsNothing,
            reason: '$mode must show no transfer text');
        expect(find.textContaining('Перебрати'), findsNothing,
            reason: '$mode must show no takeover button');
      }
    });
  });
}
