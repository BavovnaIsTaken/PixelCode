/// Widget tests for [SendButton].
///
/// The widget is rendered with `variantOverride` so the active-variant
/// provider doesn't need a fully wired game economy. Each variant has its
/// own paint subtree, so we assert variant-specific structural markers and
/// shared interaction semantics (tap → onPressed callback).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/send_button_style.dart';
import 'package:pixelcode/widgets/chat/send_button.dart';

Future<void> _pumpButton(
  WidgetTester tester, {
  required SendButtonVariant variant,
  required VoidCallback onPressed,
  double size = 44,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SendButton(
              variantOverride: variant,
              onPressed: onPressed,
              size: size,
            ),
          ),
        ),
      ),
    ),
  );
  // First frame only — the idle controller loops forever, so pumpAndSettle
  // would never return. A single pump is enough to render the initial state.
  await tester.pump();
}

void main() {
  group('SendButton — interaction', () {
    testWidgets('tap fires onPressed for classic variant', (tester) async {
      var taps = 0;
      await _pumpButton(
        tester,
        variant: SendButtonVariant.classic,
        onPressed: () => taps++,
      );
      await tester.tap(find.byType(SendButton));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('tap fires onPressed for neonPulse variant', (tester) async {
      var taps = 0;
      await _pumpButton(
        tester,
        variant: SendButtonVariant.neonPulse,
        onPressed: () => taps++,
      );
      await tester.tap(find.byType(SendButton));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('tap fires onPressed for goldRocket variant', (tester) async {
      var taps = 0;
      await _pumpButton(
        tester,
        variant: SendButtonVariant.goldRocket,
        onPressed: () => taps++,
      );
      await tester.tap(find.byType(SendButton));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('tap fires onPressed for pixelArcade variant',
        (tester) async {
      var taps = 0;
      await _pumpButton(
        tester,
        variant: SendButtonVariant.pixelArcade,
        onPressed: () => taps++,
      );
      await tester.tap(find.byType(SendButton));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('multiple taps each fire onPressed', (tester) async {
      var taps = 0;
      await _pumpButton(
        tester,
        variant: SendButtonVariant.classic,
        onPressed: () => taps++,
      );
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byType(SendButton));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(taps, 5);
    });

    testWidgets('tap-down then tap-cancel does not fire onPressed',
        (tester) async {
      var taps = 0;
      await _pumpButton(
        tester,
        variant: SendButtonVariant.classic,
        onPressed: () => taps++,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SendButton)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      // Move far away so the gesture turns into a cancelled tap.
      await gesture.moveBy(const Offset(500, 500));
      await gesture.up();
      await tester.pump();
      expect(taps, 0);
    });
  });

  group('SendButton — variant rendering', () {
    testWidgets('respects size argument', (tester) async {
      await _pumpButton(
        tester,
        variant: SendButtonVariant.classic,
        onPressed: () {},
        size: 60,
      );
      // Outermost SizedBox inside the body must match the requested size.
      final sized = tester
          .widgetList<SizedBox>(find.descendant(
            of: find.byType(SendButton),
            matching: find.byType(SizedBox),
          ))
          .firstWhere(
            (s) => s.width == 60.0 && s.height == 60.0,
            orElse: () => const SizedBox.shrink(),
          );
      expect(sized.width, 60);
      expect(sized.height, 60);
    });

    testWidgets('classic variant renders a send icon', (tester) async {
      await _pumpButton(
        tester,
        variant: SendButtonVariant.classic,
        onPressed: () {},
      );
      // Classic + neonPulse + goldRocket all render Icons.send_rounded.
      // pixelArcade uses a CustomPaint pixel arrow instead.
      expect(
        find.descendant(
          of: find.byType(SendButton),
          matching: find.byIcon(Icons.send_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('neonPulse variant renders a send icon', (tester) async {
      await _pumpButton(
        tester,
        variant: SendButtonVariant.neonPulse,
        onPressed: () {},
      );
      expect(
        find.descendant(
          of: find.byType(SendButton),
          matching: find.byIcon(Icons.send_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('goldRocket variant renders a send icon', (tester) async {
      await _pumpButton(
        tester,
        variant: SendButtonVariant.goldRocket,
        onPressed: () {},
      );
      expect(
        find.descendant(
          of: find.byType(SendButton),
          matching: find.byIcon(Icons.send_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('pixelArcade variant renders no Icons.send_rounded',
        (tester) async {
      // The pixel variant draws its arrow via CustomPaint instead of the
      // Material icon — so the icon family must be absent.
      await _pumpButton(
        tester,
        variant: SendButtonVariant.pixelArcade,
        onPressed: () {},
      );
      expect(
        find.descendant(
          of: find.byType(SendButton),
          matching: find.byIcon(Icons.send_rounded),
        ),
        findsNothing,
      );
      // …and there must be at least one CustomPaint (the pixel-arrow painter).
      expect(
        find.descendant(
          of: find.byType(SendButton),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
    });

    testWidgets('mounts and disposes without exception', (tester) async {
      await _pumpButton(
        tester,
        variant: SendButtonVariant.neonPulse,
        onPressed: () {},
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  });

  group('SendButton — variant override switching', () {
    testWidgets('rebuild with different variant swaps render path',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SendButton(
                variantOverride: SendButtonVariant.classic,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);

      // Swap to pixelArcade — now the Material send icon should disappear.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SendButton(
                variantOverride: SendButtonVariant.pixelArcade,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.send_rounded), findsNothing);
    });
  });
}
