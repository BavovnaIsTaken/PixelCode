import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/canvas/build_mode_logic.dart';

/// Builds a [BuildGhostInput] with a valid default scenario: a 2×2 room at
/// (1,1) in an 8×8 grid (inner 1..6), nothing in the way, affordable, under
/// cap. Override per test to exercise one failure at a time.
BuildGhostInput input({
  int col = 1,
  int row = 1,
  int width = 2,
  int height = 2,
  int gridCols = 8,
  int gridRows = 8,
  Set<String> blockedTiles = const {},
  List<PlacedRoom> rooms = const [],
  int roomCount = 0,
  int maxPerOffice = 5,
  int grymni = 1000,
  int roomCost = 100,
}) =>
    BuildGhostInput(
      col: col,
      row: row,
      width: width,
      height: height,
      gridCols: gridCols,
      gridRows: gridRows,
      blockedTiles: blockedTiles,
      rooms: rooms,
      roomCount: roomCount,
      maxPerOffice: maxPerOffice,
      grymni: grymni,
      roomCost: roomCost,
    );

PlacedRoom _roomAt(int col, int row) =>
    PlacedRoom(id: 'r', type: RoomType.values.first, col: col, row: row);

void main() {
  group('computeGhostStatus — green==placeable parity', () {
    test('fits in the lot, affordable, under cap → valid', () {
      final s = computeGhostStatus(input());
      expect(s.valid, isTrue);
      expect(s.reason, isNull);
    });

    test('at the per-type cap → invalid(atCap) — the headline "green but '
        'Place does nothing" bug', () {
      final s = computeGhostStatus(input(roomCount: 2, maxPerOffice: 2));
      expect(s.valid, isFalse);
      expect(s.reason, GhostInvalidReason.atCap);
    });

    test('left/top out of bounds → invalid(outOfBounds)', () {
      expect(computeGhostStatus(input(col: 0)).reason,
          GhostInvalidReason.outOfBounds);
      expect(computeGhostStatus(input(row: 0)).reason,
          GhostInvalidReason.outOfBounds);
    });

    test('overlapping a placed room → invalid(overlap)', () {
      final s = computeGhostStatus(input(rooms: [_roomAt(1, 1)]));
      expect(s.reason, GhostInvalidReason.overlap);
    });

    test('over a blocked tile inside the footprint → invalid(blocked)', () {
      // Ghost (1,1) 2×2 covers tiles 1,1 / 2,1 / 1,2 / 2,2.
      final s = computeGhostStatus(input(blockedTiles: {'2,2'}));
      expect(s.reason, GhostInvalidReason.blocked);
    });

    test('in-grid but unaffordable → invalid(insufficientGrymni) '
        '(previously showed green)', () {
      final s = computeGhostStatus(input(grymni: 50, roomCost: 100));
      expect(s.valid, isFalse);
      expect(s.reason, GhostInvalidReason.insufficientGrymni);
    });
  });

  group('computeGhostStatus — fixed-lot bounds (Stage 4)', () {
    // 6-wide grid (inner cols 1..4, wall at col 5); a 2-wide ghost at col 4
    // spills its far edge onto the wall (gc+gw=6 > gridCols-1=5).
    test('right edge spills past the wall → invalid(outOfBounds)', () {
      final s = computeGhostStatus(input(col: 4, gridCols: 6));
      expect(s.valid, isFalse);
      expect(s.reason, GhostInvalidReason.outOfBounds);
    });

    test('bottom edge spills past the wall → invalid(outOfBounds)', () {
      final s = computeGhostStatus(input(row: 4, gridRows: 6));
      expect(s.reason, GhostInvalidReason.outOfBounds);
    });

    test('footprint starting past the wall → invalid(outOfBounds)', () {
      final s = computeGhostStatus(
          input(col: 6, row: 1, width: 1, height: 1, gridCols: 6));
      expect(s.reason, GhostInvalidReason.outOfBounds);
    });

    test('1×1 in the last playable column → valid', () {
      // gridCols 6 → wall at 5, last playable col is 4.
      final s = computeGhostStatus(
          input(col: 4, row: 1, width: 1, height: 1, gridCols: 6));
      expect(s.valid, isTrue);
    });
  });

  group('connectingCorridorPath — preview == built', () {
    test('no rooms → empty path', () {
      expect(
        connectingCorridorPath(
          footLeft: 5,
          footTop: 1,
          footRight: 7,
          footBottom: 3,
          rooms: const [],
          gridCols: 20,
          gridRows: 20,
        ),
        isEmpty,
      );
    });

    test('a gap to the right of a room → bridges it (tiles in the gap)', () {
      final room = _roomAt(1, 1);
      final rRight = 1 + room.footprintWidth;
      final gLeft = rRight + 2; // 2-tile gap
      final path = connectingCorridorPath(
        footLeft: gLeft,
        footTop: 1,
        footRight: gLeft + 2,
        footBottom: 1 + room.footprintHeight,
        rooms: [room],
        gridCols: 30,
        gridRows: 30,
      );
      expect(path, isNotEmpty);
      for (final t in path) {
        expect(t.col >= rRight && t.col < gLeft, isTrue,
            reason: 'corridor tile $t must lie in the gap');
      }
    });

    test('room directly abutting (no gap) → empty (a door forms instead)', () {
      final room = _roomAt(1, 1);
      final rRight = 1 + room.footprintWidth;
      final path = connectingCorridorPath(
        footLeft: rRight, // touching the room's right edge
        footTop: 1,
        footRight: rRight + 2,
        footBottom: 1 + room.footprintHeight,
        rooms: [room],
        gridCols: 30,
        gridRows: 30,
      );
      expect(path, isEmpty);
    });
  });

  group('ghostTopLeft — center-anchor under the cursor', () {
    test('1×1 anchors exactly on the cursor tile', () {
      expect(ghostTopLeft(cursorCol: 3, cursorRow: 4, width: 1, height: 1),
          (col: 3, row: 4));
    });

    test('2×2 shifts up-left by one so the footprint straddles the cursor', () {
      expect(ghostTopLeft(cursorCol: 5, cursorRow: 5, width: 2, height: 2),
          (col: 4, row: 4));
    });

    test('odd dimensions centre the cursor in the footprint', () {
      expect(ghostTopLeft(cursorCol: 5, cursorRow: 5, width: 3, height: 1),
          (col: 4, row: 5));
    });
  });
}
