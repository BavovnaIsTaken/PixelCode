/// Smoke tests for [BottomNotchPainter] — repaint signal + paint without
/// crashing on a reasonable canvas size.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/hub/bottom_notch_painter.dart';

void main() {
  test('shouldRepaint detects parameter changes', () {
    final a = BottomNotchPainter(
      fillColor: const Color(0xFF111111),
      strokeColor: const Color(0xFF222222),
      bottomBarInset: 24,
      flareRadius: 14,
    );
    final sameAsA = BottomNotchPainter(
      fillColor: const Color(0xFF111111),
      strokeColor: const Color(0xFF222222),
      bottomBarInset: 24,
      flareRadius: 14,
    );
    final differentInset = BottomNotchPainter(
      fillColor: const Color(0xFF111111),
      strokeColor: const Color(0xFF222222),
      bottomBarInset: 28,
      flareRadius: 14,
    );
    expect(a.shouldRepaint(sameAsA), false);
    expect(a.shouldRepaint(differentInset), true);
  });

  testWidgets('paints inside a CustomPaint without throwing',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 28,
              child: CustomPaint(
                painter: BottomNotchPainter(
                  fillColor: const Color(0xFF111111),
                  strokeColor: const Color(0xFF222222),
                  bottomBarInset: 24,
                  flareRadius: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
