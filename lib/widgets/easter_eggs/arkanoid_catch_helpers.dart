/// Pure helpers for the Arkanoid sticky-catch state.
///
/// Extracted so the catch-launch arithmetic and the splat-tick clamp can
/// be unit-tested without spinning up the full painter / game widget.
library;

import 'dart:math';

/// Frames the capture-splat animation runs for after a ball is caught.
/// Must match `kCaptureSplatFrames` in `arkanoid_game.dart`.
const int kCaptureSplatFrames = 10;

/// Launch angle (radians, measured from +X axis, so −π/2 == straight up)
/// for a stuck ball, derived from where on the paddle the ball is sitting.
///
/// [hitFraction] is `(ballX − paddleLeft) / paddleWidth`, clamped to [0, 1].
/// Matches the formula used by both the in-flight collision and the
/// release-on-tap code paths so the aim-arrow preview is faithful.
double aimAngleForHit(double hitFraction) {
  final clamped = hitFraction.clamp(0.0, 1.0);
  return -pi / 2 + (clamped - 0.5) * 1.2;
}

/// Advance the per-ball capture-splat tick by one frame, clamped at the
/// max splat length. Pure so it's testable without `_Ball`.
int advanceCaptureTick(int current) {
  if (current >= kCaptureSplatFrames) return current;
  return current + 1;
}

/// True when the ball is still inside the capture-splat animation window
/// (the painter draws the radial pixel-burst + paddle squish during this).
bool inCaptureSplatWindow(int captureTick) =>
    captureTick < kCaptureSplatFrames;
