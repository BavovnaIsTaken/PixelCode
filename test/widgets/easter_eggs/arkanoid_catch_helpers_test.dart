/// Unit tests for the sticky-catch helpers — covers the aim-angle
/// formula across the paddle, the splat-tick clamp, and the in-window
/// predicate. These are pure functions so no widget binding is needed.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/easter_eggs/arkanoid_catch_helpers.dart';

void main() {
  group('aimAngleForHit', () {
    test('centre of paddle launches straight up (positive)', () {
      // hit = 0.5 → angle == -π/2 (up)
      expect(aimAngleForHit(0.5), closeTo(-pi / 2, 1e-9));
    });

    test('left edge tilts left of vertical', () {
      // hit = 0.0 → angle = -π/2 + (-0.5) * 1.2 = -π/2 - 0.6
      final a = aimAngleForHit(0.0);
      expect(a, closeTo(-pi / 2 - 0.6, 1e-9));
      // Sanity: vector points up-and-left → cos negative, sin negative
      expect(cos(a), lessThan(0));
      expect(sin(a), lessThan(0));
    });

    test('right edge tilts right of vertical', () {
      final a = aimAngleForHit(1.0);
      expect(a, closeTo(-pi / 2 + 0.6, 1e-9));
      expect(cos(a), greaterThan(0));
      expect(sin(a), lessThan(0));
    });

    test('out-of-range inputs are clamped (negative path)', () {
      // Same as left/right edges — never produces a downward launch.
      expect(aimAngleForHit(-3.0), aimAngleForHit(0.0));
      expect(aimAngleForHit(99.0), aimAngleForHit(1.0));
    });

    test('NaN-free for all sane fractions across the paddle', () {
      for (var i = 0; i <= 20; i++) {
        final a = aimAngleForHit(i / 20);
        expect(a.isFinite, isTrue);
        // dy must always be negative (ball goes up after launch)
        expect(sin(a), lessThan(0));
      }
    });

    test('monotonic — moving right increases angle (rotates clockwise)', () {
      double prev = aimAngleForHit(0.0);
      for (var i = 1; i <= 10; i++) {
        final a = aimAngleForHit(i / 10);
        expect(a, greaterThan(prev),
            reason: 'angle should increase as hit fraction grows');
        prev = a;
      }
    });
  });

  group('advanceCaptureTick / inCaptureSplatWindow', () {
    test('advances by 1 inside the window (positive)', () {
      expect(advanceCaptureTick(0), 1);
      expect(advanceCaptureTick(5), 6);
    });

    test('clamps at kCaptureSplatFrames (boundary)', () {
      expect(advanceCaptureTick(kCaptureSplatFrames), kCaptureSplatFrames);
      expect(
          advanceCaptureTick(kCaptureSplatFrames + 1), kCaptureSplatFrames + 1,
          reason:
              'helper trusts caller; values above the cap are returned untouched');
    });

    test('inCaptureSplatWindow boundary semantics', () {
      expect(inCaptureSplatWindow(0), isTrue);
      expect(inCaptureSplatWindow(kCaptureSplatFrames - 1), isTrue);
      expect(inCaptureSplatWindow(kCaptureSplatFrames), isFalse,
          reason: 'window is half-open: [0, kCaptureSplatFrames)');
    });

    test('full lifecycle — splat window closes after kCaptureSplatFrames steps',
        () {
      var t = 0;
      var insideCount = 0;
      while (inCaptureSplatWindow(t)) {
        insideCount++;
        t = advanceCaptureTick(t);
        if (insideCount > 100) fail('loop did not terminate');
      }
      expect(insideCount, kCaptureSplatFrames);
    });
  });
}
