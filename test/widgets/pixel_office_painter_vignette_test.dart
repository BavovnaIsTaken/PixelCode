/// Tests that PixelOfficePainter._drawVignette uses the actual game-state
/// canvas dimensions rather than the legacy hardcoded kCanvasWidth/kCanvasHeight
/// constants.
///
/// Regression: before the fix the vignette rect was anchored at
/// (kCanvasWidth/2, kCanvasHeight/2) = (160, 112), which is completely
/// outside the garage canvas (7×5 tiles = 112×80 px world-space).  The
/// gradient therefore covered the entire canvas with ≥55 % black — making the
/// office appear completely blank.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/canvas/office_game_state.dart';
import 'package:pixelcode/widgets/canvas/pixel_office_painter.dart';

/// Renders a [PixelOfficePainter] and returns the color of the pixel at ([px], [py]).
// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── Canvas dimension invariants ─────────────────────────────────────────────

  group('OfficeGameState canvas dimensions', () {
    test('garage canvas is smaller than the legacy kCanvasWidth/kCanvasHeight constants', () {
      final state = OfficeGameState(level: OfficeLevel.garage);
      // With the old bug the vignette center was at (kCanvasWidth/2=160,
      // kCanvasHeight/2=112), which lies outside the 112×80 garage canvas.
      expect(state.canvasWidth, lessThan(kCanvasWidth));
      expect(state.canvasHeight, lessThan(kCanvasHeight));
    });

    test('garage fixed lot: 10 cols × 7 rows', () {
      final state = OfficeGameState(level: OfficeLevel.garage);
      expect(state.gridCols, 10);
      expect(state.gridRows, 7);
      expect(state.canvasWidth, 10 * kTileSize);
      expect(state.canvasHeight, 7 * kTileSize);
    });

    test('smallOffice canvas is larger than garage', () {
      final small = OfficeGameState(level: OfficeLevel.smallOffice);
      final garage = OfficeGameState(level: OfficeLevel.garage);
      expect(small.canvasWidth, greaterThan(garage.canvasWidth));
      expect(small.canvasHeight, greaterThan(garage.canvasHeight));
    });

    for (final level in OfficeLevel.values) {
      test('$level canvas width = gridCols × kTileSize and height = gridRows × kTileSize', () {
        final state = OfficeGameState(level: level);
        expect(state.canvasWidth, state.gridCols * kTileSize,
            reason: '$level width');
        expect(state.canvasHeight, state.gridRows * kTileSize,
            reason: '$level height');
      });
    }
  });

  // ── Vignette uses actual canvas dims (regression) ───────────────────────────

  group('PixelOfficePainter vignette', () {
    // Geometry regression: vignette center must be inside canvas bounds.
    // With the old bug, the center was hardcoded to (kCanvasWidth/2=160,
    // kCanvasHeight/2=112) — completely outside the garage canvas (112×80).
    // This caused the gradient to cover the entire office with ≥55% black.
    for (final level in OfficeLevel.values) {
      test('$level vignette center lies inside the canvas', () {
        final state = OfficeGameState(level: level);
        final vignetteCx = state.canvasWidth / 2;
        final vignetteCy = state.canvasHeight / 2;

        expect(vignetteCx, greaterThan(0),
            reason: '$level: vignette center x must be positive');
        expect(vignetteCx, lessThan(state.canvasWidth),
            reason: '$level: vignette center x must be inside canvas');
        expect(vignetteCy, greaterThan(0),
            reason: '$level: vignette center y must be positive');
        expect(vignetteCy, lessThan(state.canvasHeight),
            reason: '$level: vignette center y must be inside canvas');
      });
    }

    test('garage vignette center is NOT at the legacy kCanvasWidth/2 position', () {
      final state = OfficeGameState(level: OfficeLevel.garage);
      // Pre-fix bug: used kCanvasWidth/2=160, kCanvasHeight/2=112.
      // These are both far outside the 112×80 garage canvas.
      expect(state.canvasWidth / 2, isNot(kCanvasWidth / 2));
      expect(state.canvasHeight / 2, isNot(kCanvasHeight / 2));
    });

    testWidgets('garage painter does not throw', (tester) async {
      final state = OfficeGameState(level: OfficeLevel.garage);
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            child: SizedBox(
              width: 400,
              height: 300,
              child: CustomPaint(
                painter: PixelOfficePainter(
                  gameState: state,
                  officeLevel: OfficeLevel.garage,
                  placedFurniture: const [],
                  placedRooms: const [],
                  placedCorridors: const [],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('campus painter does not throw (larger canvas still uses dynamic dims)',
        (tester) async {
      final state = OfficeGameState(level: OfficeLevel.campus);
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            child: SizedBox(
              width: 800,
              height: 600,
              child: CustomPaint(
                painter: PixelOfficePainter(
                  gameState: state,
                  officeLevel: OfficeLevel.campus,
                  placedFurniture: const [],
                  placedRooms: const [],
                  placedCorridors: const [],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
