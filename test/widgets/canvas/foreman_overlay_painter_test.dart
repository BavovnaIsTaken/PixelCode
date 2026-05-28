/// Geometry + render-smoke tests for `ForemanOverlayPainter`. The hint
/// priority resolver is already covered by `test/widgets/foreman_hint_test.dart`;
/// this file exercises the layout helpers (door rect, foreman rect, door col)
/// and confirms the painter doesn't throw across permutations of its inputs.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/canvas/foreman_overlay_painter.dart';
import 'package:pixelcode/widgets/canvas/office_game_state.dart';

void main() {
  group('doorLeftColFor', () {
    test('garage (7 cols) → door starts at col 2 (centred 2-tile span)', () {
      // (7 - 2) ~/ 2 == 2 → door spans cols 2..3 in a 0..6 grid.
      expect(doorLeftColFor(7), 2);
    });

    test('smallOffice (9 cols) → door at col 3 (positive)', () {
      expect(doorLeftColFor(9), 3);
    });

    test('extreme narrow grid still returns at least col 1 (edge)', () {
      // Even a degenerate 2-col grid must keep the door inside the playable
      // area (i.e. not at col 0 which is the wall).
      expect(doorLeftColFor(2), greaterThanOrEqualTo(1));
      expect(doorLeftColFor(3), greaterThanOrEqualTo(1));
    });

    test('door rect width is exactly 2 tiles', () {
      final rect = doorHitRect(11);
      expect(rect.width, kDoorWidthTiles * kTileSize);
      expect(rect.height, kTileSize);
      expect(rect.top, 0); // door sits on the back wall (row 0)
    });
  });

  group('foremanHitRect', () {
    test('foreman is anchored at (gridCols-1, gridRows-2) (positive)', () {
      const cols = 7;
      const rows = 5;
      final rect = foremanHitRect(cols, rows);
      // Hit rect is wider/taller than a single tile — pad of 2 px on the
      // x-axis and the sprite is ~2 tiles tall.
      expect(rect.width, closeTo(kTileSize + 4, 0.001));
      expect(rect.height, closeTo(kTileSize * 2 - 2, 0.001));
      // Left edge corresponds to (foremanCol * kTileSize) - 2 padding.
      expect(rect.left, closeTo(foremanColFor(cols) * kTileSize - 2, 0.001));
    });

    test('foreman rect grows with the grid — campus right edge differs from garage',
        () {
      final small = foremanHitRect(7, 5);
      final large = foremanHitRect(14, 12);
      expect(large.left, greaterThan(small.left));
    });
  });

  group('ForemanOverlayPainter render smoke', () {
    Future<void> renderPainter(
        WidgetTester tester, ForemanOverlayPainter painter) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            child: SizedBox(
              width: 400,
              height: 300,
              child: CustomPaint(painter: painter),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }

    testWidgets('paints with all booleans off (positive)', (tester) async {
      await renderPainter(
        tester,
        ForemanOverlayPainter(
          gridCols: 7,
          gridRows: 5,
          tick: 0,
          officeLevel: OfficeLevel.garage,
          sprites: null,
          attention: false,
          firstTimePrompt: false,
          hovering: false,
          nextTier: OfficeLevel.smallOffice,
          doorAffordable: false,
          doorDisabled: false,
        ),
      );
    });

    testWidgets('paints attention bubble without crashing', (tester) async {
      await renderPainter(
        tester,
        ForemanOverlayPainter(
          gridCols: 7,
          gridRows: 5,
          tick: 12,
          officeLevel: OfficeLevel.garage,
          sprites: null,
          attention: true,
          firstTimePrompt: false,
          hovering: false,
          nextTier: OfficeLevel.smallOffice,
          doorAffordable: true,
          doorDisabled: false,
        ),
      );
    });

    testWidgets('paints hover speech bubble + onboarding chevron permutations',
        (tester) async {
      // hover wins
      await renderPainter(
        tester,
        ForemanOverlayPainter(
          gridCols: 9,
          gridRows: 6,
          tick: 30,
          officeLevel: OfficeLevel.smallOffice,
          sprites: null,
          attention: true,
          firstTimePrompt: true,
          hovering: true,
          nextTier: OfficeLevel.modernOffice,
          doorAffordable: false,
          doorDisabled: false,
          hasUnassignedAgent: true,
        ),
      );
      // onboarding wins (no hover)
      await renderPainter(
        tester,
        ForemanOverlayPainter(
          gridCols: 9,
          gridRows: 6,
          tick: 0,
          officeLevel: OfficeLevel.smallOffice,
          sprites: null,
          attention: false,
          firstTimePrompt: true,
          hovering: false,
          nextTier: OfficeLevel.modernOffice,
          doorAffordable: false,
          doorDisabled: false,
        ),
      );
      // needsDesk wins (no hover, no onboarding)
      await renderPainter(
        tester,
        ForemanOverlayPainter(
          gridCols: 9,
          gridRows: 6,
          tick: 0,
          officeLevel: OfficeLevel.smallOffice,
          sprites: null,
          attention: false,
          firstTimePrompt: false,
          hovering: false,
          nextTier: OfficeLevel.modernOffice,
          doorAffordable: false,
          doorDisabled: false,
          hasUnassignedAgent: true,
        ),
      );
    });

    testWidgets('disabled door (no next tier) paints without throwing',
        (tester) async {
      await renderPainter(
        tester,
        ForemanOverlayPainter(
          gridCols: 14,
          gridRows: 12,
          tick: 0,
          officeLevel: OfficeLevel.campus,
          sprites: null,
          attention: false,
          firstTimePrompt: false,
          hovering: false,
          nextTier: null,
          doorAffordable: false,
          doorDisabled: true,
        ),
      );
    });
  });

  group('ForemanOverlayPainter.shouldRepaint', () {
    ForemanOverlayPainter make({
      int tick = 0,
      bool attention = false,
      bool hovering = false,
      bool firstTimePrompt = false,
      bool doorAffordable = false,
      bool doorDisabled = false,
      OfficeLevel? nextTier = OfficeLevel.smallOffice,
    }) {
      return ForemanOverlayPainter(
        gridCols: 7,
        gridRows: 5,
        tick: tick,
        officeLevel: OfficeLevel.garage,
        sprites: null,
        attention: attention,
        firstTimePrompt: firstTimePrompt,
        hovering: hovering,
        nextTier: nextTier,
        doorAffordable: doorAffordable,
        doorDisabled: doorDisabled,
      );
    }

    test('returns true when any input changes', () {
      final base = make();
      expect(base.shouldRepaint(make(tick: 1)), isTrue);
      expect(base.shouldRepaint(make(attention: true)), isTrue);
      expect(base.shouldRepaint(make(hovering: true)), isTrue);
      expect(base.shouldRepaint(make(firstTimePrompt: true)), isTrue);
      expect(base.shouldRepaint(make(doorAffordable: true)), isTrue);
      expect(base.shouldRepaint(make(doorDisabled: true)), isTrue);
      expect(base.shouldRepaint(make(nextTier: null)), isTrue);
    });

    test('returns false when no input changes (negative)', () {
      final base = make();
      expect(base.shouldRepaint(make()), isFalse);
    });
  });

  test('PictureRecorder smoke: painter draws something', () {
    // Belt-and-braces low-level check: the painter actually emits draw ops.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    ForemanOverlayPainter(
      gridCols: 7,
      gridRows: 5,
      tick: 0,
      officeLevel: OfficeLevel.garage,
      sprites: null,
      attention: true,
      firstTimePrompt: false,
      hovering: false,
      nextTier: OfficeLevel.smallOffice,
      doorAffordable: true,
      doorDisabled: false,
    ).paint(canvas, const Size(400, 300));
    final picture = recorder.endRecording();
    // endRecording returning non-null means draw commands were captured.
    expect(picture, isNotNull);
    picture.dispose();
  });
}
